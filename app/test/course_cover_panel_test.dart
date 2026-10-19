import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_content_screen.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/content/course_cover_actions.dart';
import 'package:summit_academy/content/course_cover_panel.dart';
import 'package:summit_academy/content/course_covers.dart';
import 'package:summit_academy/content/course_image_selector.dart';

import 'auth_fakes.dart';
import 'content_admin_screen_test.dart' as content;

late Uint8List png;
Course course({String? path = 'private/current.png', bool deleted = false}) =>
    Course(
      id: '11111111-1111-4111-8111-111111111111',
      title: 'Engineering',
      instructor: 'Teacher',
      category: 'Civil',
      level: 'Beginner',
      pricePiasters: 100,
      coverPath: path,
      deletedAt: deleted ? DateTime.utc(2026) : null,
    );

class Covers implements CourseCoverActions {
  final downloads = <Course>[];
  final replacements = <(Course, Uint8List)>[];
  final removals = <Course>[];
  final cleanups = <String>[];
  Completer<Uint8List?>? readPending;
  Completer<Course>? writePending;
  Object? error;
  CoverCleanupResult result = const CoverCleanupResult(
    attempted: 20,
    cleaned: 19,
    failed: 1,
    mayHaveMore: true,
  );
  @override
  Future<Uint8List?> download(Course value) async {
    downloads.add(value);
    if (error != null) throw error!;
    if (readPending != null) return readPending!.future;
    return value.coverPath == null ? null : png;
  }

  @override
  Future<Course> replace(Course value, Uint8List bytes) async {
    replacements.add((value, bytes));
    if (error != null) throw error!;
    return writePending?.future ??
        Future.value(course(path: 'private/new.png'));
  }

  @override
  Future<Course> remove(Course value) async {
    removals.add(value);
    if (error != null) throw error!;
    return writePending?.future ?? Future.value(course(path: null));
  }

  @override
  Future<CoverCleanupResult> cleanup(String id) async {
    cleanups.add(id);
    if (error != null) throw error!;
    return result;
  }
}

class Selector implements CourseImageSelector {
  int calls = 0, recoveries = 0;
  bool lost = false;
  Uint8List? bytes = png;
  Object? error;
  Completer<Uint8List?>? pending;
  @override
  Future<bool> discardLostSelection() async {
    recoveries++;
    return lost;
  }

