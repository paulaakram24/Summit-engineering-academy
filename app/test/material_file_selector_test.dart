import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/material_file_selection.dart';
import 'package:summit_academy/content/material_file_selector.dart';
import 'package:summit_academy/content/material_models.dart';
import 'package:summit_academy/content/course_image_selector.dart';

import 'auth_fakes.dart';

class _StreamFile extends XFile {
  _StreamFile({
    this.declaredLength = 194,
    this.pendingLength,
    this.cleanup,
    this.fileName = 'synthetic.txt',
    this.openError,
  }) : super('synthetic.txt');

  final int declaredLength;
  final Completer<int>? pendingLength;
  final Completer<void>? cleanup;
  final String fileName;
  final Object? openError;
  int opens = 0, cancellations = 0;
  late final chunks = StreamController<Uint8List>(
    sync: true,
    onCancel: () {
      ++cancellations;
      return cleanup?.future;
    },
  );

  @override
  String get name => fileName;

  @override
  Future<int> length() => pendingLength?.future ?? Future.value(declaredLength);

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    ++opens;
    if (openError != null) throw openError!;
    return chunks.stream;
  }

  void dispose() => unawaited(chunks.close());
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAuthRepository accounts;
  late AuthController auth;
  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext(
        'admin',
        '11111111-1111-4111-8111-111111111111',
      );
    auth = AuthController(accounts);
    await auth.start();
    accounts.calls.clear();
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });
  final failure = throwsA(isA<MaterialFileSelectionFailure>());
  XFile text({String name = 'synthetic.txt'}) => XFile.fromData(
    Uint8List.fromList(utf8.encode('Synthetic teaching fixture\n')),
    name: name,
    path: name,
  );

  const readTimeout = Duration(milliseconds: 100);
  SystemMaterialFileSelector streamSelector(_StreamFile file) {
    addTearDown(file.dispose);
    return SystemMaterialFileSelector(
      open: (_) async => file,
      readTimeout: readTimeout,
      now: binding.clock.now,
    );
  }

  Future<void> pickerAvailable(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (auth.stage != AuthStage.ready) {
      await tester.runAsync(() => auth.checkAccess());
    }
    final result = await SystemMaterialFileSelector(open: (_) async => text())
        .select(auth, MaterialKind.file);
    expect(result!.fileName, 'synthetic.txt');
    expect(CourseImageSelection.active(auth), isFalse);
    // Old read deadlines/listeners must not affect a subsequent admitted pick.
    await tester.pump(const Duration(seconds: 21));
    expect(auth.stage, AuthStage.ready);
  }

  for (final empty in [false, true]) {
    testWidgets(
      '${empty ? 'empty' : 'dribbling byte'} chunks cannot extend absolute deadline',
      (tester) async {
        final file = _StreamFile();
        final selector = streamSelector(file);
        final rejected = expectLater(
          selector.select(auth, MaterialKind.file),
          failure,
        );
        await tester.pump();
        expect(file.opens, 1);
        for (var i = 0; i < 4; ++i) {
          file.chunks.add(Uint8List.fromList(empty ? [] : [65]));
          await tester.pump(const Duration(milliseconds: 20));
          expect(file.cancellations, 0);
        }
        await tester.pump(const Duration(milliseconds: 20));
        await rejected;
        expect(file.cancellations, 1);
        expect(CourseImageSelection.active(auth), isFalse);
        await pickerAvailable(tester);
      },
    );
  }

  testWidgets('stalled stream reaches deadline and cancels subscription', (
    tester,
  ) async {
    final file = _StreamFile();
    final rejected = expectLater(
      streamSelector(file).select(auth, MaterialKind.file),
      failure,
    );
    await tester.pump();
    expect(file.opens, 1);
    await tester.pump(readTimeout);
    await rejected;
    expect(file.cancellations, 1);
    await pickerAvailable(tester);
  });

  testWidgets('length and stream share one absolute deadline', (tester) async {
    final length = Completer<int>();
    final file = _StreamFile(pendingLength: length);
    final rejected = expectLater(
      streamSelector(file).select(auth, MaterialKind.file),
      failure,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(file.opens, 0);
    length.complete(194);
    await tester.pump();
    expect(file.opens, 1);
    file.chunks.add(Uint8List.fromList([65]));
    await tester.pump(const Duration(milliseconds: 20));
    await rejected;
    expect(file.cancellations, 1);
    await pickerAvailable(tester);
  });

  for (final lateError in [false, true]) {
    testWidgets(
      'length deadline safely ignores late ${lateError ? 'error' : 'success'}',
      (tester) async {
        final length = Completer<int>();
        final file = _StreamFile(pendingLength: length);
        final rejected = expectLater(
          streamSelector(file).select(auth, MaterialKind.file),
          failure,
        );
        await tester.pump();
        await tester.pump(readTimeout);
        await rejected;
        expect(file.opens, 0);
        // Prove the helper lock is released even while length is still pending.
        await pickerAvailable(tester);
        if (lateError) {
          length.completeError(StateError('PRIVATE_LENGTH_ERROR'));
        } else {
          length.complete(194);
        }
        await tester.pump();
        expect(file.opens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final duringLength in [false, true]) {
    for (final loss in ['auth', 'device replacement', 'background']) {
      testWidgets(
        '$loss during ${duringLength ? 'length' : 'stream'} aborts and releases picker',
        (tester) async {
          final length = duringLength ? Completer<int>() : null;
          final file = _StreamFile(pendingLength: length);
          final rejected = expectLater(
            streamSelector(file).select(auth, MaterialKind.file),
            failure,
          );
          await tester.pump();
          expect(file.opens, duringLength ? 0 : 1);
          if (!duringLength) file.chunks.add(Uint8List.fromList([65]));
          switch (loss) {
            case 'auth':
              auth.suspend();
            case 'device replacement':
              accounts.accessContext = const AccessContext(
                'admin',
                '22222222-2222-4222-8222-222222222222',
              );
              await tester.runAsync(() => auth.checkAccess());
            case 'background':
              binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          }
          await tester.pump();
          await rejected;
          expect(file.cancellations, duringLength ? 0 : 1);
          await pickerAvailable(tester);
          length?.complete(194);
          await tester.pump();
          expect(file.opens, duringLength ? 0 : 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final length in [-1, 0, maxSelectedMaterialFileBytes + 1]) {
    testWidgets('invalid declared length $length never opens stream', (
      tester,
    ) async {
      final file = _StreamFile(declaredLength: length);
      await expectLater(
        streamSelector(file).select(auth, MaterialKind.file),
        failure,
      );
      expect(file.opens, 0);
      await pickerAvailable(tester);
    });
  }

  testWidgets('cumulative bytes stay capped despite smaller declared length', (
    tester,
  ) async {
    final file = _StreamFile(declaredLength: 1);
    final rejected = expectLater(
      streamSelector(file).select(auth, MaterialKind.file),
      failure,
    );
    await tester.pump();
    file.chunks.add(Uint8List(maxSelectedMaterialFileBytes - 1));
    file.chunks.add(Uint8List(2));
    await tester.pump();
    await rejected;
    expect(file.cancellations, 1);
    await pickerAvailable(tester);
  });

  for (final terminal in [
    'stream error',
    'invalid UTF-8',
    'empty file',
    'invalid PDF',
  ]) {
    testWidgets('$terminal cancels stream and preserves strict screening', (
      tester,
    ) async {
      final pdf = terminal == 'invalid PDF';
      final file = _StreamFile(
        fileName: pdf ? 'synthetic.pdf' : 'synthetic.txt',
      );
      final rejected = expectLater(
        streamSelector(file)
            .select(auth, pdf ? MaterialKind.pdf : MaterialKind.file),
        failure,
      );
      await tester.pump();
      switch (terminal) {
        case 'stream error':
          file.chunks.addError(StateError('PRIVATE_STREAM_ERROR'));
        case 'invalid UTF-8':
          file.chunks.add(Uint8List.fromList([255]));
          unawaited(file.chunks.close());
        case 'empty file':
          unawaited(file.chunks.close());
        case 'invalid PDF':
          file.chunks.add(Uint8List.fromList(ascii.encode('not a PDF')));
          unawaited(file.chunks.close());
      }
      await tester.pump();
      await rejected;
      expect(file.cancellations, 1);
      await pickerAvailable(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('openRead exception is sanitized and releases read deadline', (
    tester,
  ) async {
    final file = _StreamFile(openError: StateError('PRIVATE_OPEN_ERROR'));
    await expectLater(
      streamSelector(file).select(auth, MaterialKind.file),
      failure,
    );
    expect(file.opens, 1);
    expect(file.cancellations, 0);
    await pickerAvailable(tester);
  });

  testWidgets('slow failing provider cleanup cannot retain picker lock', (
    tester,
  ) async {
    final cleanup = Completer<void>();
    final file = _StreamFile(cleanup: cleanup);
    final rejected = expectLater(
      streamSelector(file).select(auth, MaterialKind.file),
      failure,
    );
    await tester.pump();
    await tester.pump(readTimeout);
    await rejected;
    expect(file.cancellations, 1);
    await pickerAvailable(tester);
    cleanup.completeError(StateError('PRIVATE_CLEANUP_ERROR'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed bounded stream still requires fresh server admission',
    (tester) async {
      final file = _StreamFile();
      final admission = Completer<AccessContext>();
      accounts.accessCompleter = admission;
      var delivered = false;
      final selecting = streamSelector(file)
          .select(auth, MaterialKind.file)
          .then((value) {
            delivered = true;
            return value;
          });
      await tester.pump();
      file.chunks.add(Uint8List.fromList(utf8.encode('Synthetic fixture\n')));
      unawaited(file.chunks.close());
      await tester.pump();
      expect(delivered, isFalse);
      expect(accounts.calls, contains('access'));
      expect(file.cancellations, 1);
      admission.complete(accounts.accessContext);
      final selected = await selecting;
      expect(selected!.fileName, 'synthetic.txt');
      expect(selected.byteLength, utf8.encode('Synthetic fixture\n').length);
      accounts.accessCompleter = null;
      await pickerAvailable(tester);
    },
  );

  test(
    'cancel revalidates access without selecting or uploading bytes',
    () async {
      final selector = SystemMaterialFileSelector(open: (_) async => null);
      expect(await selector.select(auth, MaterialKind.pdf), isNull);
      expect(auth.stage, AuthStage.ready);
      expect(accounts.calls, contains('access'));
    },
  );
  test(
    'valid bounded text returns a selected file after admission check',
    () async {
      final selector = SystemMaterialFileSelector(open: (_) async => text());
      final selected = await selector.select(auth, MaterialKind.file);
      expect(selected!.fileName, 'synthetic.txt');
      expect(selected.contentType, 'text/plain');
      expect(auth.stage, AuthStage.ready);
      expect(accounts.calls, contains('access'));
    },
  );
  test(
    'PDF selection rejects renamed plain text after reading actual bytes',
    () async {
      final selector = SystemMaterialFileSelector(
        open: (_) async => text(name: 'synthetic.pdf'),
      );
      await expectLater(selector.select(auth, MaterialKind.pdf), failure);
    },
  );
  test('non-file kinds never open the system picker', () async {
    var opens = 0;
    final selector = SystemMaterialFileSelector(
      open: (_) async {
        opens++;
        return text();
      },
    );
    for (final kind in [
      MaterialKind.assignment,
      MaterialKind.link,
      MaterialKind.video,
    ]) {
      await expectLater(selector.select(auth, kind), failure);
    }
    expect(opens, 0);
  });
  test('fresh admission denial discards selected data', () async {
    final selector = SystemMaterialFileSelector(
      open: (_) async {
        accounts.accessContext = const AccessContext(
          'student',
          '11111111-1111-4111-8111-111111111111',
        );
        return text();
      },
    );
    await expectLater(selector.select(auth, MaterialKind.file), failure);
    expect(auth.stage, AuthStage.blocked);
  });
  test(
    'access closure during selection cannot return old-account bytes',
    () async {
      final selector = SystemMaterialFileSelector(
        open: (_) async {
          auth.suspend();
          return text();
        },
      );
      await expectLater(selector.select(auth, MaterialKind.file), failure);
    },
  );
  test('platform errors are sanitized', () async {
    final selector = SystemMaterialFileSelector(
      open: (_) async => throw StateError('PRIVATE_PATH_CANARY'),
    );
    await expectLater(
      selector.select(auth, MaterialKind.file),
      throwsA(
        isA<MaterialFileSelectionFailure>().having(
          (e) => e.toString(),
          'safe',
          isNot(contains('PRIVATE_PATH_CANARY')),
        ),
      ),
    );
  });
}
