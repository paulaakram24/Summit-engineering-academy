import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../auth/auth_controller.dart';
import 'course_image_selector.dart';
import 'material_file_selection.dart';
import 'material_models.dart';

abstract class MaterialFileSelector {
  Future<SelectedMaterialFile?> select(AuthController auth, MaterialKind kind);
}

class SystemMaterialFileSelector implements MaterialFileSelector {
  SystemMaterialFileSelector({
    Future<XFile?> Function(MaterialKind)? open,
    this.readTimeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _open = open ?? _openSystem,
       _now = now ?? DateTime.now {
    if (readTimeout <= Duration.zero) {
      throw ArgumentError.value(readTimeout, 'readTimeout');
    }
  }
  final Future<XFile?> Function(MaterialKind) _open;
  final Duration readTimeout;
  final DateTime Function() _now;

  static Future<XFile?> _openSystem(MaterialKind kind) => openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: kind == MaterialKind.pdf
            ? 'PDF documents'
            : 'PDF or text documents',
        extensions: kind == MaterialKind.pdf ? ['pdf'] : ['pdf', 'txt'],
        mimeTypes: kind == MaterialKind.pdf
            ? ['application/pdf']
            : ['application/pdf', 'text/plain'],
        uniformTypeIdentifiers: kind == MaterialKind.pdf
            ? ['com.adobe.pdf']
            : ['com.adobe.pdf', 'public.plain-text'],
      ),
    ],
  );

  Future<SelectedMaterialFile> _read(
    XFile file,
    AuthController auth,
    MaterialKind kind,
  ) async {
    final result = Completer<SelectedMaterialFile>();
    final builder = BytesBuilder(copy: false);
    final access = auth.access;
    final started = _now();
    StreamSubscription<Uint8List>? subscription;
    void fail() {
      if (!result.isCompleted) {
        result.completeError(const MaterialFileSelectionFailure());
      }
    }

    bool active() {
      if (result.isCompleted) return false;
      final state = WidgetsBinding.instance.lifecycleState;
      if (_now().difference(started) >= readTimeout ||
          auth.stage != AuthStage.ready ||
          access?.role != 'admin' ||
          !identical(auth.access, access) ||
          (state != null && state != AppLifecycleState.resumed)) {
        fail();
        return false;
      }
      return true;
    }

    void authChanged() => active();
    final lifecycle = _MaterialReadLifecycle(fail);
    final deadline = Timer(readTimeout, fail);
    auth.addListener(authChanged);
    WidgetsBinding.instance.addObserver(lifecycle);
    try {
      if (active()) {
        // Observe late success/errors, but never open a stream after cancellation.
        unawaited(
          file.length().then<void>((length) {
            if (!active()) return;
            if (length <= 0 || length > maxSelectedMaterialFileBytes) {
              fail();
              return;
            }
            try {
              subscription = file.openRead().listen(
                (chunk) {
                  if (!active()) return;
                  if (chunk.length >
                      maxSelectedMaterialFileBytes - builder.length) {
                    fail();
                    return;
                  }
                  if (chunk.isNotEmpty) builder.add(chunk);
                },
                onError: (Object _, StackTrace _) => fail(),
                onDone: () {
                  if (!active()) return;
                  try {
                    final selected = SelectedMaterialFile.fromBytes(
                      kind: kind,
                      fileName: file.name,
                      bytes: builder.takeBytes(),
                    );
                    if (active()) result.complete(selected);
                  } catch (_) {
                    fail();
                  }
                },
              );
            } catch (_) {
              fail();
            }
          }, onError: (Object _, StackTrace _) => fail()),
        );
      }
      return await result.future;
    } finally {
      deadline.cancel();
      auth.removeListener(authChanged);
      WidgetsBinding.instance.removeObserver(lifecycle);
      builder.clear();
      // Cancellation stops delivery immediately. Do not let a provider's slow
      // cleanup future retain the selection lock; observe cleanup errors safely.
      final current = subscription;
      if (current != null) {
        unawaited(current.cancel().catchError((Object _) {}));
      }
    }
  }

  @override
  Future<SelectedMaterialFile?> select(
    AuthController auth,
    MaterialKind kind,
  ) async {
    try {
      if (kind != MaterialKind.pdf && kind != MaterialKind.file) {
        throw const MaterialFileSelectionFailure();
      }
      return await CourseImageSelection.runValue<SelectedMaterialFile>(auth, (
        returned,
      ) async {
        final file = await _open(kind);
        await returned();
        if (file == null) return null;
        return _read(file, auth, kind);
      });
    } catch (_) {
      // Never return a provider path, document contents or platform exception.
      throw const MaterialFileSelectionFailure();
    }
  }
}

class _MaterialReadLifecycle extends WidgetsBindingObserver {
  _MaterialReadLifecycle(this.cancel);
  final VoidCallback cancel;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }
}
