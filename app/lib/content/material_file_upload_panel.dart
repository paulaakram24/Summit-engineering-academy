import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'course_image_selector.dart';
import 'material_file_selector.dart';
import 'material_file_upload_repository.dart';
import 'material_models.dart';

class MaterialFileUploadPanel extends StatefulWidget {
  const MaterialFileUploadPanel({
    super.key,
    required this.auth,
    required this.material,
    required this.repository,
    required this.selector,
    required this.onClose,
  });
  final AuthController auth;
  final MaterialDescriptor material;
  final MaterialFileUploadRepository repository;
  final MaterialFileSelector selector;
  final VoidCallback onClose;
  @override
  State<MaterialFileUploadPanel> createState() =>
      _MaterialFileUploadPanelState();
}

class _MaterialFileUploadPanelState extends State<MaterialFileUploadPanel>
    with WidgetsBindingObserver {
  static const _uploaded =
      'Uploaded — awaiting trusted validation. Not available to students.';
  SelectedMaterialFile? _selected;
  MaterialFileUploadRequest? _request;
  List<MaterialFileUpload> _rows = [];
  String? _actor, _device, _error, _notice;
  Object? _access;
  MaterialFileUploadPhase? _phase;
  bool _busy = false, _confirming = false, _fresh = false;
  bool _foreground = true, _invalidated = false, _closed = false;
  int _epoch = 0;
  DialogRoute<bool>? _dialog;
  ValueNotifier<bool>? _dialogGuard;

  String? get _liveActor {
    try {
      return widget.repository.currentActorId?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  bool get _materialValid {
    try {
      widget.material.validate();
      return !widget.material.isDeleted &&
          (widget.material.kind == MaterialKind.pdf ||
              widget.material.kind == MaterialKind.file);
    } catch (_) {
      return false;
    }
  }

  bool get _identityMatches =>
      !_invalidated &&
      !_closed &&
      _foreground &&
      widget.auth.stage == AuthStage.ready &&
      widget.auth.access?.role == 'admin' &&
      identical(_access, widget.auth.access) &&
      widget.auth.access?.deviceId == _device &&
      _actor != null &&
      isCatalogUuid(_actor!) &&
      _liveActor == _actor;
  bool get _canChoose =>
      _identityMatches &&
      _materialValid &&
      _fresh &&
      !_busy &&
      _request == null;
  bool get _dirty => _selected != null || _request != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_authChanged);
    _capture();
    if (_identityMatches && _materialValid) unawaited(_load());
  }

  void _capture() {
    _actor = _liveActor;
    _access = widget.auth.access;
    _device = widget.auth.access?.deviceId;
    _foreground = _isForeground;
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _clearPrivate() {
    _selected = null;
    _request = null;
    _rows = [];
    _phase = null;
    _fresh = false;
    _error = _notice = null;
  }

  void _dismissDialog({bool notify = true}) {
    final route = _dialog;
    _dialog = null;
    if (notify) _dialogGuard?.value = false;
    if (route != null) {
      scheduleMicrotask(() {
        final navigator = route.navigator;
        if (navigator != null && navigator.mounted && route.isActive) {
          navigator.removeRoute(route, false);
        }
      });
    }
  }

  void _invalidate() {
    if (_invalidated || _closed) return;
    ++_epoch;
    _invalidated = true;
    _dismissDialog();
    _clearPrivate();
    _busy = _confirming = false;
    if (mounted) setState(() {});
  }

  bool _check() {
    if (!mounted || _closed) return false;
    if (!_identityMatches || !_materialValid) {
      _invalidate();
      return false;
    }
    return true;
  }

  bool _current(int epoch) => mounted && epoch == _epoch && _check();
  void _authChanged() {
    if (!_identityMatches) _invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Track real foreground even while native handoff suppression is active.
    // The selector releases it on foreground acknowledgement, before file reads
    // and server revalidation. Subsequent background events always invalidate.
    _foreground = state == AppLifecycleState.resumed;
    if (CourseImageSelection.active(widget.auth)) return;
    if (!_foreground) _invalidate();
  }

  @override
  void didUpdateWidget(covariant MaterialFileUploadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth ||
        oldWidget.material != widget.material ||
        oldWidget.repository != widget.repository ||
        oldWidget.selector != widget.selector) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      ++_epoch;
      _dismissDialog(notify: false);
      _clearPrivate();
      _busy = _confirming = _invalidated = false;
      _capture();
      if (!_closed && _identityMatches && _materialValid) unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    _dismissDialog(notify: false);
    _clearPrivate();
    super.dispose();
  }

  bool _accessFailure(Object error) =>
      error is MaterialFileUploadFailure && error.accessChanged;
  bool _rowMatches(MaterialFileUpload row) =>
      row.materialId == widget.material.id.toLowerCase() &&
      (widget.material.kind != MaterialKind.pdf ||
          row.contentType == 'application/pdf');

  Future<void> _load() async {
    if (!_check()) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _fresh = false;
      _rows = [];
      _error = null;
    });
    try {
      final rows = await widget.repository.listUploads(
        actorId: _actor!,
        material: widget.material,
      );
      if (!_current(epoch)) return;
      if (rows.length > 20 ||
          rows.any((row) => !_rowMatches(row)) ||
          rows.map((row) => row.assetId).toSet().length != rows.length) {
        throw const MaterialFileUploadFailure();
      }
      setState(() {
        _rows = List.unmodifiable(rows);
        _fresh = true;
      });
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accessFailure(error)) {
        _invalidate();
        return;
      }
      setState(
        () => _error = 'Upload history could not be verified. Refresh before selecting another file.',
      );
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    if (!_check() || !_canChoose) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      final selected = await widget.selector.select(
        widget.auth,
        widget.material.kind,
      );
      // Result delivery is not itself proof that Flutter has resumed. The real
      // selector waits for foreground; independently verify at this boundary.
      if (!mounted || epoch != _epoch) return;
      _foreground = _isForeground;
      if (!_current(epoch) || selected == null) return;
      if (selected.kind != widget.material.kind) {
        throw const MaterialFileSelectionFailure();
      }
      setState(() => _selected = selected);
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _error = const MaterialFileSelectionFailure().message);
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({required bool discard}) async {
    if (!_check() || _busy) return false;
    final epoch = ++_epoch;
    final guard = ValueNotifier<bool>(true);
    late DialogRoute<bool> route;
    route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<bool>(
        valueListenable: guard,
        builder: (_, allowed, _) => AlertDialog(
          scrollable: true,
          title: Text(
            !allowed
                ? 'Access changed'
                : discard
                ? 'Discard local selection?'
                : 'Upload selected file?',
          ),
          content: Text(
            !allowed
                ? 'Close and verify administrator access again.'
                : discard
                ? 'Discard the in-memory selection or status-check request. Any transmitted upload may already exist. Closing does not delete or retry it; reopen to list upload statuses.'
                : 'Upload to private quarantine only. This does not replace an existing asset, validate the file, publish it, or make it available to students.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (route.isCurrent) Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: allowed
                  ? () {
                      if (_current(epoch) && route.isCurrent) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    }
                  : null,
              child: Text(discard ? 'Discard and close' : 'Confirm upload'),
            ),
          ],
        ),
      ),
    );
    _dialog = route;
    _dialogGuard = guard;
    setState(() {
      _busy = _confirming = true;
    });
    try {
      return await Navigator.of(context, rootNavigator: true).push(route) ==
              true &&
          _current(epoch);
    } finally {
      if (identical(_dialog, route)) _dialog = null;
      if (identical(_dialogGuard, guard)) _dialogGuard = null;
      unawaited(route.completed.then((_) => guard.dispose()));
      if (_current(epoch)) {
        setState(() {
          _busy = _confirming = false;
        });
      }
    }
  }

  bool _resultMatches(
    MaterialFileUpload row,
    MaterialFileUploadRequest request,
  ) =>
      _rowMatches(row) &&
      row.fileName == request.file.fileName &&
      row.contentType == request.file.contentType &&
      row.byteLength == request.file.byteLength;

  Future<void> _upload() async {
    if (!_check() || !_canChoose || _selected == null) return;
    final request = MaterialFileUploadRequest(
      actorId: _actor!,
      material: widget.material,
      file: _selected!,
    );
    if (!await _confirm(discard: false) || !_check() || !_canChoose) return;
    final epoch = ++_epoch;
    setState(() {
      _request = request;
      _selected = null;
      _busy = true;
      _fresh = false;
      _rows = [];
      _phase = MaterialFileUploadPhase.preparing;
      _error = _notice = null;
    });
    try {
      final result = await widget.repository.upload(
        request,
        onPhase: (phase) {
          // A stale UI must stop the next side effect, not merely hide progress.
          // Already transmitted bytes remain uncertain and are never deleted.
          if (!_current(epoch)) {
            throw const MaterialFileUploadFailure(accessChanged: true);
          }
          setState(() => _phase = phase);
        },
      );
      if (!_current(epoch)) return;
      if (!_resultMatches(result, request) ||
          result.state != MaterialFileUploadState.uploaded) {
        throw const MaterialFileUploadFailure();
      }
      await _confirmedUpload();
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accessFailure(error)) {
        _invalidate();
        return;
      }
      setState(
        () => _error = 'The upload may already exist. Check upload to reconcile this exact request without resending bytes. No automatic retry is made.',
      );
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _phase = null;
        });
      }
    }
  }

  Future<void> _checkUpload() async {
    if (!_check() || _busy || _request == null) return;
    final request = _request!;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _phase = MaterialFileUploadPhase.checking;
      _fresh = false;
      _rows = [];
      _error = _notice = null;
    });
    try {
      final result = await widget.repository.checkUpload(
        request,
        ensureActive: () {
          if (!_current(epoch)) {
            throw const MaterialFileUploadFailure(accessChanged: true);
          }
        },
      );
      if (!_current(epoch)) return;
      if (!_resultMatches(result, request)) {
        throw const MaterialFileUploadFailure();
      }
      if (result.state == MaterialFileUploadState.uploaded) {
        await _confirmedUpload();
      } else {
        setState(
          () => _notice = 'Reservation exists; upload is not confirmed. No bytes were resent. Check again explicitly or close and review upload history.',
        );
      }
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accessFailure(error)) {
        _invalidate();
        return;
      }
      setState(
        () => _error = 'Upload status remains uncertain. Check upload again explicitly; no bytes will be resent.',
      );
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
          _phase = null;
        });
      }
    }
  }

  Future<void> _confirmedUpload() async {
    setState(() {
      _request = null;
      _selected = null;
      _phase = null;
      _notice = _uploaded;
    });
    await _load(); // A returned upload snapshot never replaces fresh list state.
  }

  Future<void> _refresh() async {
    if (!_check() || _busy) return;
    // A list refresh cannot erase an unresolved request or authorize resending.
    await _load();
  }

  Future<void> _close() async {
    if (!mounted || _closed || (_identityMatches && _busy)) return;
    if (_identityMatches && _dirty && !await _confirm(discard: true)) return;
    if (!mounted || _closed) return;
    ++_epoch;
    _closed = true;
    _dismissDialog();
    _clearPrivate();
    setState(() {});
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_identityMatches || !_materialValid) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                !_materialValid
                    ? 'A nondeleted PDF or file material is required.'
                    : 'Administrator access changed. Close and verify access again.',
              ),
            ),
            TextButton(onPressed: _close, child: const Text('Close uploads')),
          ] else ...[
            Text(
              'Files: ${widget.material.title}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'PDF or UTF-8 TXT, up to 20 MiB. Private quarantine only: no file preview, publication or student access.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _canChoose ? _choose : null,
                  child: const Text('Choose file'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh uploads'),
                ),
                TextButton(
                  onPressed: _busy ? null : _close,
                  child: const Text('Close uploads'),
                ),
              ],
            ),
            if (_busy && !_confirming) const LinearProgressIndicator(),
            if (_phase != null)
              Semantics(
                liveRegion: true,
                child: Text(switch (_phase!) {
                  MaterialFileUploadPhase.preparing => 'Preparing upload…',
                  MaterialFileUploadPhase.transferring => 'Transferring file…',
                  MaterialFileUploadPhase.checking => 'Checking upload…',
                }),
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            if (_selected != null) ...[
              const Text('Selected — not uploaded'),
              Text(_selected!.fileName),
              Text(
                '${_selected!.byteLength} bytes • ${_selected!.contentType}',
              ),
              FilledButton(
                onPressed: _canChoose ? _upload : null,
                child: const Text('Upload selected file'),
              ),
              TextButton(
                onPressed: !_canChoose
                    ? null
                    : () {
                        if (!_check()) return;
                        setState(() => _selected = null);
                      },
                child: const Text('Discard selection'),
              ),
            ],
            if (_request != null) ...[
              const Text('Bound upload request (read-only)'),
              Text(_request!.file.fileName),
              Text(
                '${_request!.file.byteLength} bytes • ${_request!.file.contentType}',
              ),
              OutlinedButton(
                onPressed: _busy ? null : _checkUpload,
                child: const Text('Check upload'),
              ),
            ],
            if (_fresh && _rows.isEmpty) const Text('No uploads on this page.'),
            for (final row in _rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(row.fileName),
                      Text('${row.byteLength} bytes • ${row.contentType}'),
                      Text(
                        row.state == MaterialFileUploadState.uploaded
                            ? _uploaded
                            : 'Reserved — upload not confirmed. Not available to students.',
                      ),
                    ],
                  ),
                ),
              ),
            if (_fresh && _rows.length == 20)
              const Text('Showing up to 20 recent uploads.'),
          ],
        ],
      ),
    ),
  );
}
