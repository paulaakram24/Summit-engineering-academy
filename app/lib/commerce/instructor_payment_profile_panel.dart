import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../catalog/catalog_models.dart' show isCatalogUuid, trimCatalogSpaces;
import 'instructor_payment_repository.dart';

class InstructorPaymentProfilePanel extends StatefulWidget {
  const InstructorPaymentProfilePanel({
    super.key,
    required this.auth,
    required this.repository,
    required this.onClose,
  });
  final AuthController auth;
  final InstructorPaymentRepository repository;
  final VoidCallback onClose;

  @override
  State<InstructorPaymentProfilePanel> createState() =>
      _InstructorPaymentProfilePanelState();
}

class _InstructorPaymentProfilePanelState
    extends State<InstructorPaymentProfilePanel>
    with WidgetsBindingObserver {
  final _name = TextEditingController(), _phone = TextEditingController();
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  InstructorPaymentMethodConfiguration _method =
      InstructorPaymentMethodConfiguration.instapayOnly;
  String? _actor, _device, _error, _notice;
  Object? _access;
  int _epoch = 0, _revision = 0;
  bool _foreground = true, _invalidated = false, _closed = false;
  bool _busy = false, _saving = false, _confirming = false;
  bool _fresh = false, _dirty = false, _setting = false;
  DialogRoute<bool>? _dialog;
  ValueNotifier<bool>? _dialogGuard;

  String? get _liveActor {
    try {
      return widget.repository.currentActorId?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  bool get _identityMatches =>
      !_invalidated &&
      !_closed &&
      _foreground &&
      widget.auth.stage == AuthStage.ready &&
      widget.auth.access?.role == 'admin' &&
      identical(widget.auth.access, _access) &&
      widget.auth.access?.deviceId == _device &&
      _actor != null &&
      isCatalogUuid(_actor!) &&
      _actor == _liveActor;
  bool get _writable => _identityMatches && _fresh && !_busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_authChanged);
    _name.addListener(_edited);
    _phone.addListener(_edited);
    _capture();
    if (_identityMatches) unawaited(_load());
  }

  void _capture() {
    _actor = _liveActor;
    _access = widget.auth.access;
    _device = widget.auth.access?.deviceId;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _edited() {
    if (!_setting && mounted) setState(() => _dirty = true);
  }

  void _clear() {
    _setting = true;
    _name.clear();
    _phone.clear();
    _setting = false;
    _method = InstructorPaymentMethodConfiguration.instapayOnly;
    _revision = 0;
    _dirty = _fresh = false;
    _form = GlobalKey<FormState>();
  }

  // Dismiss exactly our route, even if another route has since appeared above it.
  // Clear the guard synchronously so old confirmation callbacks cannot write.
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
    _clear();
    _busy = _saving = _confirming = false;
    _error = _notice = null;
    if (mounted) setState(() {});
  }

  bool _check() {
    if (!mounted || _closed) return false;
    if (!_identityMatches) {
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
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  @override
  void didUpdateWidget(covariant InstructorPaymentProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth ||
        oldWidget.repository != widget.repository) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
      ++_epoch;
      _dismissDialog(notify: false);
      _clear();
      _busy = _saving = _confirming = _invalidated = false;
      _error = _notice = null;
      _capture();
      if (!_closed && _identityMatches) unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_authChanged);
    _dismissDialog(notify: false);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _accessFailure(Object error) =>
      error is InstructorPaymentFailure &&
      (error.kind == InstructorPaymentFailureKind.accessRequired ||
          error.kind == InstructorPaymentFailureKind.actorChanged);

  Future<void> _load() async {
    if (!_check()) return;
    final epoch = ++_epoch;
    final actor = _actor!;
    setState(() {
      _clear();
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.getMyProfile(actorId: actor);
      if (!_current(epoch)) return;
      if (profile != null && profile.instructorId != actor) {
        throw const InstructorPaymentFailure(
          InstructorPaymentFailureKind.invalidResponse,
        );
      }
      setState(() {
        _setting = true;
        _name.text = profile?.recipientName ?? '';
        _phone.text = profile?.phoneNumber ?? '';
        _setting = false;
        _method =
            profile?.methodConfiguration ??
            InstructorPaymentMethodConfiguration.instapayOnly;
        _revision = profile?.revision ?? 0;
        _fresh = true;
        _dirty = false;
      });
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accessFailure(error)) {
        _invalidate();
        return;
      }
      setState(() {
        _notice = null;
        _error =
            'Receiving details could not be verified. Refresh before editing.';
      });
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
            allowed
                ? (discard
                      ? 'Discard unsaved changes?'
                      : 'Save receiving details?')
                : 'Access changed',
          ),
          content: Text(
            !allowed
                ? 'Close and verify administrator access again.'
                : discard
                ? 'These edits will be discarded. This does not repeat a previous save.'
                : 'Setup only. This does not verify bank or wallet receiving capability, enable checkout, or move money. Both enabled methods use the same phone number.',
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
              child: Text(discard ? 'Discard changes' : 'Confirm save'),
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
      final confirmed = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      return _current(epoch) && confirmed == true;
    } finally {
      if (identical(_dialog, route)) _dialog = null;
      if (identical(_dialogGuard, guard)) _dialogGuard = null;
      // Navigator's outgoing animation can still build the guard after pop.
      // Its route owns that final render; no further value updates are made.
      unawaited(route.completed.then((_) => guard.dispose()));
      if (_current(epoch)) {
        setState(() {
          _busy = _confirming = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_check() || !_writable || !_form.currentState!.validate()) return;
    final SaveInstructorPaymentProfileRequest request;
    try {
      // Capture immutable actor, fields and CAS revision before confirmation.
      request = SaveInstructorPaymentProfileRequest(
        actorId: _actor!,
        recipientName: _name.text,
        phoneNumber: _phone.text,
        methodConfiguration: _method,
        expectedRevision: _revision,
      );
    } catch (_) {
      setState(
        () => _error =
            'Check the receiving details. This revision may require refresh.',
      );
      return;
    }
    if (!await _confirm(discard: false) || !_check() || !_writable) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = _saving = true;
      _fresh = false;
      _error = _notice = null;
    });
    try {
      final result = await widget.repository.saveMyProfile(request);
      if (!_current(epoch)) return;
      if (result.instructorId != request.actorId ||
          result.revision != request.expectedRevision + 1 ||
          result.recipientName != request.recipientName ||
          result.phoneNumber != request.phoneNumber ||
          result.methodConfiguration != request.methodConfiguration) {
        throw const InstructorPaymentFailure(
          InstructorPaymentFailureKind.invalidResponse,
        );
      }
      setState(() {
        _clear();
        _notice =
            'Save acknowledged. Refreshing current setup before further edits.';
        _saving = false;
      });
      // Never install a mutation snapshot as current editable state.
      await _load();
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accessFailure(error)) {
        _invalidate();
        return;
      }
      setState(() {
        _fresh = false;
        if (error is InstructorPaymentFailure &&
            error.kind == InstructorPaymentFailureKind.stateConflict) {
          _dirty = true;
          _error = 'Setup changed elsewhere. Your edits remain read-only for copying. Refresh discards them; reconcile manually with the current setup.';
        } else {
          _clear();
          _error = 'The save could not be confirmed and may already have saved. Refresh before another change. No automatic retry will be made.';
        }
      });
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = _saving = false;
        });
      }
      // A successful save starts a newer load epoch, which owns its busy flag.
    }
  }

  Future<void> _refresh() async {
    if (!_check() || _busy) return;
    if (_dirty && !await _confirm(discard: true)) return;
    if (_check()) {
      _notice = null;
      await _load();
    }
  }

  Future<void> _close() async {
    if (!mounted || _closed || (_identityMatches && (_saving || _confirming))) {
      return;
    }
    if (_identityMatches && _dirty && !await _confirm(discard: true)) return;
    if (!mounted || _closed) return;
    // Latch before invoking the parent's callback: stale same-frame buttons and
    // pending reads cannot resurrect data while close/reopen awaits a rebuild.
    ++_epoch;
    _closed = true;
    _dismissDialog();
    _clear();
    setState(() {});
    widget.onClose();
  }

  String? _nameError(String? value) {
    final text = trimCatalogSpaces(value ?? '');
    return text.isEmpty ||
            text.runes.length > 160 ||
            text.codeUnits.any((u) => u <= 31 || u == 127)
        ? 'Use 1–160 characters without control characters.'
        : null;
  }

  String? _phoneError(String? value) {
    final text = value ?? '';
    final match = RegExp(r'^\+?[0-9]{7,15}$').firstMatch(text);
    return match == null || match.end != text.length
        ? 'Use 7–15 digits, optionally starting with +. No spaces or formatting.'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: !_identityMatches
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Administrator access changed. Close and verify access again.',
                ),
              ),
              TextButton(
                onPressed: _close,
                child: const Text('Close receiving setup'),
              ),
            ],
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
                  'My receiving details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Administrator setup only—not verified bank or wallet capability. Checkout and payments are not enabled here.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _refresh,
                      child: const Text('Refresh receiving setup'),
                    ),
                    TextButton(
                      onPressed: _saving || _confirming ? null : _close,
                      child: const Text('Close receiving setup'),
                    ),
                  ],
                ),
                if (_busy && !_confirming) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_notice != null)
                  Semantics(liveRegion: true, child: Text(_notice!)),
                if (_fresh || _dirty || _saving)
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_fresh && !_busy)
                          const Text('Unsaved edits (read-only)'),
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          readOnly: !_writable,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Recipient name',
                            errorMaxLines: 16,
                          ),
                          validator: _nameError,
                          textInputAction: TextInputAction.next,
                        ),
                        TextFormField(
                          controller: _phone,
                          enabled: !_busy,
                          readOnly: !_writable,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Receiving phone number',
                            errorMaxLines: 16,
                            helperText: 'The same number is used for both methods when enabled.',
                            helperMaxLines: 5,
                          ),
                          validator: _phoneError,
                        ),
                        const SizedBox(height: 12),
                        const Text('Enabled receiving methods'),
                        RadioGroup<InstructorPaymentMethodConfiguration>(
                          groupValue: _method,
                          onChanged: (value) {
                            if (!_check() || !_writable || value == null) {
                              return;
                            }
                            setState(() {
                              _method = value;
                              _dirty = true;
                            });
                          },
                          child: Column(
                            children: [
                              RadioListTile<
                                InstructorPaymentMethodConfiguration
                              >(
                                value: InstructorPaymentMethodConfiguration
                                    .instapayOnly,
                                enabled: _writable,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('InstaPay only'),
                              ),
                              RadioListTile<
                                InstructorPaymentMethodConfiguration
                              >(
                                value: InstructorPaymentMethodConfiguration
                                    .instapayAndVodafoneCash,
                                enabled: _writable,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'InstaPay and Vodafone Cash (same number)',
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _writable ? _save : null,
                          child: const Text('Save receiving details'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
  );
}
