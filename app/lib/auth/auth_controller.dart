import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

enum AuthStage {
  checking,
  signedOut,
  verification,
  recovery,
  completeProfile,
  ready,
  blocked,
}

class AuthController extends ChangeNotifier {
  AuthController(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _subscription = repository.events.listen(
      _event,
      onError: (Object _) => lock('connection'),
    );
  }
  final AuthRepository repository;
  final DateTime Function() _now;
  late final StreamSubscription<SessionEvent> _subscription;
  Future<void> _queue = Future.value();
  AuthStage stage = AuthStage.checking;
  AccountProfile? profile;
  AccessContext? access;
  String? message;
  String verificationEmail = '';
  bool busy = false;
  bool _recovery = false;
  bool _revoked = false;
  bool _registrationAttempted = false;
  bool _serverSessionActive = false;
  bool _disposed = false;
  int _epoch = 0;
  DateTime? _resendAt;
  Timer? _ticker;
  int get resendSeconds {
    final milliseconds = _resendAt?.difference(_now()).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  Future<void> get settled => _queue;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _clearProtected() {
    profile = null;
    access = null;
  }

  Future<void> start() async {
    final epoch = _epoch;
    try {
      final recovery = await repository.recoveryPending();
      if (!_current(epoch)) {
        return;
      }
      if (recovery && repository.hasSession) {
        _recovery = true;
        stage = AuthStage.recovery;
        _notify();
      } else {
        await checkAccess();
      }
    } catch (_) {
      lock('storage');
    }
  }

  void _event(SessionEvent event) {
    if (_disposed) {
      return;
    }
    if (event == SessionEvent.signedOut) {
      ++_epoch;
      _clearProtected();
      _recovery = false;
      _serverSessionActive = false;
      stage = AuthStage.signedOut;
      _notify();
      return;
    }
    if (event == SessionEvent.recovery) {
      ++_epoch;
      _recovery = true;
      _serverSessionActive = false;
      _clearProtected();
      stage = AuthStage.recovery;
      message = null;
      _notify();
      _queue = _queue.then((_) async {
        try {
          await repository.setRecoveryPending(true);
        } catch (_) {
          lock('storage');
        }
      });
      return;
    }
    if (_recovery || _revoked) {
      return;
    }
    _scheduleCheck(register: event == SessionEvent.signedIn);
  }

  Future<void> checkAccess() {
    if (_recovery || _revoked || _disposed) {
      return _queue;
    }
    return _scheduleCheck();
  }

  Future<void> _scheduleCheck({bool register = false}) {
    final epoch = ++_epoch;
    _clearProtected();
    stage = AuthStage.checking;
    _notify();
    _queue = _queue.then((_) async {
      if (!_current(epoch) || _recovery || _revoked) {
        return;
      }
      if (!repository.hasSession) {
        stage = AuthStage.signedOut;
        _notify();
        return;
      }
      try {
        AccessContext context;
        if (register && !_registrationAttempted) {
          _registrationAttempted = true;
          context = await repository.registerDevice();
        } else {
          try {
            context = await repository.getAccessContext();
          } on AccountFailure catch (error) {
            // Only the server may authorize recovery of interrupted registration.
            if (error.code != 'session_not_registered' ||
                _registrationAttempted ||
                !_current(epoch)) {
              rethrow;
            }
            _registrationAttempted = true;
            context = await repository.registerDevice();
          }
        }
        if (!_current(epoch) || _recovery) {
          return;
        }
        _serverSessionActive = true;
        final loaded = await repository.fetchProfile();
        if (!_current(epoch) || _recovery) {
          return;
        }
        access = context;
        profile = loaded;
        message = null;
        stage = loaded.complete ? AuthStage.ready : AuthStage.completeProfile;
        _notify();
      } catch (error) {
        if (_current(epoch)) {
          final code = _code(error);
          if ([
            'active_session_exists',
            'device_limit',
            'unverified_account',
            'unverified_or_invalid_session',
            'account_disabled',
            'device_revoked',
            'session_device_mismatch',
          ].contains(code)) {
            // A rejected new login must not end the existing server session.
            try {
              await repository.signOut();
            } catch (_) {
              lock('storage');
              return;
            }
          }
          lock(code);
        }
      }
    });
    return _queue;
  }

  void suspend() {
    if (_recovery || !repository.hasSession || _revoked) {
      return;
    }
    ++_epoch;
    _clearProtected();
    stage = AuthStage.checking;
    _notify();
  }

  void lock(String code) {
    ++_epoch;
    _clearProtected();
    if ([
      'device_limit',
      'session_replaced',
      'unverified_account',
      'active_session_exists',
      'storage',
      'unverified_or_invalid_session',
      'account_disabled',
      'device_revoked',
      'session_device_mismatch',
    ].contains(code)) {
      _revoked = true;
    }
    stage = AuthStage.blocked;
    message = failureMessage(code);
    _notify();
  }

  static String _code(Object error) =>
      error is AccountFailure ? error.code : 'connection';
  static String failureMessage(String code) => switch (code) {
    'device_limit' => 'This account has reached its device limit. Contact the academy for help.',
    'session_replaced' =>
      'This session is no longer active. Sign in again to continue.',
    'unverified_account' ||
    'email_not_confirmed' => 'Verify your email before signing in.',
    'unverified_or_invalid_session' =>
      'Verify your email and sign in again to continue.',
    'account_disabled' =>
      'Account access is disabled. Contact the academy for help.',
    'device_revoked' || 'session_device_mismatch' =>
      'This device cannot access the account. Contact the academy for help.',
    'active_session_exists' => 'An account session is already active. Log out there before signing in here.',
    'invalid_credentials' => 'Check your email and password and try again.',
    'over_email_send_rate_limit' || 'over_request_rate_limit' =>
      'Too many requests. Please wait before trying again.',
    'otp_expired' => 'The verification code has expired. Request a new email.',
    'weak_password' => 'Choose a stronger password.',
    'storage' => 'Secure storage is unavailable. Restart the app to try again.',
    'browser' => 'Could not open the browser. Please try again.',
    _ =>
      'Unable to verify account access. Check your connection and try again.',
  };
  Future<void> _action(Future<void> Function() action) async {
    if (busy || _disposed) {
      return;
    }
    busy = true;
    message = null;
    _notify();
    try {
      await action();
    } catch (error) {
      message = failureMessage(_code(error));
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> signIn(String email, String password) => _action(() async {
    // Only an explicit new authentication may leave a revoked session gate.
    _revoked = false;
    _registrationAttempted = false;
    _serverSessionActive = false;
    await repository.signIn(email.trim(), password);
  });
  Future<void> signUp(String email, String password, AccountProfile details) =>
      _action(() async {
        if (details.validationMessage != null) {
          message = details.validationMessage;
          return;
        }
        _revoked = false;
        _registrationAttempted = false;
        verificationEmail = email.trim();
        await repository.signUp(verificationEmail, password, details);
        if (!repository.hasSession && !_recovery) {
          stage = AuthStage.verification;
          _cooldown();
        }
      });
  Future<void> googleSignIn() => _action(() async {
    _revoked = false;
    _registrationAttempted = false;
    await repository.googleSignIn();
  });
  void showVerification(String email) {
    if (repository.hasSession || _recovery) {
      return;
    }
    verificationEmail = email.trim();
    stage = AuthStage.verification;
    message = null;
    _notify();
  }

  void showLogin() {
    if (repository.hasSession || _recovery) {
      return;
    }
    stage = AuthStage.signedOut;
    message = null;
    _notify();
  }

  void _cooldown() {
    _resendAt = _now().add(const Duration(seconds: 60));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendSeconds == 0) {
        timer.cancel();
      }
      _notify();
    });
  }

