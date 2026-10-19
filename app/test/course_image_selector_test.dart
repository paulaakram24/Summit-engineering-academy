import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/course_covers.dart';
import 'package:summit_academy/content/course_image_selector.dart';

import 'auth_fakes.dart';

class Picker extends ImagePicker {
  XFile? file;
  ImageSource? source;
  bool? metadata;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    metadata = requestFullMetadata;
    return file;
  }
}

class OversizedFile extends XFile {
  OversizedFile() : super('unused');
  bool read = false;
  @override
  Future<int> length() async => maxCoverInputBytes + 1;
  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    return Uint8List(0);
  }
}

class GrowingFile extends XFile {
  GrowingFile() : super('unused');
  bool cancelled = false, continued = false;
  @override
  Future<int> length() async => 1;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    try {
      yield Uint8List(maxCoverInputBytes);
      yield Uint8List(1);
      continued = true;
      yield Uint8List(10);
    } finally {
      cancelled = true;
    }
  }
}

class TrackedFile extends XFile {
  TrackedFile() : super('unused');
  bool inspected = false;
  @override
  Future<int> length() async {
    inspected = true;
    return 1;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      Stream.value(Uint8List.fromList([7]));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'system selector uses gallery without metadata and handles cancellation',
    () async {
      final picker = Picker();
      final selector = SystemCourseImageSelector(picker: picker);
      expect(await selector.select(), isNull);
      expect(picker.source, ImageSource.gallery);
      expect(picker.metadata, isFalse);
      picker.file = XFile.fromData(Uint8List.fromList([1, 2, 3]));
      expect(await selector.select(), [1, 2, 3]);
    },
  );
  test('oversized input is refused before file read', () async {
    final file = OversizedFile();
    final selector = SystemCourseImageSelector(picker: Picker()..file = file);
    await expectLater(selector.select(), throwsA(isA<CourseCoverFailure>()));
    expect(file.read, isFalse);
  });
  test('growing file stream is bounded and cancelled at 5 MiB', () async {
    final file = GrowingFile();
    final selector = SystemCourseImageSelector(picker: Picker()..file = file);
    await expectLater(selector.select(), throwsA(isA<CourseCoverFailure>()));
    expect(file.cancelled, isTrue);
    expect(file.continued, isFalse);
  });
  testWidgets(
    'picker handoff survives lifecycle then restores normal locking',
    (tester) async {
      final repo = FakeAuthRepository()
        ..hasSession = true
        ..accessContext = const AccessContext(
          'admin',
          '11111111-1111-4111-8111-111111111111',
        );
      final auth = AuthController(repo);
      addTearDown(() async {
        auth.dispose();
        await repo.dispose();
      });
      await auth.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuthPanel(controller: auth)),
        ),
      );
      final pending = Completer<Uint8List?>();
      final selected = CourseImageSelection.run(auth, (returned) async {
        final result = await pending.future;
        await returned();
        return result;
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(auth.stage, AuthStage.ready);
      pending.complete(null);
      expect(await selected, isNull);
      expect(repo.calls.where((call) => call == 'access'), hasLength(2));
      expect(CourseImageSelection.active(auth), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(auth.stage, AuthStage.checking);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await auth.settled;
      await tester.pumpAndSettle();
      expect(auth.stage, AuthStage.ready);
    },
  );
  for (final resultFirst in [true, false]) {
    testWidgets(
      '${resultFirst ? 'result then resume' : 'resume then result'} waits before file read and fresh access',
      (tester) async {
        final repo = FakeAuthRepository()
          ..hasSession = true
          ..accessContext = const AccessContext(
            'admin',
            '11111111-1111-4111-8111-111111111111',
          );
        final auth = AuthController(repo);
        addTearDown(() async {
          auth.dispose();
          await repo.dispose();
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await auth.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AuthPanel(controller: auth)),
          ),
        );
        final nativeResult = Completer<void>();
        final file = TrackedFile();
        final selector = SystemCourseImageSelector(
          picker: Picker()..file = file,
        );
        late Future<Uint8List?> selected;
        await tester.runAsync(() async {
          selected = CourseImageSelection.run(auth, (returned) async {
            await nativeResult.future;
            return selector.select(onPickerReturned: returned);
          });
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        if (resultFirst) {
          nativeResult.complete();
          await tester.runAsync(
            () async => Future<void>.delayed(Duration.zero),
          );
          expect(file.inspected, isFalse);
          expect(repo.calls.where((call) => call == 'access'), hasLength(1));
          expect(CourseImageSelection.active(auth), isTrue);
          expect(auth.stage, AuthStage.ready);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          nativeResult.complete();
        }
        expect(await tester.runAsync(() => selected), [7]);
        expect(file.inspected, isTrue);
        expect(repo.calls.where((call) => call == 'access'), hasLength(2));
        expect(auth.stage, AuthStage.ready);
        expect(CourseImageSelection.active(auth), isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        expect(auth.stage, AuthStage.checking);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );
  }
  testWidgets(
    'missing resume times out the native handoff and invalidates access',
    (tester) async {
      final repo = FakeAuthRepository()
        ..hasSession = true
        ..accessContext = const AccessContext(
          'admin',
          '11111111-1111-4111-8111-111111111111',
        );
      final auth = AuthController(repo);
      addTearDown(() async {
        auth.dispose();
        await repo.dispose();
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await auth.start();
      final nativeResult = Completer<void>();
      final selected = CourseImageSelection.run(auth, (returned) async {
        await nativeResult.future;
        await returned();
        return null;
      });
      final failed = expectLater(selected, throwsA(isA<CourseCoverFailure>()));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      nativeResult.complete();
      await tester.idle();
      await tester.pump(const Duration(seconds: 21));
      await failed;
      expect(CourseImageSelection.active(auth), isFalse);
      expect(auth.stage, AuthStage.checking);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  test(
    'server failure after cancellation invalidates access and releases lease',
    () async {
      final repo = FakeAuthRepository()
        ..hasSession = true
        ..accessContext = const AccessContext(
          'admin',
          '11111111-1111-4111-8111-111111111111',
        );
      final auth = AuthController(repo);
      addTearDown(() async {
        auth.dispose();
        await repo.dispose();
      });
      await auth.start();
      repo.accessError = StateError('private response');
      await expectLater(
        CourseImageSelection.run(auth, (returned) async {
          await returned();
          return null;
        }),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(auth.stage, AuthStage.blocked);
      expect(CourseImageSelection.active(auth), isFalse);
    },
  );
}
