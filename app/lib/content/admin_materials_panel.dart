import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'content_models.dart';
import 'material_repository.dart';

class AdminMaterialsPanel extends StatefulWidget {
  const AdminMaterialsPanel({
    super.key,
    required this.course,
    required this.session,
    required this.auth,
    required this.repository,
    required this.onClose,
  });
  final Course course;
  final CourseSession session;
  final AuthController auth;
  final MaterialRepository repository;
  final VoidCallback onClose;
  @override
  State<AdminMaterialsPanel> createState() => _AdminMaterialsPanelState();
}

class _AdminMaterialsPanelState extends State<AdminMaterialsPanel>
    with WidgetsBindingObserver {
  final _title = TextEditingController(), _summary = TextEditingController();
  final _position = TextEditingController(),
      _body = TextEditingController(),
      _target = TextEditingController();
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  List<MaterialDescriptor> _rows = [];
  MaterialDescriptor? _expected;
  MaterialKind _kind = MaterialKind.video;
  ContentStatus _status = ContentStatus.draft;
  String? _actor, _device, _error, _notice;
  Object? _access;
  int _epoch = 0, _offset = 0, _editorId = 0;
  bool _busy = false,
      _confirming = false,
      _fresh = false,
      _refreshRequired = false;
  bool _includeDeleted = false,
      _editing = false,
      _dirty = false,
      _settingFields = false;
  bool _invalidated = false, _foreground = true;
  DialogRoute<bool>? _dialog;
  NavigatorState? _dialogNavigator;
  ValueNotifier<bool>? _dialogGuard;
  List<TextEditingController> get _controllers => [
    _title,
    _summary,
    _position,
    _body,
    _target,
  ];

  bool get _parentsMatch =>
      isMaterialUuid(widget.course.id) &&
      isMaterialUuid(widget.session.id) &&
      widget.session.courseId.toLowerCase() == widget.course.id.toLowerCase();
  bool get _parentsLive =>
      _parentsMatch && !widget.course.isDeleted && !widget.session.isDeleted;
  String? get _liveActor {
    try {
      return widget.repository.currentActorId;
    } catch (_) {
      return null;
    }
  }

  bool get _identityMatches =>
      !_invalidated &&
      _foreground &&
      widget.auth.stage == AuthStage.ready &&
      widget.auth.access?.role == 'admin' &&
      identical(widget.auth.access, _access) &&
      widget.auth.access?.deviceId == _device &&
      _actor != null &&
      isMaterialUuid(_actor!) &&
      _liveActor?.toLowerCase() == _actor!.toLowerCase();
  bool get _writable =>
      _identityMatches && _parentsLive && _fresh && !_refreshRequired && !_busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_authChanged);
    for (final controller in _controllers) {
      controller.addListener(_formChanged);
    }
    _captureIdentity();
    if (_identityMatches && _parentsMatch) _load();
  }

  void _captureIdentity() {
    _actor = _liveActor;
    _access = widget.auth.access;
    _device = widget.auth.access?.deviceId;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(AdminMaterialsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth ||
        oldWidget.repository != widget.repository ||
        oldWidget.course != widget.course ||
        oldWidget.session != widget.session) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      ++_epoch;
      _dismissDialog(notifyGuard: false);
      _clearEditor();
      _rows = [];
      _busy = _confirming = _fresh = _refreshRequired = _includeDeleted =
          _invalidated = false;
      _offset = 0;
      _error = _notice = null;
      _captureIdentity();
      if (_identityMatches && _parentsMatch) _load();
    }
  }

  void _formChanged() {
    if (!_settingFields && _editing && mounted) setState(() => _dirty = true);
  }

  void _clearEditor() {
    _settingFields = true;
    for (final controller in _controllers) {
      controller.clear();
    }
    _settingFields = false;
    _editing = _dirty = false;
    _expected = null;
    _kind = MaterialKind.video;
    _status = ContentStatus.draft;
    _form = GlobalKey<FormState>();
    ++_editorId;
  }

  void _dismissDialog({bool notifyGuard = true}) {
    final route = _dialog;
    final navigator = _dialogNavigator;
    // During widget replacement/disposal Flutter locks the tree. In that case
    // remove this route after the stack unwinds without notifying its builder.
    if (notifyGuard) _dialogGuard?.value = false;
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
    _clearEditor();
    _rows = [];
    _fresh = _busy = _confirming = false;
    _error = _notice = null;
    if (mounted) setState(() {});
  }

  void _authChanged() {
    if (!_identityMatches) _invalidate();
  }

  bool _check() {
    if (!mounted) return false;
    if (!_identityMatches) {
      _invalidate();
      return false;
    }
    return true;
  }

  bool _current(int epoch) => _check() && epoch == _epoch;

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
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _failure(Object error) => error is MaterialFailure
      ? MaterialFailure(error.kind).message
      : const MaterialFailure(MaterialFailureKind.requestFailed).message;

  Future<void> _load() async {
    if (!_check() || !_parentsMatch) return;
    final epoch = ++_epoch;
    setState(() {
      _clearEditor();
      _rows = [];
      _busy = true;
      _fresh = false;
      _error = null;
    });
    try {
      final rows = await widget.repository.listMaterials(
        widget.session.id,
        offset: _offset,
        includeDeleted: _includeDeleted,
      );
      if (!_current(epoch)) return;
      if (rows.length > materialPageSize) {
        throw const MaterialFailure(MaterialFailureKind.requestFailed);
      }
      for (final row in rows) {
        row.validate();
        if (row.sessionId.toLowerCase() != widget.session.id.toLowerCase() ||
            (!_includeDeleted && row.isDeleted)) {
          throw const MaterialFailure(MaterialFailureKind.requestFailed);
        }
      }
      setState(() {
        _rows = List.unmodifiable(rows);
        _fresh = true;
        _refreshRequired = false;
      });
    } catch (error) {
      if (_current(epoch)) {
        setState(() {
          _refreshRequired = true;
          _error = _failure(error);
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  void _new() {
    if (!_check() || !_writable) return;
    setState(() {
      _clearEditor();
      _editing = true;
      _position.text = '0';
      _dirty = false;
      _error = _notice = null;
    });
  }

  Future<void> _edit(MaterialDescriptor row) async {
    if (!_check() || !_writable || row.isDeleted) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      final detail = await widget.repository.getAdminDetail(row);
      if (!_current(epoch)) return;
      final descriptor = detail.descriptor;
      descriptor.validate();
      final draft = detail.toDraft();
      draft.validate();
      if (descriptor.id.toLowerCase() != row.id.toLowerCase() ||
          descriptor.sessionId.toLowerCase() !=
              widget.session.id.toLowerCase() ||
          descriptor.kind != row.kind ||
          descriptor.revision < row.revision ||
          descriptor.isDeleted ||
          descriptor.createdBy.toLowerCase() != row.createdBy.toLowerCase() ||
          !descriptor.createdAt.isAtSameMomentAs(row.createdAt)) {
        throw const MaterialFailure(MaterialFailureKind.unavailable);
      }
      setState(() {
        _clearEditor();
        _editing = true;
        _expected = descriptor;
        _kind = draft.kind;
        _status = draft.status;
        _settingFields = true;
        _title.text = draft.title;
        _summary.text = draft.summary;
        _position.text = '${draft.position}';
        _body.text = draft.payload.bodyText;
        _target.text = draft.payload.targetUrl ?? '';
        _settingFields = false;
        _dirty = false;
      });
    } catch (error) {
      if (_current(epoch)) {
        setState(() {
          _clearEditor();
          _rows = [];
          _fresh = false;
          _refreshRequired = true;
          _error = _failure(error);
        });
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String explanation,
    String confirmLabel,
  ) async {
    if (!_check() || _busy) return false;
    final epoch = ++_epoch;
    final guard = ValueNotifier<bool>(true);
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _busy = true;
      _confirming = true;
    });
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<bool>(
        valueListenable: guard,
        builder: (_, allowed, _) => AlertDialog(
          title: Text(allowed ? title : 'Access changed'),
          content: Text(
            allowed
                ? explanation
                : 'Close this dialog and verify administrator access again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: allowed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    _dialog = route;
    _dialogNavigator = navigator;
    _dialogGuard = guard;
    try {
      final confirmed = await navigator.push(route);
      return _current(epoch) && confirmed == true;
    } finally {
      if (identical(_dialog, route)) {
        _dialog = null;
        _dialogNavigator = null;
      }
      if (identical(_dialogGuard, guard)) _dialogGuard = null;
      guard.dispose();
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (!_check() || _busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard unsaved changes?',
          'Refreshing discards these edits. It does not repeat the previous save.',
          'Discard changes',
        )) {
      return;
    }
    if (_check()) {
      _notice = null;
      await _load();
    }
  }

  Future<void> _cancelEdit() async {
    if (!_check() || _busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard unsaved changes?',
          'These edits have not been saved.',
          'Discard changes',
        )) {
      return;
    }
    if (_check()) {
      setState(() {
        _clearEditor();
        _error = null;
      });
    }
  }

  Future<void> _close() async {
    if (_busy && _identityMatches) return;
    if (_dirty &&
        _identityMatches &&
        !await _confirm(
          'Discard unsaved changes?',
          'Leaving discards these edits. No material will be saved.',
          'Discard changes',
        )) {
      return;
    }
    if (mounted) widget.onClose();
  }

  MaterialDraft _draft() => MaterialDraft(
    kind: _kind,
    title: _title.text,
    summary: _summary.text,
    position: int.parse(_position.text.trim()),
    status: _expected == null ? ContentStatus.draft : _status,
    payload: switch (_kind) {
      MaterialKind.assignment => AssignmentMaterialPayload(_body.text),
      MaterialKind.link => LinkMaterialPayload(
        _target.text.isEmpty ? null : _target.text,
      ),
      _ => const EmptyMaterialPayload(),
    },
  );

  Future<void> _save() async {
    if (!_check() ||
        !_writable ||
        !_editing ||
        !_form.currentState!.validate()) {
      return;
    }
    MaterialDraft draft;
    try {
      draft = _draft();
      draft.validate();
    } catch (error) {
      setState(() => _error = _failure(error));
      return;
    }
    final actor = _liveActor;
    if (actor == null || !_check()) return;
    final expected = _expected;
    if (expected == null) {
      final request = CreateMaterialRequest(
        sessionId: widget.session.id,
        draft: draft,
        actorId: actor,
      );
      await _mutate(() => widget.repository.createMaterial(request));
    } else {
      final request = UpdateMaterialRequest(
        expected: expected,
        draft: draft,
        actorId: actor,
      );
      await _mutate(() => widget.repository.updateMaterial(request));
    }
  }

  Future<void> _lifecycle(MaterialDescriptor row) async {
    if (!_check() || !_writable) return;
    final restore = row.isDeleted;
    if (!await _confirm(
      restore ? 'Restore material?' : 'Delete material?',
      restore
          ? 'Restore this material to draft. Publishing remains an explicit authoring action.'
          : 'This recoverable deletion archives the material. It may be restored to draft.',
      restore ? 'Confirm restore' : 'Confirm delete',
    )) {
      return;
    }
    if (!_check() || !_writable) return;
    final actor = _liveActor;
    if (actor == null) {
      _invalidate();
      return;
    }
    final request = MaterialLifecycleRequest(expected: row, actorId: actor);
    await _mutate(
      () => restore
          ? widget.repository.restoreMaterial(request)
          : widget.repository.deleteMaterial(request),
    );
  }

  Future<void> _mutate(Future<MaterialMutationResult> Function() action) async {
    if (!_check() || !_writable) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _rows = [];
      _error = _notice = null;
    });
    try {
      await action(); // A cached snapshot is not current state; never merge it.
      if (!_current(epoch)) return;
      setState(() {
        _clearEditor();
        _fresh = false;
        _refreshRequired = true;
        _offset = 0;
        _notice =
            'Save acknowledged. Showing a fresh list before further changes.';
      });
      await _load();
    } catch (error) {
      if (!_current(epoch)) return;
      if (error is MaterialFailure &&
          (error.kind == MaterialFailureKind.accessDenied ||
              error.kind == MaterialFailureKind.actorMismatch)) {
        _invalidate();
        return;
      }
      setState(() {
        _fresh = false;
        _refreshRequired = true;
        if (error is MaterialFailure &&
            error.kind == MaterialFailureKind.conflict &&
            _editing) {
          _expected = null;
          _error = 'This material changed. Edits remain read-only for copying. Refresh discards them; reopen the current material and reconcile manually.';
        } else {
          _clearEditor();
          _error = 'The change could not be confirmed and may already have saved. Refresh before any new change. This panel will not retry it.';
        }
      });
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int lines = 1,
    int? max,
    bool required = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    readOnly: !_writable,
    decoration: InputDecoration(labelText: label),
    minLines: lines,
    maxLines: lines,
    validator: (value) =>
        validateContentText(value, label, max ?? 10000, required: required),
  );

  bool get _configured => switch (_kind) {
    MaterialKind.assignment =>
      _body.text.trim().isNotEmpty && _body.text.runes.length <= 10000,
    MaterialKind.link => isMaterialHttpsTarget(_target.text),
    _ => false,
  };
  Widget _editor() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _refreshRequired
              ? 'Unsaved edits (read-only)'
              : _expected == null
              ? 'New material'
              : 'Edit material',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_expected == null && !_refreshRequired)
          DropdownButtonFormField<MaterialKind>(
            key: ValueKey('kind-$_editorId'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Kind'),
            isExpanded: true,
            items: MaterialKind.values
                .map(
                  (kind) =>
                      DropdownMenuItem(value: kind, child: Text(kind.name)),
                )
                .toList(),
            onChanged: !_writable
                ? null
                : (kind) => setState(() {
                    _kind = kind!;
                    _body.clear();
                    _target.clear();
                    _dirty = true;
                  }),
          )
        else
          Text('Kind: ${_kind.name} (immutable)'),
        _field('Title', _title, max: 160, required: true),
        _field('Summary', _summary, lines: 3),
        TextFormField(
          controller: _position,
          enabled: !_busy,
          readOnly: !_writable,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Position'),
          validator: validateContentInteger,
        ),
        if (_kind == MaterialKind.assignment)
          _field('Assignment body (private)', _body, lines: 5),
        if (_kind == MaterialKind.link)
          TextFormField(
            controller: _target,
            enabled: !_busy,
            readOnly: !_writable,
            decoration: const InputDecoration(
              labelText: 'HTTPS target (private, optional)',
              helperText: 'Leave empty for an unconfigured draft. No link is opened here.',
              helperMaxLines: 4,
            ),
            validator: (value) =>
                value == null || value.isEmpty || isMaterialHttpsTarget(value)
                ? null
                : 'Enter a valid HTTPS target without credentials or whitespace.',
          ),
        if (_kind == MaterialKind.video ||
            _kind == MaterialKind.pdf ||
            _kind == MaterialKind.file)
          const Text(
            'Media placeholder only. Uploads and student delivery are unavailable; this kind cannot publish.',
          ),
        if (_expected == null)
          const Text('New materials save as draft.')
        else
          DropdownButtonFormField<ContentStatus>(
            key: ValueKey('status-$_editorId'),
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: ContentStatus.values
                .where(
                  (s) =>
                      s != ContentStatus.published ||
                      _kind == MaterialKind.assignment ||
                      _kind == MaterialKind.link,
                )
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    enabled: s != ContentStatus.published || _configured,
                    child: Text(s.name),
                  ),
                )
                .toList(),
            onChanged: !_writable
                ? null
                : (status) => setState(() {
                    _status = status!;
                    _dirty = true;
                  }),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _writable ? _save : null,
          child: const Text('Save material'),
        ),
        TextButton(
          onPressed: _busy ? null : _cancelEdit,
          child: const Text('Cancel edit'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: !_identityMatches
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Administrator access changed. Close and verify access again.',
                ),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('Close materials'),
                ),
              ],
            ),
          )
        : !_parentsMatch
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('The session does not match this course.'),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('Close materials'),
                ),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Materials: ${widget.session.title}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Admin authoring only. Published state does not grant student access.',
                ),
                if (!_parentsLive)
                  const Text(
                    'Deleted course or session: materials are read-only.',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_editing)
                      FilledButton(
                        onPressed: _writable ? _new : null,
                        child: const Text('New material'),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : _refresh,
                      child: const Text('Refresh materials'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _close,
                      child: const Text('Close materials'),
                    ),
                  ],
                ),
                if (_busy && !_confirming) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_notice != null)
                  Semantics(liveRegion: true, child: Text(_notice!)),
                if (_editing)
                  _editor()
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include deleted'),
                    subtitle: const Text(
                      'Deleted materials may be restored to draft.',
                    ),
                    value: _includeDeleted,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _includeDeleted = value;
                              _offset = 0;
                            });
                            _load();
                          },
                  ),
                  if (_fresh && _rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No materials on this page.'),
                    ),
                  for (final row in _rows)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(row.title),
                            if (row.summary.isNotEmpty) Text(row.summary),
                            Text(
                              '${row.kind.name} • ${row.status.name} • Position ${row.position}${row.isDeleted ? ' • Deleted' : ''}',
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton(
                                  onPressed: !_writable || row.isDeleted
                                      ? null
                                      : () => _edit(row),
                                  child: const Text('Edit material'),
                                ),
                                TextButton(
                                  onPressed: !_writable
                                      ? null
                                      : () => _lifecycle(row),
                                  child: Text(
                                    row.isDeleted
                                        ? 'Restore material'
                                        : 'Delete material',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () {
                                _offset -= materialPageSize;
                                _load();
                              },
                        child: const Text('Previous'),
                      ),
                      Text('Page ${_offset ~/ materialPageSize + 1}'),
                      TextButton(
                        onPressed:
                            _busy || !_fresh || _rows.length != materialPageSize
                            ? null
                            : () {
                                _offset += materialPageSize;
                                _load();
                              },
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
  );
}