  @override
  Future<Uint8List?> select({Future<void> Function()? onPickerReturned}) async {
    calls++;
    if (error != null) throw error!;
    final result = await (pending?.future ?? Future.value(bytes));
    await onPickerReturned?.call();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawPaint(ui.Paint()..color = const ui.Color(0xff225588));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    png = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
    picture.dispose();
  });
  late FakeAuthRepository repo;
  late AuthController auth;
  late Covers covers;
  late Selector selector;
  setUp(() async {
    repo = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext(
        'admin',
        '11111111-1111-4111-8111-111111111111',
      );
    auth = AuthController(repo);
    await auth.start();
    covers = Covers();
    selector = Selector();
  });
  tearDown(() async {
    auth.dispose();
    await repo.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    Course? value,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseCoverPanel(
            course: value ?? course(),
            auth: auth,
            actions: covers,
            selector: selector,
            onClose: () {},
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.text('Choose image'));
    // Image codec work completes outside the fake test clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('private preview, cancelled selection and no implicit upload', (
    tester,
  ) async {
    selector.bytes = null;
    await show(tester);
    expect(find.byType(Image), findsOneWidget);
    await choose(tester);
    expect(covers.replacements, isEmpty);
    expect(find.text('Use selected cover'), findsNothing);
    expect(repo.calls.where((call) => call == 'access').length, 2);
  });
  testWidgets('selection is sanitized, confirmed and privately read back', (
    tester,
  ) async {
    await show(tester);
    await choose(tester);
    expect(find.text('Selected image — not yet saved'), findsOneWidget);
    expect(covers.replacements, isEmpty);
    await tap(tester, 'Use selected cover');
    expect(find.text('Replace course cover?'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(covers.replacements, isEmpty);
    await tap(tester, 'Use selected cover');
    await tap(tester, 'Confirm cover');
    expect(covers.replacements, hasLength(1));
    expect(covers.replacements.single.$1.coverPath, 'private/current.png');
    expect(covers.downloads.last.coverPath, 'private/new.png');
    expect(find.text('Use selected cover'), findsNothing);
    expect(covers.cleanups, isEmpty);
  });
  testWidgets('removal confirmation detaches without implicit cleanup', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Remove cover');
    await tap(tester, 'Cancel');
    expect(covers.removals, isEmpty);
    await tap(tester, 'Remove cover');
    await tap(tester, 'Confirm removal');
    expect(covers.removals, hasLength(1));
    expect(covers.downloads.last.coverPath, isNull);
    expect(find.byType(Image), findsNothing);
    expect(covers.cleanups, isEmpty);
  });
  testWidgets('cleanup is one explicit pass with partial and empty results', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Clean retired covers (up to 20)');
    await tap(tester, 'Cancel');
    expect(covers.cleanups, isEmpty);
    await tap(tester, 'Clean retired covers (up to 20)');
    await tap(tester, 'Confirm cleanup');
    expect(covers.cleanups, hasLength(1));
    expect(
      find.textContaining('19 cleaned, 1 failed, 20 attempted'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(covers.cleanups, hasLength(1));
    covers.result = const CoverCleanupResult(
      attempted: 0,
      cleaned: 0,
      failed: 0,
      mayHaveMore: false,
    );
    await tap(tester, 'Clean retired covers (up to 20)');
    await tap(tester, 'Confirm cleanup');
    expect(find.textContaining('This pass is complete.'), findsOneWidget);
  });
  testWidgets('cleanup-only failure preserves current and unsaved image', (
    tester,
  ) async {
    await show(tester);
    await choose(tester);
    expect(find.byType(Image), findsNWidgets(2));
    covers.error = StateError('secret cleanup response');
    await tap(tester, 'Clean retired covers (up to 20)');
    await tap(tester, 'Confirm cleanup');
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('Use selected cover'), findsOneWidget);
    expect(find.textContaining('Cleanup could not finish.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(covers.replacements, isEmpty);
    covers.error = null;
    await tap(tester, 'Clean retired covers (up to 20)');
    await tap(tester, 'Confirm cleanup');
    expect(covers.cleanups, hasLength(2));
    expect(find.byType(Image), findsNWidgets(2));
  });
  testWidgets(
    'pause during delayed picker access check cannot install preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Offstage(child: AuthPanel(controller: auth)),
                CourseCoverPanel(
                  course: course(path: null),
                  auth: auth,
                  actions: covers,
                  selector: selector,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.accessCompleter = Completer<AccessContext>();
      await tester.tap(find.text('Choose image'));
      await tester.pump();
      expect(CourseImageSelection.active(auth), isFalse);
      expect(auth.stage, AuthStage.ready);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(auth.stage, AuthStage.checking);
      repo.accessCompleter!.complete(repo.accessContext);
      // Paused apps do not render frames; flush completion without requesting one.
      await tester.idle();
      expect(find.text('Use selected cover'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(covers.replacements, isEmpty);
      repo.accessCompleter = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Use selected cover'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    },
  );
  testWidgets('busy picker prevents duplicate selection and other actions', (
    tester,
  ) async {
    selector.pending = Completer<Uint8List?>();
    await show(tester);
    await tester.tap(find.text('Choose image'));
    await tester.pump();
    expect(CourseImageSelection.active(auth), isTrue);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose image'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Remove cover'),
          )
          .onPressed,
      isNull,
    );
    selector.pending!.complete(null);
    await tester.pumpAndSettle();
    expect(selector.calls, 1);
    expect(CourseImageSelection.active(auth), isFalse);
  });
  testWidgets('invalid image and picker failures are sanitized', (
    tester,
  ) async {
    selector.bytes = Uint8List.fromList([1, 2, 3]);
    await show(tester);
    await choose(tester);
    expect(find.text(const CourseCoverFailure().message), findsOneWidget);
    expect(covers.replacements, isEmpty);
    selector.error = StateError('secret URL token');
    await choose(tester);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Use selected cover'), findsNothing);
  });
  testWidgets('uncertain write clears preview and requires fresh course', (
    tester,
  ) async {
    await show(tester);
    covers.error = TimeoutException('secret token');
    await tap(tester, 'Remove cover');
    await tap(tester, 'Confirm removal');
    expect(
      find.textContaining('last change may already have completed'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose image'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('access loss during confirmation prevents mutation', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Remove cover');
    auth.lock('device_revoked');
    await tester.pumpAndSettle();
    expect(find.text('Access changed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm removal'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, 'Cancel');
    expect(find.byType(Image), findsNothing);
    expect(covers.removals, isEmpty);
  });
  testWidgets('late preview after revocation is discarded', (tester) async {
    covers.readPending = Completer<Uint8List?>();
    await show(tester, settle: false);
    await tester.pump();
    auth.lock('device_revoked');
    covers.readPending!.complete(png);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late selector after rapid suspension and reopening is discarded',
    (tester) async {
      selector.pending = Completer<Uint8List?>();
      await show(tester);
      await tester.tap(find.text('Choose image'));
      await tester.pump();
      auth.suspend();
      await tester.runAsync(auth.checkAccess);
      selector.pending!.complete(png);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(covers.replacements, isEmpty);
      expect(CourseImageSelection.active(auth), isFalse);
    },
  );
  testWidgets('role change found after picker locks access', (tester) async {
    await show(tester);
    repo.accessContext = FakeAuthRepository.context;
    await choose(tester);
    expect(auth.stage, AuthStage.blocked);
    expect(find.byType(Image), findsNothing);
    expect(covers.replacements, isEmpty);
  });
  testWidgets('late write after disposal performs no preview read', (
    tester,
  ) async {
    await show(tester);
    covers.writePending = Completer<Course>();
    await tap(tester, 'Remove cover');
    await tester.tap(find.text('Confirm removal'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    covers.writePending!.complete(course(path: null));
    await tester.pumpAndSettle();
    expect(covers.downloads, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('interrupted native selection is discarded without upload', (
    tester,
  ) async {
    selector.lost = true;
    await show(tester);
    expect(
      find.textContaining('interrupted selection was discarded'),
      findsOneWidget,
    );
    expect(covers.replacements, isEmpty);
    expect(selector.calls, 0);
  });
  testWidgets('deleted course cannot select, read or clean covers', (
    tester,
  ) async {
    await show(tester, value: course(deleted: true));
    expect(find.text('Choose image'), findsNothing);
    expect(covers.downloads, isEmpty);
    expect(selector.recoveries, 0);
  });
  testWidgets(
    'course list integrates injected cover panel and unsaved guidance',
    (tester) async {
      final metadata = content.FakeContentRepository()..courses = [course()];
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AdminContentScreen(
            repository: metadata,
            authController: auth,
            coverActions: covers,
            imageSelector: selector,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Course cover');
      expect(find.text('Cover: Engineering'), findsOneWidget);
      await tap(tester, 'Back to courses');
      expect(metadata.courseRequests, hasLength(2));
      await tap(tester, 'New course');
      expect(find.textContaining('Save course metadata first'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Price (EGP)'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.decoration!.helperMaxLines, 3);
      expect(find.text('Choose image'), findsNothing);
    },
  );
  testWidgets('cover actions fit a narrow phone at font scale 1.15', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.15)),
          child: Scaffold(
            body: CourseCoverPanel(
              course: course(),
              auth: auth,
              actions: covers,
              selector: selector,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester);
    await tap(tester, 'Use selected cover');
    expect(find.text('Replace course cover?'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late preview from previous course input cannot replace new preview',
    (tester) async {
      covers.readPending = Completer<Uint8List?>();
      await show(tester, settle: false);
      await tester.pump();
      final old = covers.readPending!;
      covers.readPending = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseCoverPanel(
              course: course(path: null),
              auth: auth,
              actions: covers,
              selector: selector,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      old.complete(png);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
