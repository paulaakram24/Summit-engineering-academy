import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../content/content_models.dart' show formatPricePiasters;
import 'catalog_repository.dart';

typedef CatalogCoverLoader = Future<Uint8List?> Function(CatalogCourse course);

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.auth,
    required this.repository,
    this.loadCover,
  });
  final AuthController auth;
  final CatalogRepository repository;
  final CatalogCoverLoader? loadCover;
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
  bool get _allowed =>
      !_closed &&
      widget.auth.stage == AuthStage.ready &&
      identical(widget.auth.access, _access) &&
      _actor != null &&
      isCatalogUuid(_actor!) &&
      widget.repository.currentActorId?.toLowerCase() == _actor!.toLowerCase();

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
        oldWidget.loadCover != widget.loadCover) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      _close();
    }
  }

  void _close() {
    if (_closed) return;
    ++_epoch;
    _closed = true;
    _courses.clear();
    _outlines.clear();
    _course = null;
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
    if (_busy && more) return;
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
      final filters = _filters ?? await widget.repository.getFilters();
      if (!_current(epoch)) return;
      final page = await widget.repository.listCourses(
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
      });
    } catch (error) {
      if (_current(epoch) && !_fatal(error)) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  String _failure(Object error) => error is CatalogFailure
      ? error.message
      : 'Unable to load the catalog. Check your connection and access, then retry.';

  bool _fatal(Object error) {
    if (error is CatalogFailure &&
        (error.kind == CatalogFailureKind.accessRequired ||
            error.kind == CatalogFailureKind.actorChanged)) {
      _close();
      return true;
    }
    return false;
  }

  Future<void> _details(String id, {bool more = false}) async {
    if (!_allowed) {
      _close();
      return;
    }
    if (_busy && more) return;
    final after = more ? _sessions?.nextCursor : null;
    if (more && after == null) return;
    final epoch = ++_epoch;
    if (_detailId == null && _catalogScroll.hasClients) {
      _catalogOffset = _catalogScroll.offset;
    }
    setState(() {
      _busy = true;
      _error = null;
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
        setState(() {
          // This is confirmed withdrawal, not a transient loading error. Do
          // not restore an old card/cover or cursor when the user goes Back.
          _courses.clear();
          _page = null;
          _dirty = true;
          _catalogOffset = 0;
          _course = null;
          _outlines.clear();
          _sessions = null;
          _unavailable = true;
        });
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
      appBar: AppBar(title: const Text('Browse courses')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: !_allowed
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Catalog access closed. Go back and reopen after account verification.',
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
    if (_busy) const LinearProgressIndicator(semanticsLabel: 'Loading catalog'),
    if (_error != null) ...[
      Text(_error!, semanticsLabel: _error),
      TextButton(
        onPressed: _busy ? null : () => _load(),
        child: const Text('Retry catalog'),
      ),
    ],
    if (_dirty) const Text('Tap Search to update results.'),
    if (!_dirty &&
        !_busy &&
        _error == null &&
        _page != null &&
        _courses.isEmpty)
      Text(
        trimCatalogSpaces(_search.text).isEmpty &&
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
                onPressed: _busy ? null : () => _details(course.id),
                child: Text('View course: ${course.title}'),
              ),
            ],
          ),
        ),
      ),
    if (_page?.hasMore == true && !_dirty)
      OutlinedButton(
        onPressed: _busy || _error != null ? null : () => _load(more: true),
        child: const Text('Load more courses'),
      ),
  ];

  Widget _filter(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value:${values.join('|')}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String>(value: null, child: Text('All')),
      for (final item in [
        if (value != null && !values.contains(value)) value,
        ...values,
      ])
        DropdownMenuItem(
          value: item,
          child: Text(item, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );

  List<Widget> _detail(BuildContext context) => [
    TextButton(onPressed: _backToCatalog, child: const Text('Back to catalog')),
    if (_busy) const LinearProgressIndicator(semanticsLabel: 'Loading course'),
    if (_error != null) ...[
      Text(_error!),
      TextButton(
        onPressed: _busy ? null : () => _details(_detailId!),
        child: const Text('Retry course'),
      ),
    ],
    if (_unavailable)
      const Text('This course is unavailable. It may have been removed.'),
    if (_course case final course?) ...[
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
      if (!_busy && _outlines.isEmpty) const Text('No published sessions yet.'),
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
