import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_materials_panel.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/content/material_file_upload_panel.dart';
import 'package:summit_academy/content/material_file_upload_repository.dart';
import 'package:summit_academy/content/material_models.dart' show MaterialKind;

import 'admin_materials_panel_test.dart' as materials;
import 'auth_fakes.dart';
import 'material_file_upload_panel_test.dart' as uploads;
import 'material_models_test.dart' as fixtures;

// Models the service's callback-before-side-effect contract with no transport.
// Actual HTTP ordering is covered by the separate transport tests.
class _PhaseAwareUploads extends uploads.UploadPanelRepositoryFake {
  _PhaseAwareUploads(this.blockedPhase);

  final MaterialFileUploadPhase blockedPhase;
  final gate = Completer<void>();
  final started = <MaterialFileUploadPhase>[];
  MaterialFileUploadFailure? guardFailure;

  @override
  Future<MaterialFileUpload> upload(
    MaterialFileUploadRequest request, {
    void Function(MaterialFileUploadPhase)? onPhase,
  }) async {
    this.uploads.add(request);
    try {
      for (final phase in MaterialFileUploadPhase.values) {
        onPhase!(phase);
        started.add(phase);
        if (phase == blockedPhase) await gate.future;
      }
      return uploads.row(file: request.file, owner: request.material.id);
    } on MaterialFileUploadFailure catch (error) {
      guardFailure = error;
      rethrow;
    }
  }
}

class _DelayedCheckUploads extends uploads.UploadPanelRepositoryFake {
  final prepared = Completer<void>();
  int guardCalls = 0, preparations = 0, finalizations = 0;
  MaterialFileUploadFailure? guardFailure;

