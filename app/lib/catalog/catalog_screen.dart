import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../bookmarks/bookmark_repository.dart';
import '../content/content_models.dart' show formatPricePiasters;
import 'catalog_repository.dart';

typedef CatalogCoverLoader = Future<Uint8List?> Function(CatalogCourse course);

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.auth,
    required this.repository,
    this.loadCover,
    this.bookmarkRepository,
    this.savedOnly = false,
  });
  final AuthController auth;
  final CatalogRepository repository;
  final CatalogCoverLoader? loadCover;
  final BookmarkRepository? bookmarkRepository;
  final bool savedOnly;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _catalogScroll = ScrollController(), _detailScroll = ScrollController();
  double _catalogOffset = 0;
  late Object? _access;
  late String? _actor;
  int _epoch = 0;
  bool _closed = false, _busy = false, _dirty = false;
  String? _category, _level, _error;
  CatalogFilters? _filters;
  CatalogPage<CatalogCourse>? _page;
  CatalogCourse? _course;
  CatalogPage<CatalogSession>? _sessions;
  final _courses = <CatalogCourse>[];
  final _outlines = <CatalogSession>[];
  bool _unavailable = false;
  CourseBookmark? _bookmark;
  DialogRoute<bool>? _cleanupDialog;
  bool _cleanupConfirming = false, _cleanupRefreshRequired = false;
  int? _cleanupCount;
  bool get _allowed =>
      !_closed &&
      widget.auth.stage == AuthStage.ready &&
      identical(widget.auth.access, _access) &&
      _actor != null &&
      isCatalogUuid(_actor!) &&
      widget.repository.currentActorId?.toLowerCase() ==
          _actor!.toLowerCase() &&
      (!widget.savedOnly || widget.bookmarkRepository != null) &&
      (widget.bookmarkRepository == null ||
          widget.bookmarkRepository!.currentActorId?.toLowerCase() ==
              _actor!.toLowerCase());

  @override
  void initState() {
    super.initState();
    _access = widget.auth.access;
    _actor = widget.repository.currentActorId;
    widget.auth.addListener(_authChanged);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (!_allowed || (state != null && state != AppLifecycleState.resumed)) {
      _closed = true;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth ||
        oldWidget.repository != widget.repository ||
        oldWidget.loadCover != widget.loadCover ||
        oldWidget.bookmarkRepository != widget.bookmarkRepository ||
        oldWidget.savedOnly != widget.savedOnly) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      _close();
    }
  }

  void _close() {
    if (_closed) return;
    ++_epoch;
    _closed = true;
    _dismissCleanupDialog();
    _cleanupCount = null;
    _cleanupConfirming = false;
    _courses.clear();
    _outlines.clear();
    _course = null;
    _bookmark = null;
    _page = null;
    _sessions = null;
    _filters = null;
    _category = _level = _error = null;
    _search.clear();
    _busy = false;
    if (mounted) setState(() {});
  }

  void _authChanged() {
    if (!_allowed) _close();
  }

  bool _current(int epoch) {
    if (!mounted) return false;
    if (!_allowed) {
      _close();
      return false;
    }
    return epoch == _epoch;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  @override
  void dispose() {
    ++_epoch;
    _dismissCleanupDialog();
    widget.auth.removeListener(_authChanged);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _catalogScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _criteriaChanged() {
    ++_epoch;
    setState(() {
      _dirty = true;
      _busy = false;
      _error = null;
      _page = null;
      _courses.clear();
    });
  }

  Future<void> _load({bool more = false}) async {
    if (!_allowed) {
      _close();
      return;
    }
    if (_cleanupConfirming || (_busy && more)) return;
    final epoch = ++_epoch;
    final after = more ? _page?.nextCursor : null;
    if (more && after == null) return;
    final search = _search.text, category = _category, level = _level;
    setState(() {
      _busy = true;
      _dirty = false;
      _error = null;
      if (!more) {
        _courses.clear();
        _page = null;
      }
    });
    try {
      final filters = widget.savedOnly
          ? null
          : _filters ?? await widget.repository.getFilters();
      if (!_current(epoch)) return;
      final page = widget.savedOnly
          ? await widget.bookmarkRepository!.listSavedCourses(after: after)
          : await widget.repository.listCourses(
              search: search,
              category: category,
              level: level,
              after: after,
            );
      if (!_current(epoch)) return;
      if (page.items.any(
        (item) => _courses.any(
          (old) => old.id.toLowerCase() == item.id.toLowerCase(),
        ),
      )) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      setState(() {
        _filters = filters;
        _courses.addAll(page.items);
        _page = page;
        if (!more) _cleanupRefreshRequired = false;
      });
    } catch (error) {
      if (_current(epoch) && !_fatal(error)) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  String _failure(Object error) => error is BookmarkFailure
      ? error.message
      : error is CatalogFailure
      ? error.message
      : 'Unable to load the catalog. Check your connection and access, then retry.';

  bool _fatal(Object error) {
    if (error is BookmarkFailure &&
        (error.kind == BookmarkFailureKind.accessRequired ||
            error.kind == BookmarkFailureKind.actorChanged)) {
      _close();
      return true;
    }
    if (error is CatalogFailure &&
        (error.kind == CatalogFailureKind.accessRequired ||
            error.kind == CatalogFailureKind.actorChanged)) {
      _close();
      return true;
    }
    return false;
  }

  void _invalidateCards() {
    _courses.clear();
    _page = null;
    _dirty = true;
    _catalogOffset = 0;
  }

  void _withdraw() {
    setState(() {
      _invalidateCards();
      _course = null;
      _bookmark = null;
      _outlines.clear();
      _sessions = null;
      _unavailable = true;
    });
  }

  void _dismissCleanupDialog() {
    final route = _cleanupDialog;
    _cleanupDialog = null;
    if (route == null) return;
    // Invalidation may happen during build/dispose. Remove this exact route
    // after the frame, even if another route has since been placed above it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
  }

  Future<void> _clearUnavailableBookmarks() async {
    if (!_allowed) {
      _close();
      return;
    }
    final repository = widget.bookmarkRepository;
    if (!widget.savedOnly ||
        repository == null ||
        _busy ||
        _cleanupConfirming ||
        _cleanupRefreshRequired) {
      return;
    }
    final actor = repository.currentActorId!;
    final epoch = ++_epoch;
    setState(() => _cleanupConfirming = true);
    late final DialogRoute<bool> route;
    void finish(bool confirmed) {
      if (confirmed &&
          (!_current(epoch) ||
              !identical(_cleanupDialog, route) ||
              !route.isCurrent)) {
        return;
      }
      final navigator = route.navigator;
      if (navigator != null && route.isActive) {
        navigator.removeRoute(route, confirmed);
      }
    }

    route = DialogRoute<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: const Text('Remove unavailable saved courses?'),
        content: const Text(
          'Only your saved references to courses that are currently unavailable will be removed. Available saved courses stay saved. Purchases and enrollments are unchanged. No hidden course details will be shown.',
        ),
        actions: [
          TextButton(
            onPressed: () => finish(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => finish(true),
            child: const Text(
              'Remove',
              semanticsLabel: 'Remove unavailable saved references',
            ),
          ),
        ],
      ),
    );
    _cleanupDialog = route;
    bool? confirmed;
    try {
      confirmed = await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      if (identical(_cleanupDialog, route)) _cleanupDialog = null;
      if (_current(epoch)) setState(() => _cleanupConfirming = false);
    }
    if (confirmed != true || !_current(epoch)) return;
    setState(() {
      _busy = true;
      _cleanupCount = null;
      _cleanupRefreshRequired = true;
      _error = null;
      _invalidateCards();
    });
    try {
      final count = await repository.clearUnavailableBookmarks(actorId: actor);
      if (!_current(epoch)) return;
      if (count < 0 || count > catalogMaxInteger) {
        throw const BookmarkFailure(BookmarkFailureKind.invalidResponse);
      }
      setState(() => _cleanupCount = count);
      await _load();
    } catch (error) {
      if (!_current(epoch) || _fatal(error)) return;
      setState(() {
        _invalidateCards();
        _error = 'Removal could not be confirmed and may already have completed. Refresh saved courses before another change. No automatic retry was sent.';
      });
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _changeBookmark(bool saved) async {
    if (!_allowed) {
      _close();
      return;
    }
    final repository = widget.bookmarkRepository;
    if (_busy ||
        _cleanupConfirming ||
        _cleanupRefreshRequired ||
        repository == null ||
        _bookmark == null ||
        _course == null) {
      return;
    }
    final epoch = ++_epoch;
    final id = _course!.id;
    final intent = SetCourseBookmarkRequest(
      actorId: repository.currentActorId!,
      courseId: id,
      saved: saved,
      expectedRevision: _bookmark!.revision,
    );
    setState(() {
      _busy = true;
      _error = null;
      _invalidateCards();
    });
    try {
      await repository.setBookmark(intent);
      if (!_current(epoch)) return;
      // Never merge a mutation response into an obsolete metadata/state view.
      setState(_invalidateCards);
      await _details(id);
    } catch (error) {
      if (!_current(epoch) || _fatal(error)) return;
      if (error is BookmarkFailure &&
          error.kind == BookmarkFailureKind.courseUnavailable) {
        _withdraw();
      } else {
        setState(() {
          _invalidateCards();
          _bookmark = null;
          _error =
              error is BookmarkFailure &&
                  error.kind == BookmarkFailureKind.stateConflict
              ? 'Saved-course state changed. Retry course to refresh before another change. No automatic retry was sent.'
              : 'The bookmark change could not be confirmed and may already have saved. Retry course to refresh before another change. No automatic retry was sent.';
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _details(String id, {bool more = false}) async {
    if (!_allowed) {
      _close();
      return;
    }
    if (_cleanupConfirming || (_busy && more)) return;
    final after = more ? _sessions?.nextCursor : null;
    if (more && after == null) return;
    final epoch = ++_epoch;
    if (_detailId == null && _catalogScroll.hasClients) {
      _catalogOffset = _catalogScroll.offset;
    }
    setState(() {
      _busy = true;
      _error = null;
      _bookmark = null;
      _unavailable = false;
      if (!more) {
        _course = null;
        _sessions = null;
        _outlines.clear();
      }
      _detailId = id;
    });
    try {
      // Refetch even when loading another outline page: removed parents must
      // not leave their old description visible indefinitely.
      final course = await widget.repository.getCourse(id);
      if (!_current(epoch)) return;
      if (course == null) {
        _withdraw();
        return;
      }
      final bookmark = widget.bookmarkRepository == null
          ? null
          : await widget.bookmarkRepository!.getBookmark(id);
      if (!_current(epoch)) return;
      if (widget.bookmarkRepository != null && bookmark == null) {
        _withdraw();
        return;
      }
      final page = await widget.repository.listSessions(id, after: after);
      if (!_current(epoch)) return;
      if (page.items.any(
        (item) =>
            item.courseId.toLowerCase() != id.toLowerCase() ||
            _outlines.any(
              (old) => old.id.toLowerCase() == item.id.toLowerCase(),
            ),
      )) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      setState(() {
        _course = course;
        _bookmark = bookmark;
        _outlines.addAll(page.items);
        _sessions = page;
      });
    } catch (error) {
      if (_current(epoch) && !_fatal(error)) {
        setState(() {
          _course = null;
          _outlines.clear();
          _sessions = null;
          _error = _failure(error);
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  String? _detailId;
  void _backToCatalog() {
    ++_epoch;
    setState(() {
      _detailId = null;
      _course = null;
      _bookmark = null;
      _sessions = null;
      _outlines.clear();
      _busy = false;
      _error = null;
      _unavailable = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _allowed &&
          _detailId == null &&
          _catalogScroll.hasClients) {
        _catalogScroll.jumpTo(
          _catalogOffset.clamp(0.0, _catalogScroll.position.maxScrollExtent),
        );
      }
    });
  }

  Widget _cover(CatalogCourse course) => _CatalogCover(
    key: ValueKey(
      '${identityHashCode(_access)}:${course.id}:${course.coverPath}',
    ),
    course: course,
    load: widget.loadCover,
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _detailId == null || _closed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_closed) _backToCatalog();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.savedOnly ? 'Saved courses' : 'Browse courses'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: !_allowed
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Catalog access closed. Go back and reopen after account verification.',
                      ),
                    ),
                  )
                : ListView(
                    key: PageStorageKey(
                      _detailId == null
                          ? 'catalog-list'
                          : 'catalog-detail:$_detailId',
                    ),
                    controller: _detailId == null
                        ? _catalogScroll
                        : _detailScroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_detailId == null)
                        ..._catalog(context)
                      else
                        ..._detail(context),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _catalog(BuildContext context) => [
    if (widget.savedOnly) ...[
      const Text(bookmarkDisclaimer),
      TextButton(
        onPressed: _busy || _cleanupConfirming ? null : () => _load(),
        child: const Text('Refresh saved courses'),
      ),
      TextButton(
        onPressed: _busy || _cleanupConfirming || _cleanupRefreshRequired
            ? null
            : _clearUnavailableBookmarks,
        child: const Text('Remove unavailable saved courses'),
      ),
      if (_cleanupCount != null)
        _status(
          'Removed $_cleanupCount unavailable saved course${_cleanupCount == 1 ? '' : 's'}.',
        ),
    ],
    if (!widget.savedOnly) ...[
      TextField(
        controller: _search,
        maxLength: 100,
        decoration: const InputDecoration(
          labelText: 'Search courses',
          hintText: 'Title, instructor or category',
        ),
        textInputAction: TextInputAction.search,
        onChanged: (_) => _criteriaChanged(),
        onSubmitted: (_) => _load(),
      ),
      if (_filters != null) ...[
        _filter('Category', _category, _filters!.categories, (value) {
          _category = value;
          _criteriaChanged();
          _load();
        }),
        _filter('Level / year', _level, _filters!.levels, (value) {
          _level = value;
          _criteriaChanged();
          _load();
        }),
      ],
      Wrap(
        spacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _load();
                  },
            icon: const Icon(Icons.search),
            label: const Text('Search'),
          ),
          TextButton(
            onPressed: () {
              _search.clear();
              _category = _level = null;
              _criteriaChanged();
              _filters = null;
              _load();
            },
            child: const Text('Clear filters'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    _filters = null;
                    _load();
                  },
            child: const Text('Refresh catalog'),
          ),
        ],
      ),
    ],
    if (_busy) const LinearProgressIndicator(semanticsLabel: 'Loading catalog'),
    if (_error != null) ...[
      _status(_error!),
      TextButton(
        onPressed: _busy ? null : () => _load(),
        child: const Text('Retry catalog'),
      ),
    ],
    if (_dirty)
      Text(
        widget.savedOnly
            ? 'Refresh saved courses to update results.'
            : 'Tap Search to update results.',
      ),
    if (!_dirty &&
        !_busy &&
        _error == null &&
        _page != null &&
        _courses.isEmpty)
      _status(
        widget.savedOnly
            ? 'No available saved courses. Browse courses to save one for later.'
            : trimCatalogSpaces(_search.text).isEmpty &&
                  _category == null &&
                  _level == null
            ? 'No published courses yet.'
            : 'No courses match your search or filters.',
      ),
    for (final course in _courses)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(course),
              Text(course.title, style: Theme.of(context).textTheme.titleLarge),
              Text(course.instructor),
              Text('${course.category} · ${course.level}'),
              Text('${formatPricePiasters(course.pricePiasters)} EGP'),
              OutlinedButton(
                onPressed: _busy || _cleanupConfirming
                    ? null
                    : () => _details(course.id),
                child: Text('View course: ${course.title}'),
              ),
            ],
          ),
        ),
      ),
    if (_page?.hasMore == true && !_dirty)
      OutlinedButton(
        onPressed: _busy || _cleanupConfirming || _error != null
            ? null
            : () => _load(more: true),
        child: const Text('Load more courses'),
      ),
  ];

  Widget _status(String message) =>
      Semantics(liveRegion: true, child: Text(message));

  Widget _filter(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value:${values.join('|')}'),
    initialValue: value,
    isExpanded: true,
    isDense: false,
    itemHeight: null,
    // Keep the closed field bounded even when an unselected option is long.
    // The menu below wraps the complete label; long-press also reveals it here.
    selectedItemBuilder: (context) => [
      const Text('All'),
      for (final item in [
        if (value != null && !values.contains(value)) value,
        ...values,
      ])
        Tooltip(
          message: item,
          excludeFromSemantics: true,
          child: Text(item, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
    ],
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String>(value: null, child: Text('All')),
      for (final item in [
        if (value != null && !values.contains(value)) value,
        ...values,
      ])
        DropdownMenuItem(value: item, child: Text(item)),
    ],
    onChanged: onChanged,
  );

  List<Widget> _detail(BuildContext context) => [
    TextButton(onPressed: _backToCatalog, child: const Text('Back to catalog')),
    if (_busy) const LinearProgressIndicator(semanticsLabel: 'Loading course'),
    if (_error != null) ...[
      _status(_error!),
      TextButton(
        onPressed: _busy ? null : () => _details(_detailId!),
        child: const Text('Retry course'),
      ),
    ],
    if (_unavailable)
      _status('This course is unavailable. It may have been removed.'),
    if (_course case final course?) ...[
      if (widget.bookmarkRepository != null) ...[
        const Text(bookmarkDisclaimer),
        if (_bookmark != null)
          _status(
            _bookmark!.saved ? 'Course saved for later.' : 'Course not saved.',
          ),
        MergeSemantics(
          child: Semantics(
            toggled: _bookmark?.saved ?? false,
            child: FilledButton.icon(
              onPressed: _busy || _bookmark == null
                  ? null
                  : () => _changeBookmark(!_bookmark!.saved),
              icon: Icon(
                _bookmark?.saved == true
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              label: Text(
                _bookmark?.saved == true
                    ? 'Remove from saved courses'
                    : 'Save course for later',
              ),
            ),
          ),
        ),
      ],
      _cover(course),
      Text(course.title, style: Theme.of(context).textTheme.headlineSmall),
      Text(course.instructor),
      Text('${course.category} · ${course.level}'),
      Text('Course price: ${formatPricePiasters(course.pricePiasters)} EGP'),
      Text(course.description),
      const SizedBox(height: 16),
      Text('Session outline', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Descriptions only. Purchases, access status and protected playback are not available yet.',
      ),
      if (!_busy && _outlines.isEmpty) _status('No published sessions yet.'),
      for (final session in _outlines)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${session.sessionNumber}. ${session.title}'),
                Text(session.description),
                Text('${formatPricePiasters(session.pricePiasters)} EGP'),
                if (session.isFreePreview)
                  const Text('Preview designated — playback not enabled'),
              ],
            ),
          ),
        ),
      if (_sessions?.hasMore == true)
        OutlinedButton(
          onPressed: _busy ? null : () => _details(course.id, more: true),
          child: const Text('Load more sessions'),
        ),
    ],
  ];
}

class _CatalogCover extends StatefulWidget {
  const _CatalogCover({super.key, required this.course, this.load});
  final CatalogCourse course;
  final CatalogCoverLoader? load;
  @override
  State<_CatalogCover> createState() => _CatalogCoverState();
}

class _CatalogCoverState extends State<_CatalogCover> {
  Uint8List? _bytes;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CatalogCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.coverPath != widget.course.coverPath ||
        oldWidget.course.id != widget.course.id ||
        oldWidget.load != widget.load) {
      _clear();
      _load();
    }
  }

  void _clear() {
    ++_epoch;
    if (_bytes != null) MemoryImage(_bytes!).evict();
    _bytes = null;
  }

  Future<void> _load() async {
    if (widget.course.coverPath == null || widget.load == null) return;
    final epoch = ++_epoch;
    try {
      final bytes = await widget.load!(widget.course);
      if (mounted &&
          epoch == _epoch &&
          bytes != null &&
          bytes.length <= 3 * 1024 * 1024) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      /* Keep the accessible fallback; never render a raw error. */
    }
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _bytes == null
        ? Semantics(
            label: 'Course cover unavailable',
            child: const SizedBox(
              height: 80,
              child: Center(child: Icon(Icons.school_outlined, size: 48)),
            ),
          )
        : Image.memory(
            _bytes!,
            height: 140,
            width: double.infinity,
            fit: BoxFit.contain,
            semanticLabel: '${widget.course.title} course cover',
            errorBuilder: (_, _, _) => const Text('Course cover unavailable'),
          ),
  );
}
