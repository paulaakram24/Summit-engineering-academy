import 'dart:async';
import 'dart:typed_data';

// Test-only platform substitution keeps the production selector in the route.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_content_screen.dart';
import 'package:summit_academy/content/admin_materials_panel.dart';
import 'package:summit_academy/content/course_image_selector.dart';
import 'package:summit_academy/content/material_file_upload_panel.dart';
import 'package:summit_academy/content/material_file_upload_repository.dart'
    show MaterialFileUpload;
import 'package:summit_academy/main.dart';

import 'admin_materials_panel_test.dart' as materials;
import 'auth_fakes.dart';
import 'content_admin_screen_test.dart' show FakeContentRepository;
import 'material_file_upload_panel_test.dart' as uploads;
import 'material_models_test.dart' as fixtures;

class _Picker extends FileSelectorPlatform {
  Completer<XFile?>? pending;
  int opens = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    ++opens;
    pending = Completer<XFile?>();
    return pending!.future;
  }
}

class _Document extends XFile {
  _Document()
    : super.fromData(
        Uint8List.fromList([...List.filled(193, 65), 10]),
        name: 'synthetic-194.txt',
        path: 'synthetic-194.txt',
      );

  int lengthReads = 0, streamReads = 0;

  @override
  Future<int> length() {
    ++lengthReads;
    return super.length();
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    ++streamReads;
    return super.openRead(start, end);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAuthRepository accounts;
  late AuthController auth;
  late FakeContentRepository content;
  late materials.PanelMaterials materialRepository;
  late uploads.UploadPanelRepositoryFake uploadRepository;
  late FileSelectorPlatform originalPlatform;
  late _Picker picker;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', fixtures.actorId);
    auth = AuthController(accounts);
    await auth.start();
    content = FakeContentRepository()
      ..courses = [materials.parentCourse()]
      ..sessions = [materials.parentSession()];
    materialRepository = materials.PanelMaterials()
      ..rows = [uploads.material()];
    uploadRepository = uploads.UploadPanelRepositoryFake();
    originalPlatform = FileSelectorPlatform.instance;
    picker = _Picker();
    FileSelectorPlatform.instance = picker;
  });

  tearDown(() async {
    FileSelectorPlatform.instance = originalPlatform;
    auth.dispose();
    await accounts.dispose();
  });

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> enterUploads(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      SummitApp(
        authController: auth,
        contentRepository: content,
        materialRepository: materialRepository,
        materialFileUploadRepository: uploadRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Manage courses');
    await tap(tester, 'Sessions');
    await tap(tester, 'Materials');
    await tap(tester, 'Upload file');
    expect(find.byType(AuthPanel, skipOffstage: false), findsOneWidget);
    expect(find.byType(AdminContentScreen), findsOneWidget);
    expect(find.byType(AdminMaterialsPanel), findsOneWidget);
    expect(find.byType(MaterialFileUploadPanel), findsOneWidget);
    expect(content.courseRequests, hasLength(1));
    expect(content.sessionRequests, hasLength(1));
    expect(materialRepository.lists, hasLength(1));
    expect(uploadRepository.lists, hasLength(1));
  }

  Future<void> beginPicker(WidgetTester tester) async {
    await tap(tester, 'Choose file', settle: false);
    expect(picker.opens, 1);
    expect(CourseImageSelection.active(auth), isTrue);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(auth.stage, AuthStage.ready);
    expect(find.byType(MaterialFileUploadPanel), findsOneWidget);
  }

  void noWrites() {
    expect(uploadRepository.uploads, isEmpty);
    expect(uploadRepository.checks, isEmpty);
    expect(materialRepository.writes, 0);
    expect(content.courseSaves, isEmpty);
    expect(content.sessionSaves, isEmpty);
    expect(content.courseVisibility, isEmpty);
    expect(content.sessionVisibility, isEmpty);
  }

  Future<void> refreshAccess(WidgetTester tester) async {
    await tester.runAsync(() => auth.checkAccess());
    await tester.pumpAndSettle();
  }

  for (final resultFirst in [false, true]) {
    for (final delayedAdmission in [false, true]) {
      testWidgets(
        '${resultFirst ? 'result then resume' : 'resume then result'} with ${delayedAdmission ? 'delayed' : 'immediate'} admission preserves real entrypoint after 20s',
        (tester) async {
          await enterUploads(tester);
          final adminState = tester.state(find.byType(AdminContentScreen));
          final materialsState = tester.state(find.byType(AdminMaterialsPanel));
          final panelState = tester.state(find.byType(MaterialFileUploadPanel));
          final access = auth.access;
          final calls = accounts.calls.where((call) => call == 'access').length;
          await beginPicker(tester);
          final document = _Document();
          final admission = delayedAdmission
              ? Completer<AccessContext>()
              : null;
          accounts.accessCompleter = admission;
          if (resultFirst) {
            picker.pending!.complete(document);
            await tester.pump();
            expect(document.lengthReads, 0);
            expect(CourseImageSelection.active(auth), isTrue);
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          } else {
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            picker.pending!.complete(document);
          }
          await tester.pump();
          if (admission != null) {
            expect(document.streamReads, 1);
            expect(find.text(document.name), findsNothing);
            expect(CourseImageSelection.active(auth), isFalse);
            await tester.pump(const Duration(seconds: 19));
            expect(auth.stage, AuthStage.ready);
            expect(find.byType(MaterialFileUploadPanel), findsOneWidget);
            admission.complete(accounts.accessContext);
          }
          await tester.pumpAndSettle();
          expect(document.lengthReads, 1);
          expect(document.streamReads, 1);
          expect(find.text(document.name), findsOneWidget);
          expect(find.text('194 bytes • text/plain'), findsOneWidget);
          expect(auth.access, same(access));
          expect(
            accounts.calls.where((call) => call == 'access'),
            hasLength(calls + 1),
          );
          expect(
            tester.state(find.byType(AdminContentScreen)),
            same(adminState),
          );
          expect(
            tester.state(find.byType(AdminMaterialsPanel)),
            same(materialsState),
          );
          expect(
            tester.state(find.byType(MaterialFileUploadPanel)),
            same(panelState),
          );

          await tap(tester, 'Upload selected file');
          final cancel = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
              .onPressed!;
          await tap(tester, 'Cancel');
          await tester.pump(const Duration(seconds: 21));
          // A delayed callback from the closed confirmation must be harmless.
          expect(cancel, returnsNormally);
          await tester.pumpAndSettle();
          expect(find.text(document.name), findsOneWidget);
          expect(
            tester.state(find.byType(MaterialFileUploadPanel)),
            same(panelState),
          );
          expect(content.courseRequests, hasLength(1));
          expect(content.sessionRequests, hasLength(1));
          expect(materialRepository.lists, hasLength(1));
          expect(uploadRepository.lists, hasLength(1));
          expect(auth.stage, AuthStage.ready);
          expect(tester.takeException(), isNull);
          noWrites();
        },
      );
    }
  }

  for (final resultFirst in [false, true]) {
    testWidgets(
      'native cancellation ${resultFirst ? 'before' : 'after'} resume stays on upload panel',
      (tester) async {
        await enterUploads(tester);
        final panelState = tester.state(find.byType(MaterialFileUploadPanel));
        final calls = accounts.calls.where((call) => call == 'access').length;
        await beginPicker(tester);
        if (resultFirst) {
          picker.pending!.complete(null);
          await tester.pump();
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        } else {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          picker.pending!.complete(null);
        }
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 21));
        expect(auth.stage, AuthStage.ready);
        expect(
          tester.state(find.byType(MaterialFileUploadPanel)),
          same(panelState),
        );
        expect(find.text('Selected — not uploaded'), findsNothing);
        expect(
          accounts.calls.where((call) => call == 'access'),
          hasLength(calls + 1),
        );
        expect(content.courseRequests, hasLength(1));
        expect(CourseImageSelection.active(auth), isFalse);
        noWrites();
      },
    );
  }

  for (final trigger in [
    'explicit access refresh',
    'additional resumed event',
  ]) {
    testWidgets(
      '$trigger after selection resets workspace through fail-closed admission',
      (tester) async {
        await enterUploads(tester);
        await beginPicker(tester);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        final document = _Document();
        picker.pending!.complete(document);
        await tester.pumpAndSettle();
        expect(find.text(document.name), findsOneWidget);
        final previousAccess = auth.access;
        final stages = <AuthStage>[];
        void changed() => stages.add(auth.stage);
        auth.addListener(changed);
        addTearDown(() => auth.removeListener(changed));
        if (trigger == 'explicit access refresh') {
          await refreshAccess(tester);
        } else {
          // Dispatch directly to the real observer: the binding deduplicates
          // repeated states, while an additional observer callback can be modeled.
          final observer = tester.state(
            find.byType(AuthPanel, skipOffstage: false),
          ) as WidgetsBindingObserver;
          await tester.runAsync(() async {
            observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
            await auth.settled;
          });
          await tester.pumpAndSettle();
        }
        expect(
          stages,
          containsAllInOrder([AuthStage.checking, AuthStage.ready]),
        );
        expect(auth.access!.role, previousAccess!.role);
        expect(auth.access!.deviceId, previousAccess.deviceId);
        expect(find.byType(AdminContentScreen), findsOneWidget);
        expect(find.byType(AdminMaterialsPanel), findsNothing);
        expect(find.byType(MaterialFileUploadPanel), findsNothing);
        expect(find.text(document.name), findsNothing);
        expect(find.text('Courses'), findsOneWidget);
        expect(content.courseRequests, hasLength(2));
        noWrites();
      },
    );
  }

  testWidgets(
    'late native result after access refresh cannot restore old upload route',
    (tester) async {
      await enterUploads(tester);
      await beginPicker(tester);
      await refreshAccess(tester);
      final document = _Document();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      picker.pending!.complete(document);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 21));
      expect(document.lengthReads, 0);
      expect(find.text(document.name), findsNothing);
      expect(find.byType(MaterialFileUploadPanel), findsNothing);
      expect(find.text('Courses'), findsOneWidget);
      expect(CourseImageSelection.active(auth), isFalse);
      expect(tester.takeException(), isNull);
      noWrites();
    },
  );

  testWidgets('late admission after its 20s timeout cannot restore selection', (
    tester,
  ) async {
    await enterUploads(tester);
    await beginPicker(tester);
    final admission = Completer<AccessContext>();
    accounts.accessCompleter = admission;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final document = _Document();
    picker.pending!.complete(document);
    await tester.pump();
    expect(document.streamReads, 1);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(auth.stage, AuthStage.blocked);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    admission.complete(accounts.accessContext);
    await tester.pumpAndSettle();
    expect(find.text(document.name), findsNothing);
    expect(find.byType(MaterialFileUploadPanel), findsNothing);
    expect(CourseImageSelection.active(auth), isFalse);
    accounts.accessCompleter = null;
    await refreshAccess(tester);
    expect(find.text('Courses'), findsOneWidget);
    await tap(tester, 'Sessions');
    await tap(tester, 'Materials');
    await tap(tester, 'Upload file');
    await tap(tester, 'Choose file', settle: false);
    expect(picker.opens, 2);
    picker.pending!.complete(_Document());
    await tester.pumpAndSettle();
    expect(find.text(document.name), findsOneWidget);
    expect(tester.takeException(), isNull);
    noWrites();
  });

  testWidgets(
    'background during delayed admission drops selection and returns through fresh course list',
    (tester) async {
      await enterUploads(tester);
      await beginPicker(tester);
      final admission = Completer<AccessContext>();
      accounts.accessCompleter = admission;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final document = _Document();
      picker.pending!.complete(document);
      await tester.pump();
      expect(CourseImageSelection.active(auth), isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      admission.complete(accounts.accessContext);
      await tester.pumpAndSettle();
      expect(find.text(document.name), findsNothing);
      expect(find.byType(MaterialFileUploadPanel), findsNothing);
      accounts.accessCompleter = null;
      await tester.runAsync(() async {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await auth.settled;
      });
      await tester.pumpAndSettle();
      expect(auth.stage, AuthStage.ready);
      expect(find.text('Courses'), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      expect(find.text(document.name), findsNothing);
      expect(tester.takeException(), isNull);
      noWrites();
    },
  );

  testWidgets(
    'late upload history after access refresh cannot restore private rows or route',
    (tester) async {
      await enterUploads(tester);
      final history = Completer<List<MaterialFileUpload>>();
      uploadRepository.onList = () => history.future;
      await tap(tester, 'Refresh uploads', settle: false);
      await refreshAccess(tester);
      history.complete([uploads.row(name: 'LATE_PRIVATE_NAME.txt')]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 21));
      expect(find.text('LATE_PRIVATE_NAME.txt'), findsNothing);
      expect(find.byType(MaterialFileUploadPanel), findsNothing);
      expect(find.text('Courses'), findsOneWidget);
      expect(tester.takeException(), isNull);
      noWrites();
    },
  );
}
