import 'dart:async';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_controller.dart';
import 'course_covers.dart';

abstract class CourseImageSelector {
  Future<Uint8List?> select({Future<void> Function()? onPickerReturned});
  Future<bool> discardLostSelection();
}

class SystemCourseImageSelector implements CourseImageSelector {
  SystemCourseImageSelector({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<bool> discardLostSelection() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    // No durable association with a course/auth session survives process death.
    // Consume recovery data without reading or attaching it to another course.
    return !(await _picker.retrieveLostData()).isEmpty;
  }

  @override
  Future<Uint8List?> select({Future<void> Function()? onPickerReturned}) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    await onPickerReturned?.call();
    if (file == null) return null;
    if (await file.length().timeout(const Duration(seconds: 20)) >
        maxCoverInputBytes) {
      throw const CourseCoverFailure();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead().timeout(
      const Duration(seconds: 20),
    )) {
      if (chunk.length > maxCoverInputBytes - bytes.length) {
        throw const CourseCoverFailure();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

class _SelectionLifecycle extends WidgetsBindingObserver {
  _SelectionLifecycle(this.onBackground)
    : foreground =
          WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  final VoidCallback onBackground;
  bool foreground;
  bool picking = true;
  Completer<void>? _resumed;
  Future<void> waitForForeground() {
    if (foreground) return Future.value();
    return (_resumed ??= Completer<void>()).future.timeout(
      const Duration(seconds: 20),
    );
  }

  void cancelWait() {
    if (_resumed != null && !_resumed!.isCompleted) {
      _resumed!.completeError(const CourseCoverFailure());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && _resumed != null && !_resumed!.isCompleted) {
      _resumed!.complete();
    }
    if (!picking && !foreground) onBackground();
  }
}

/// Only the native picker itself bypasses the generic background refresh.
/// A fresh server access check is mandatory before returning even cancellation.
/// Actual auth notifications still invalidate all workspace and preview state.
class CourseImageSelection {
  static final _active = <AuthController>{};
  static final _running = <AuthController>{};
  static bool active(AuthController auth) => _active.contains(auth);

  static Future<Uint8List?> run(
    AuthController auth,
    Future<Uint8List?> Function(Future<void> Function() onPickerReturned)
    select,
  ) => runValue<Uint8List>(auth, select);

  /// Shared native-document handoff. Only the system picker bypasses ordinary
  /// background locking; all returned values still require fresh admission.
  static Future<T?> runValue<T>(
    AuthController auth,
    Future<T?> Function(Future<void> Function() onPickerReturned) select,
  ) async {
    final access = auth.access;
    if (access?.role != 'admin' ||
        auth.stage != AuthStage.ready ||
        _running.contains(auth)) {
      throw const CourseCoverFailure();
    }
    var invalidated = false;
    void background() {
      invalidated = true;
      auth.suspend();
    }

    final lifecycle = _SelectionLifecycle(background);
    if (!lifecycle.foreground) throw const CourseCoverFailure();
    Future<void> pickerReturned() async {
      if (invalidated) throw const CourseCoverFailure();
      // Android can deliver the activity result before Flutter observes resume.
      // Keep only the native handoff pending; no file reads/network start yet.
      try {
        await lifecycle.waitForForeground();
      } catch (_) {
        background();
        throw const CourseCoverFailure();
      }
      lifecycle.picking = false;
      _active.remove(auth);
      if (!lifecycle.foreground) background();
      if (invalidated) throw const CourseCoverFailure();
    }

    void changed() {
      if (auth.stage != AuthStage.ready || !identical(auth.access, access)) {
        invalidated = true;
        lifecycle.cancelWait();
      }
    }

    auth.addListener(changed);
    WidgetsBinding.instance.addObserver(lifecycle);
    _running.add(auth);
    _active.add(auth);
    try {
      T? selected;
      Object? failure;
      try {
        selected = await select(pickerReturned);
      } catch (error) {
        failure = error;
      }
      // Also release the handoff on picker exceptions or a faulty adapter.
      if (lifecycle.picking && !invalidated) await pickerReturned();
      if (invalidated) throw const CourseCoverFailure();
      try {
        final fresh = await auth.repository.getAccessContext().timeout(
          const Duration(seconds: 20),
        );
        if (fresh.role != 'admin' || fresh.deviceId != access!.deviceId) {
          throw const CourseCoverFailure();
        }
      } catch (_) {
        if (!invalidated) auth.lock('connection');
        throw const CourseCoverFailure();
      }
      if (invalidated || !lifecycle.foreground || failure != null) {
        throw const CourseCoverFailure();
      }
      return selected;
    } finally {
      _active.remove(auth);
      _running.remove(auth);
      WidgetsBinding.instance.removeObserver(lifecycle);
      auth.removeListener(changed);
    }
  }
}