  @override
  Future<MaterialFileUpload> checkUpload(
    MaterialFileUploadRequest request, {
    void Function()? ensureActive,
  }) async {
    checks.add(request);
    void guard() {
      ++guardCalls;
      // Require the real panel to supply its lifecycle guard.
      ensureActive!();
    }

    try {
      guard();
      ++preparations;
      await prepared.future;
      guard();
      ++finalizations;
      final result = uploads.row(
        file: request.file,
        owner: request.material.id,
      );
      guard();
      rows = [result];
      return result;
    } on MaterialFileUploadFailure catch (error) {
      guardFailure = error;
      rethrow;
    }
  }
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late materials.PanelMaterials repository;
  late uploads.UploadPanelRepositoryFake uploadRepository;
  late uploads.FileSelectorFake selector;
  late Course course;
  late CourseSession session;
  late int closed;

  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', fixtures.actorId);
    auth = AuthController(accounts);
    await auth.start();
    repository = materials.PanelMaterials()..rows = [uploads.material()];
    uploadRepository = uploads.UploadPanelRepositoryFake();
    selector = uploads.FileSelectorFake();
    course = materials.parentCourse();
    session = materials.parentSession();
    closed = 0;
  });

  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });

  Widget workspace() => MaterialApp(
    home: Scaffold(
      body: AdminMaterialsPanel(
        course: course,
        session: session,
        auth: auth,
        repository: repository,
        uploadRepository: uploadRepository,
        fileSelector: selector,
        onClose: () => closed++,
      ),
    ),
  );

  Future<void> show(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(workspace());
    await tester.pumpAndSettle();
  }

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
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  VoidCallback cardCallback(WidgetTester tester) => tester
      .widget<TextButton>(find.widgetWithText(TextButton, 'Upload file'))
      .onPressed!;

  for (final blockedPhase in [
    MaterialFileUploadPhase.preparing,
    MaterialFileUploadPhase.transferring,
  ]) {
    testWidgets(
      'background while ${blockedPhase.name} awaits makes next phase guard throw before its side effect',
      (tester) async {
        final phased = _PhaseAwareUploads(blockedPhase);
        uploadRepository = phased;
        await show(tester);
        await tap(tester, 'Upload file');
        await tap(tester, 'Choose file');
        await tap(tester, 'Upload selected file');
        await tap(tester, 'Confirm upload', settle: false);

        final expected = MaterialFileUploadPhase.values
            .take(blockedPhase.index + 1)
            .toList();
        expect(phased.started, expected);
        expect(phased.uploads, hasLength(1));
        expect(phased.guardFailure, isNull);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        // Release before another frame: the guard must invalidate synchronously.
        phased.gate.complete();
        await tester.pumpAndSettle();

        expect(
          phased.guardFailure,
          isA<MaterialFileUploadFailure>().having(
            (error) => error.accessChanged,
            'accessChanged',
            isTrue,
          ),
        );
        expect(phased.started, expected);
        expect(phased.checks, isEmpty);
        expect(phased.lists, hasLength(1));
        expect(find.text(selector.result!.fileName), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(phased.started, expected);
        expect(phased.uploads, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final background in [true, false]) {
    testWidgets(
      'delayed Check upload preparation ${background ? 'blocks finalization after background' : 'finalizes while active'}',
      (tester) async {
        final delayed = _DelayedCheckUploads()
          ..onUpload = (_) async => throw const MaterialFileUploadFailure();
        uploadRepository = delayed;
        await show(tester);
        await tap(tester, 'Upload file');
        await tap(tester, 'Choose file');
        await tap(tester, 'Upload selected file');
        await tap(tester, 'Confirm upload');
        final originalRequest = delayed.uploads.single;
        expect(find.text('Check upload'), findsOneWidget);
        await tap(tester, 'Check upload', settle: false);

        expect(delayed.checks.single, same(originalRequest));
        expect(delayed.guardCalls, 1);
        expect(delayed.preparations, 1);
        expect(delayed.finalizations, 0);
        expect(delayed.guardFailure, isNull);
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        // Release before the next frame so invalidation must be synchronous.
        delayed.prepared.complete();
        await tester.pumpAndSettle();

        if (background) {
          expect(
            delayed.guardFailure,
            isA<MaterialFileUploadFailure>().having(
              (error) => error.accessChanged,
              'accessChanged',
              isTrue,
            ),
          );
          expect(delayed.guardCalls, 2);
          expect(delayed.finalizations, 0);
          expect(delayed.lists, hasLength(1));
          expect(find.text(selector.result!.fileName), findsNothing);
          expect(find.text('Check upload'), findsNothing);
          expect(find.textContaining('Uploaded —'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(delayed.finalizations, 0);
        } else {
          expect(delayed.guardFailure, isNull);
          expect(delayed.guardCalls, 3);
          expect(delayed.finalizations, 1);
          expect(delayed.lists, hasLength(2));
          expect(find.textContaining('Uploaded —'), findsWidgets);
          expect(find.text('Check upload'), findsNothing);
        }
        expect(delayed.preparations, 1);
        expect(delayed.checks, hasLength(1));
        expect(delayed.uploads, hasLength(1));
        expect(delayed.checks.single, same(originalRequest));
        expect(closed, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dependency in [
    'material repository',
    'upload repository',
    'course',
    'session',
    'selector',
  ]) {
    testWidgets('retained card callback rejects replaced $dependency', (
      tester,
    ) async {
      await show(tester);
      final retained = cardCallback(tester);
      final originalState = tester.state(find.byType(AdminMaterialsPanel));
      final originalUploads = uploadRepository;
      switch (dependency) {
        case 'material repository':
          repository = materials.PanelMaterials()..rows = [uploads.material()];
        case 'upload repository':
          uploadRepository = uploads.UploadPanelRepositoryFake();
        case 'course':
          course = materials.parentCourse();
        case 'session':
          session = materials.parentSession();
        case 'selector':
          selector = uploads.FileSelectorFake();
      }
      await tester.pumpWidget(workspace());
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(AdminMaterialsPanel)),
        same(originalState),
      );
      expect(cardCallback(tester), isNotNull);

      expect(retained, returnsNormally);
      await tester.pumpAndSettle();
      expect(find.byType(MaterialFileUploadPanel), findsNothing);
      expect(originalUploads.lists, isEmpty);
      expect(uploadRepository.lists, isEmpty);
      expect(selector.kinds, isEmpty);
      expect(closed, 0);
      expect(tester.takeException(), isNull);

      // A fresh callback must still open the current workspace successfully.
      await tap(tester, 'Upload file');
      expect(find.byType(MaterialFileUploadPanel), findsOneWidget);
      expect(uploadRepository.lists, hasLength(1));
      expect(
        uploadRepository.lists.single.material,
        same(repository.rows.single),
      );
    });
  }

  for (final uncertain in [false, true]) {
    testWidgets(
      'second material retained callback cannot replace active ${uncertain ? 'uncertain request' : 'selected file'}',
      (tester) async {
        final first = materials.descriptor(
          title: 'First file material',
          kind: MaterialKind.file,
          number: 1,
        );
        final second = materials.descriptor(
          title: 'Second file material',
          kind: MaterialKind.file,
          number: 2,
        );
        repository.rows = [first, second];
        if (uncertain) {
          uploadRepository.onUpload = (_) async =>
              throw const MaterialFileUploadFailure();
        }
        await show(tester);
        final cards = find.widgetWithText(TextButton, 'Upload file');
        expect(cards, findsNWidgets(2));
        final retainedSecond = tester
            .widget<TextButton>(cards.at(1))
            .onPressed!;
        await tester.ensureVisible(cards.first);
        await tester.tap(cards.first);
        await tester.pumpAndSettle();
        await tap(tester, 'Choose file');
        if (uncertain) {
          await tap(tester, 'Upload selected file');
          await tap(tester, 'Confirm upload');
          expect(find.text('Bound upload request (read-only)'), findsOneWidget);
        } else {
          expect(find.text('Selected — not uploaded'), findsOneWidget);
        }

        final activeState = tester.state(find.byType(MaterialFileUploadPanel));
        expect(retainedSecond, returnsNormally);
        expect(retainedSecond, returnsNormally);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MaterialFileUploadPanel>(
                find.byType(MaterialFileUploadPanel),
              )
              .material,
          same(first),
        );
        expect(
          tester.state(find.byType(MaterialFileUploadPanel)),
          same(activeState),
        );
        expect(find.text('Files: ${first.title}'), findsOneWidget);
        expect(find.text('Files: ${second.title}'), findsNothing);
        expect(find.text(selector.result!.fileName), findsOneWidget);
        expect(uploadRepository.lists, hasLength(1));
        expect(uploadRepository.lists.single.material, same(first));
        expect(selector.kinds, [MaterialKind.file]);
        expect(uploadRepository.uploads, hasLength(uncertain ? 1 : 0));
        expect(uploadRepository.checks, isEmpty);

        if (uncertain) {
          final originalRequest = uploadRepository.uploads.single;
          uploadRepository.onCheck = (request) async => uploads.row(
            owner: request.material.id,
            file: request.file,
            state: 'reserved',
          );
          await tap(tester, 'Check upload');
          expect(uploadRepository.checks.single, same(originalRequest));
          expect(originalRequest.material, same(first));
          expect(find.text('Bound upload request (read-only)'), findsOneWidget);
          expect(uploadRepository.uploads, hasLength(1));
        } else {
          expect(find.text('Selected — not uploaded'), findsOneWidget);
          expect(find.text('Upload selected file'), findsOneWidget);
        }

        // Retaining either state must also retain its explicit discard gate.
        await tap(tester, 'Close uploads');
        expect(find.text('Discard local selection?'), findsOneWidget);
        expect(closed, 0);
        await tap(tester, 'Cancel');
        expect(find.text(selector.result!.fileName), findsOneWidget);
        expect(find.text('Files: ${first.title}'), findsOneWidget);
        expect(uploadRepository.lists, hasLength(1));
        expect(closed, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retained card callback after disposal neither opens nor throws',
    (tester) async {
      await show(tester);
      final retained = cardCallback(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Text('Replacement screen')),
      );
      await tester.pumpAndSettle();
      expect(retained, returnsNormally);
      await tester.pumpAndSettle();
      expect(find.text('Replacement screen'), findsOneWidget);
      expect(find.byType(MaterialFileUploadPanel), findsNothing);
      expect(uploadRepository.lists, isEmpty);
      expect(selector.kinds, isEmpty);
      expect(closed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained card callback rejects a row removed by refresh', (
    tester,
  ) async {
    await show(tester);
    final retained = cardCallback(tester);
    repository.rows = [];
    await tap(tester, 'Refresh materials');
    expect(retained, returnsNormally);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialFileUploadPanel), findsNothing);
    expect(uploadRepository.lists, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outer Back respects child dirty discard confirmation', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Upload file');
    await tap(tester, 'Choose file');
    expect(find.text(selector.result!.fileName), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Discard local selection?'), findsOneWidget);
    expect(closed, 0);
    expect(uploadRepository.uploads, isEmpty);
    await tap(tester, 'Cancel');
    expect(find.byType(MaterialFileUploadPanel), findsOneWidget);
    expect(find.text(selector.result!.fileName), findsOneWidget);
    expect(closed, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, 'Discard and close');
    expect(find.byType(MaterialFileUploadPanel), findsNothing);
    expect(find.byType(AdminMaterialsPanel), findsOneWidget);
    expect(find.text('Upload file'), findsOneWidget);
    expect(closed, 0);
    expect(uploadRepository.uploads, isEmpty);
    expect(uploadRepository.checks, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
}
