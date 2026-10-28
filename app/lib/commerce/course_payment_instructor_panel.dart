import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../catalog/catalog_models.dart' show isCatalogUuid;
import '../content/content_models.dart';
import 'instructor_payment_repository.dart';

/// Administrator assignment setup only. Never presents receiving instructions.
class CoursePaymentInstructorPanel extends StatefulWidget {
  const CoursePaymentInstructorPanel({
    super.key,
    required this.course,
    required this.auth,
    required this.repository,
    required this.onClose,
  });

  final Course course;
  final AuthController auth;
  final InstructorPaymentRepository repository;
  final VoidCallback onClose;

  @override
  State<CoursePaymentInstructorPanel> createState() =>
      _CoursePaymentInstructorPanelState();
}

class _CoursePaymentInstructorPanelState
    extends State<CoursePaymentInstructorPanel>
    with WidgetsBindingObserver {
  String? _actor, _device, _selected, _error, _notice;
  Object? _access;
  CoursePaymentInstructor? _binding;
  List<PaymentInstructorDirectoryEntry> _rows = [];
  PaymentInstructorCursor? _cursor;
  bool _hasMore = false, _fresh = false, _busy = false;
  bool _invalidated = false, _foreground = true;
  bool _confirming = false;
  bool _closed = false;
  int _epoch = 0;
  DialogRoute<bool>? _dialog;
  NavigatorState? _dialogNavigator;
  ValueNotifier<bool>? _dialogGuard;

  String? get _liveActor {
    try {
      return widget.repository.currentActorId?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  bool get _identityMatches =>
      !_closed &&
      !_invalidated &&
      _foreground &&
      widget.auth.stage == AuthStage.ready &&
      widget.auth.access?.role == 'admin' &&
      identical(widget.auth.access, _access) &&
      widget.auth.access?.deviceId == _device &&
      _actor != null &&
      isCatalogUuid(_actor!) &&
      _liveActor == _actor;
  bool get _courseLive =>
      isCatalogUuid(widget.course.id) && !widget.course.isDeleted;
  bool get _dirty => _selected != null;
  bool get _writable =>
      _identityMatches &&
      _courseLive &&
      _fresh &&
      !_busy &&
      (_binding?.revision ?? 0) < instructorPaymentMaxRevision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_authChanged);
    _capture();
    if (_identityMatches && _courseLive) _load();
  }

  void _capture() {
    _actor = _liveActor;
    _access = widget.auth.access;
    _device = widget.auth.access?.deviceId;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _clear() {
    _binding = null;
    _rows = [];
    _selected = null;
    _cursor = null;
    _fresh = _hasMore = false;
  }

  void _dismissDialog({bool notifyGuard = true}) {
    if (notifyGuard) _dialogGuard?.value = false;
    final route = _dialog;
    final navigator = _dialogNavigator;
    _dialog = null;
    _dialogNavigator = null;
    if (route != null && navigator != null) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) {
          navigator.removeRoute(route, false);
        }
      });
    }
  }

  void _invalidate() {
    if (_invalidated) return;
    ++_epoch;
    _invalidated = true;
    _dismissDialog();
    _clear();
    _busy = _confirming = false;
    _error = _notice = null;
    if (mounted) setState(() {});
  }

  void _authChanged() {
    if (!_identityMatches) _invalidate();
  }

  bool _check() {
    if (!mounted || _closed) return false;
    if (!_identityMatches) {
      _invalidate();
      return false;
    }
    return true;
  }

  bool _current(int epoch) => _check() && epoch == _epoch;

  @override
  void didUpdateWidget(CoursePaymentInstructorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.auth, widget.auth) ||
        !identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.course, widget.course)) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      if (_closed) return;
      ++_epoch;
      _dismissDialog(notifyGuard: false);
      _clear();
      _invalidated = _busy = _confirming = false;
      _error = _notice = null;
      _capture();
      if (_identityMatches && _courseLive) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  @override
  void dispose() {
    ++_epoch;
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    _dismissDialog(notifyGuard: false);
    super.dispose();
  }

  void _failed(Object error) {
    if (error is InstructorPaymentFailure &&
        (error.kind == InstructorPaymentFailureKind.accessRequired ||
            error.kind == InstructorPaymentFailureKind.actorChanged)) {
      _invalidate();
      return;
    }
    setState(() {
      _clear();
      _busy = false;
      _notice = null;
      // Never render raw transport exceptions, phone numbers or private payloads.
      _error = error is InstructorPaymentFailure
          ? InstructorPaymentFailure(error.kind).message
          : const InstructorPaymentFailure(
              InstructorPaymentFailureKind.invalidResponse,
            ).message;
    });
  }

  void _validatePage(
    PaymentInstructorPage page,
    PaymentInstructorCursor? after,
  ) {
    PaymentInstructorPage(
      items: page.items,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
      limit: paymentInstructorDefaultLimit,
      after: after,
    );
    final known = _rows.map((row) => row.instructorId).toSet();
    if (page.items.any((row) => known.contains(row.instructorId))) {
      throw const InstructorPaymentModelFailure();
    }
  }

  Future<void> _load({String? notice}) async {
    if (!_check() || !_courseLive) return;
    final epoch = ++_epoch;
    final repository = widget.repository;
    final courseId = widget.course.id.toLowerCase();
    final actor = _actor!;
    setState(() {
      _clear();
      _busy = true;
      _error = _notice = null;
    });
    try {
      final binding = await repository.getCourseInstructor(
        actorId: actor,
        courseId: courseId,
      );
      if (!_current(epoch)) return;
      if (binding != null && binding.courseId != courseId) {
        throw const InstructorPaymentModelFailure();
      }
      final page = await repository.listInstructors(
        actorId: actor,
        limit: paymentInstructorDefaultLimit,
      );
      if (!_current(epoch)) return;
      _validatePage(page, null);
      setState(() {
        _binding = binding;
        _rows = page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _fresh = true;
        _busy = false;
        _notice = notice;
      });
    } catch (error) {
      if (_current(epoch)) _failed(error);
    }
  }

  Future<void> _more() async {
    if (!_check() || !_fresh || _busy || !_hasMore || _cursor == null) return;
    final after = _cursor!;
    final epoch = ++_epoch;
    setState(() => _busy = true);
    try {
      final page = await widget.repository.listInstructors(
        actorId: _actor!,
        after: after,
        limit: paymentInstructorDefaultLimit,
      );
      if (!_current(epoch)) return;
      _validatePage(page, after);
      setState(() {
        _rows = List.unmodifiable([..._rows, ...page.items]);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _busy = false;
      });
    } catch (error) {
      if (_current(epoch)) _failed(error);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    if (!_check() || _busy) return false;
    final epoch = _epoch;
    final guard = ValueNotifier<bool>(true);
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _busy = _confirming = true;
    });
    late final DialogRoute<bool> route;
    void finish(bool result) {
      // Retained callbacks must never pop a newer, unrelated top route. Check
      // ownership before reading the notifier, which may already be disposed.
      if (!mounted ||
          _closed ||
          epoch != _epoch ||
          !_identityMatches ||
          !identical(_dialog, route) ||
          !identical(_dialogNavigator, navigator) ||
          !identical(_dialogGuard, guard) ||
          !navigator.mounted ||
          !identical(route.navigator, navigator) ||
          !route.isCurrent ||
          !guard.value) {
        return;
      }
      navigator.pop(result);
    }

    route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<bool>(
        valueListenable: guard,
        builder: (_, allowed, _) => AlertDialog(
          scrollable: true,
          title: Text(allowed && _identityMatches ? title : 'Access changed'),
          content: Text(allowed && _identityMatches ? body : 'Reopen setup.'),
          actions: [
            TextButton(
              onPressed: () => finish(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: allowed && _identityMatches
                  ? () => finish(true)
                  : null,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    _dialog = route;
    _dialogNavigator = navigator;
    _dialogGuard = guard;
    try {
      return await navigator.push(route) == true && _current(epoch);
    } finally {
      if (identical(_dialog, route)) {
        _dialog = null;
        _dialogNavigator = null;
      }
      if (identical(_dialogGuard, guard)) _dialogGuard = null;
      guard.dispose();
      if (_current(epoch)) setState(() => _busy = _confirming = false);
    }
  }

  String _label(PaymentInstructorDirectoryEntry row) {
    var length = 8;
    while (length < row.instructorId.length &&
        _rows.any(
          (other) =>
              other.instructorId != row.instructorId &&
              other.instructorId.endsWith(
                row.instructorId.substring(row.instructorId.length - length),
              ),
        )) {
      length = (length + 4).clamp(8, row.instructorId.length);
    }
    return '${row.displayName} · ${row.instructorId.substring(row.instructorId.length - length)}';
  }

  Future<void> _save() async {
    if (!_check() || !_writable || _selected == null) return;
    final selected = _selected!;
    final matches = _rows.where((row) => row.instructorId == selected);
    if (matches.length != 1 || selected == _binding?.instructorId) return;
    final label = _label(matches.single);
    if (!await _confirm(
      'Assign course instructor?',
      'Assign $label to ${widget.course.title}? This is setup only. Sessions '
          'and same-course bundles inherit the course instructor. Checkout is '
          'off; this creates no payment instructions, approval or learning access.',
      'Confirm assignment',
    )) {
      return;
    }
    if (!_check() || !_writable || _selected != selected) return;
    final request = SetCoursePaymentInstructorRequest(
      actorId: _actor!,
      courseId: widget.course.id,
      instructorId: selected,
      expectedRevision: _binding?.revision ?? 0,
    );
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _clear();
      _error = _notice = null;
    });
    try {
      await widget.repository.setCourseInstructor(request);
      if (!_current(epoch)) return;
      // A mutation acknowledgement is not current binding/directory authority.
      await _load(notice: 'Assignment saved. Fresh setup loaded.');
    } catch (error) {
      if (_current(epoch)) _failed(error);
    }
  }

  Future<void> _refresh() async {
    if (!_check() || _busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard selection?',
          'Refresh discards this selection and does not repeat an assignment.',
          'Discard selection',
        )) {
      return;
    }
    if (_check()) await _load();
  }

  Future<void> _close() async {
    if (_closed) return;
    if (_busy && _identityMatches) return;
    if (_dirty &&
        _identityMatches &&
        !await _confirm(
          'Discard selection?',
          'Leave without assigning this instructor?',
          'Discard selection',
        )) {
      return;
    }
    if (!mounted || _closed) return;
    ++_epoch;
    _dismissDialog();
    setState(() {
      _closed = true;
      _clear();
      _busy = _confirming = false;
      _error = _notice = null;
    });
    widget.onClose();
  }

  String get _currentText {
    final binding = _binding;
    if (binding == null) return 'No instructor assigned.';
    final matches = _rows.where(
      (row) => row.instructorId == binding.instructorId,
    );
    if (matches.isNotEmpty) {
      return 'Current instructor: ${_label(matches.first)}';
    }
    return 'Current instructor UUID: ${binding.instructorId}. Not in the loaded '
        'directory; current eligibility has not been confirmed.';
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _identityMatches && _courseLive;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Course instructor',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (!allowed)
            const Text(
              'Reopen setup with administrator access to a live course.',
            )
          else ...[
            Text(widget.course.title),
            const Text(
              'Setup only. Sessions and same-course bundles inherit this '
              'assignment. Checkout is off. No receiving details are shown.',
            ),
            if (_busy && !_confirming) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_notice != null) Text(_notice!),
            if (_fresh) ...[
              const SizedBox(height: 12),
              Text(_currentText),
              if (_rows.isEmpty) const Text('No selectable instructors found.'),
              for (final row in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Semantics(
                    selected: _selected == row.instructorId,
                    child: OutlinedButton(
                      key: ValueKey('instructor-${row.instructorId}'),
                      onPressed: _writable
                          ? () {
                              if (!_check() || !_writable) return;
                              setState(() {
                                _selected =
                                    row.instructorId == _binding?.instructorId
                                    ? null
                                    : row.instructorId;
                              });
                            }
                          : null,
                      child: Text(
                        '${_selected == row.instructorId ? 'Selected: ' : ''}${_label(row)}',
                      ),
                    ),
                  ),
                ),
              if (_hasMore)
                TextButton(
                  onPressed: _busy ? null : _more,
                  child: const Text('Load more instructors'),
                ),
              if ((_binding?.revision ?? 0) == instructorPaymentMaxRevision)
                const Text('This assignment cannot accept another revision.'),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _writable && _selected != null ? _save : null,
                  child: const Text('Assign instructor'),
                ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ],
          TextButton(
            onPressed: _busy && allowed ? null : _close,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