  Future<void> resend() => _action(() async {
    if (resendSeconds > 0) {
      return;
    }
    _cooldown();
    await repository.resendVerification(verificationEmail);
    message = 'Check your inbox for a verification link or code.';
  });
  Future<void> verify(String code) => _action(() async {
    _revoked = false;
    _registrationAttempted = false;
    await repository.verifyEmail(verificationEmail, code.trim());
  });
  Future<void> sendRecovery(String email) => _action(() async {
    await repository.sendRecovery(email.trim());
    message = 'If this account exists, a password reset link has been sent.';
  });
  Future<void> changePassword(String password) => _action(() async {
    if (!_recovery || !repository.hasSession) {
      throw const AccountFailure('auth');
    }
    await repository.updatePassword(password);
    // Recovery never claims a device or grants protected access. Require login.
    await logout();
    if (stage == AuthStage.signedOut) {
      message = 'Password updated. Sign in with your new password.';
    }
  });
  Future<void> saveProfile(AccountProfile details) => _action(() async {
    if (details.validationMessage != null) {
      message = details.validationMessage;
      return;
    }
    if (_recovery || _revoked || access == null) {
      return;
    }
    final epoch = ++_epoch;
    _clearProtected();
    stage = AuthStage.checking;
    _notify();
    try {
      await repository.getAccessContext();
      if (!_current(epoch)) {
        return;
      }
      await repository.saveProfile(details);
      if (_current(epoch)) {
        await checkAccess();
      }
    } catch (error) {
      if (_current(epoch)) {
        lock(_code(error));
      }
    }
  });
  Future<void> logout() async {
    ++_epoch;
    _clearProtected();
    _revoked = true;
    stage = AuthStage.checking;
    _notify();
    var serverEnded = true;
    try {
      if (repository.hasSession && _serverSessionActive) {
        await repository.endSession();
      }
    } catch (_) {
      serverEnded = false;
    }
    try {
      await repository.signOut();
      await repository.setRecoveryPending(false);
      _recovery = false;
      stage = AuthStage.signedOut;
      message = serverEnded ? null : 'Signed out on this device. Server session cleanup could not be confirmed.';
    } catch (_) {
      lock('storage');
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _ticker?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
