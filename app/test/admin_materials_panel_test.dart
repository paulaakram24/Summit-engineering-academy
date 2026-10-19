import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_materials_panel.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/content/material_repository.dart';

import 'auth_fakes.dart';
import 'material_models_test.dart' as fixtures;

Course parentCourse({bool deleted = false}) => Course(
  id: fixtures.otherId,
  title: 'Course',
  instructor: 'Teacher',
  category: 'Civil',
  level: 'Beginner',
  pricePiasters: 0,
  deletedAt: deleted ? DateTime.utc(2026) : null,
);
CourseSession parentSession({
  bool deleted = false,
  String courseId = fixtures.otherId,
}) => CourseSession(
  id: fixtures.sessionId,
  courseId: courseId,
  sessionNumber: 1,
  title: 'Session',
  pricePiasters: 0,
  deletedAt: deleted ? DateTime.utc(2026) : null,
);
MaterialDescriptor descriptor({
  String title = 'Assignment',
  MaterialKind kind = MaterialKind.assignment,
  int number = 1,
  int revision = 1,
  bool deleted = false,
}) => MaterialDescriptor.fromJson({
  ...fixtures.materialRow(kind: kind, revision: revision, deleted: deleted),
  'id': '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  'title': title,
});

class PanelMaterials implements MaterialRepository {
  @override
  String? currentActorId = fixtures.actorId;
  List<MaterialDescriptor> rows = [descriptor()];
  final lists = <(String, int, bool)>[];
  final details = <MaterialDescriptor>[];
  final creates = <CreateMaterialRequest>[];
  final updates = <UpdateMaterialRequest>[];
  final deletes = <MaterialLifecycleRequest>[];
  final restores = <MaterialLifecycleRequest>[];
  Completer<List<MaterialDescriptor>>? listPending;
  Completer<AdminMaterialDetail>? detailPending;
  Completer<MaterialMutationResult>? savePending;
  Object? listError, detailError, saveError;
  AdminMaterialDetail? detailOverride;
  String body = fixtures.privateBody;
  String? target = fixtures.privateTarget;
  VoidCallback? onMutation;
  int get writes =>
      creates.length + updates.length + deletes.length + restores.length;
  AdminMaterialDetail detailFor(MaterialDescriptor row) => AdminMaterialDetail(
    descriptor: row,
    payload: switch (row.kind) {
      MaterialKind.assignment => AssignmentMaterialPayload(body),
      MaterialKind.link => LinkMaterialPayload(target),
      _ => const EmptyMaterialPayload(),
    },
  );
  @override
  Future<List<MaterialDescriptor>> listMaterials(
    String sessionId, {
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    lists.add((sessionId, offset, includeDeleted));
    if (listError != null) throw listError!;
    if (listPending != null) return listPending!.future;
    return rows
        .where((row) => includeDeleted || !row.isDeleted)
        .skip(offset)
        .take(20)
        .toList();
  }

  @override
  Future<AdminMaterialDetail> getAdminDetail(
    MaterialDescriptor expected,
  ) async {
    details.add(expected);
    if (detailError != null) throw detailError!;
    if (detailPending != null) return detailPending!.future;
    return detailOverride ?? detailFor(expected);
  }

  Future<MaterialMutationResult> _save() async {
    if (saveError != null) throw saveError!;
    if (savePending != null) return savePending!.future;
    onMutation?.call();
    // Deliberately stale: the UI must ignore this snapshot and refetch.
    return MaterialMutationResult(descriptor(title: 'OBSOLETE SNAPSHOT'));
  }

  @override
  Future<MaterialMutationResult> createMaterial(CreateMaterialRequest request) {
    creates.add(request);
    return _save();
  }

  @override
  Future<MaterialMutationResult> updateMaterial(UpdateMaterialRequest request) {
    updates.add(request);
    return _save();
  }

  @override
  Future<MaterialMutationResult> deleteMaterial(
    MaterialLifecycleRequest request,
  ) {
    deletes.add(request);
    return _save();
  }

  @override
  Future<MaterialMutationResult> restoreMaterial(
    MaterialLifecycleRequest request,
  ) {
    restores.add(request);
    return _save();
  }
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late PanelMaterials repository;
  int closed = 0;
  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', fixtures.actorId);
    auth = AuthController(accounts);
    await auth.start();
    repository = PanelMaterials();
    closed = 0;
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    bool settle = true,
    Course? course,
    CourseSession? session,
    Size size = const Size(900, 1400),
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: Scaffold(
            body: AdminMaterialsPanel(
              course: course ?? parentCourse(),
              session: session ?? parentSession(),
              auth: auth,
              repository: repository,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder formField(String label) => find.widgetWithText(TextFormField, label);
  Finder input(String label) =>
      find.descendant(of: formField(label), matching: find.byType(TextField));
  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.ensureVisible(formField(label));
    await tester.enterText(formField(label), text);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> kind(WidgetTester tester, MaterialKind kind) async {
    final field = find.byType(DropdownButtonFormField<MaterialKind>);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(kind.name).last);
    await tester.pumpAndSettle();
  }

  Future<void> status(WidgetTester tester, ContentStatus value) async {
    final field = find.byType(DropdownButtonFormField<ContentStatus>);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value.name).last);
    await tester.pumpAndSettle();
  }

  bool buttonEnabled(WidgetTester tester, String text) =>
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byWidgetPredicate(
                    (w) => w is ButtonStyleButton,
                  ),
                )
                .first,
          )
          .onPressed !=
      null;

  testWidgets(
    'empty/loading/read failure use sanitized messages and explicit refresh',
    (tester) async {
      repository.listPending = Completer<List<MaterialDescriptor>>();
      await show(tester, settle: false);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(buttonEnabled(tester, 'New material'), isFalse);
      repository.listPending!.complete([]);
      repository.listPending = null;
      await tester.pumpAndSettle();
      expect(find.text('No materials on this page.'), findsOneWidget);
      repository.listError = StateError('PRIVATE response token');
      await tap(tester, 'Refresh materials');
      expect(find.textContaining('Unable to load materials'), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(buttonEnabled(tester, 'New material'), isFalse);
      repository.listError = null;
      await tap(tester, 'Refresh materials');
      expect(buttonEnabled(tester, 'New material'), isTrue);
    },
  );
  testWidgets('twenty-item pages and Include deleted reset offset', (
    tester,
  ) async {
    repository.rows = List.generate(
      25,
      (i) => descriptor(title: 'Item ${i + 1}', number: i + 1),
    );
    await show(tester);
    expect(find.text('Item 20'), findsOneWidget);
    expect(find.text('Item 21'), findsNothing);
    await tap(tester, 'Next');
    expect(find.text('Item 21'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    await tap(tester, 'Previous');
    expect(find.text('Page 1'), findsOneWidget);
    await tap(tester, 'Next');
    await tap(tester, 'Include deleted');
    expect(repository.lists, [
      (fixtures.sessionId, 0, false),
      (fixtures.sessionId, 20, false),
      (fixtures.sessionId, 0, false),
      (fixtures.sessionId, 20, false),
      (fixtures.sessionId, 0, true),
    ]);
  });
  testWidgets(
    'create draft captures actor and ignores cached mutation snapshot',
    (tester) async {
      await show(tester);
      await tap(tester, 'New material');
      await enter(tester, 'Title', 'Video lesson');
      await enter(tester, 'Summary', 'Description');
      await enter(tester, 'Position', '3');
      expect(find.textContaining('Media placeholder only'), findsOneWidget);
      repository.onMutation = () => repository.rows = [
        descriptor(title: 'Fresh server row', kind: MaterialKind.video),
      ];
      await tap(tester, 'Save material');
      final request = repository.creates.single;
      expect(request.actorId, fixtures.actorId);
      expect(isMaterialUuid(request.operationId), isTrue);
      expect(request.sessionId, fixtures.sessionId);
      expect(request.draft.kind, MaterialKind.video);
      expect(request.draft.status, ContentStatus.draft);
      expect(request.draft.position, 3);
      expect(repository.lists, hasLength(2));
      expect(find.text('Fresh server row'), findsOneWidget);
      expect(find.text('OBSOLETE SNAPSHOT'), findsNothing);
    },
  );
  testWidgets(
    'kind switching clears incompatible private payload and draft validation blocks sends',
    (tester) async {
      await show(tester);
      await tap(tester, 'New material');
      await tap(tester, 'Save material');
      expect(repository.writes, 0);
      await enter(tester, 'Title', 'Assignment');
      await kind(tester, MaterialKind.assignment);
      await enter(tester, 'Assignment body (private)', fixtures.privateBody);
      await kind(tester, MaterialKind.link);
      await enter(tester, 'HTTPS target (private, optional)', 'http://invalid');
      await tap(tester, 'Save material');
      expect(repository.writes, 0);
      await enter(
        tester,
        'HTTPS target (private, optional)',
        fixtures.privateTarget,
      );
      await kind(tester, MaterialKind.assignment);
      expect(
        tester
            .widget<TextField>(input('Assignment body (private)'))
            .controller!
            .text,
        '',
      );
      await kind(tester, MaterialKind.link);
      expect(
        tester
            .widget<TextField>(input('HTTPS target (private, optional)'))
            .controller!
            .text,
        '',
      );
      await kind(tester, MaterialKind.pdf);
      await kind(tester, MaterialKind.file);
      await enter(tester, 'Position', '-1');
      await tap(tester, 'Save material');
      expect(repository.writes, 0);
      await enter(tester, 'Position', '0');
      await enter(tester, 'Title', 'https://unsafe-catalog.invalid');
      await tap(tester, 'Save material');
      expect(repository.writes, 0);
      await enter(tester, 'Title', 'Valid');
      await tap(tester, 'Save material');
      expect(
        repository.creates.single.draft.payload,
        isA<EmptyMaterialPayload>(),
      );
    },
  );
  testWidgets('edit waits for protected detail; kind remains immutable', (
    tester,
  ) async {
    repository.detailPending = Completer<AdminMaterialDetail>();
    await show(tester);
    await tester.tap(find.text('Edit material'));
    await tester.pump();
    expect(find.text('Save material'), findsNothing);
    expect(find.text(fixtures.privateBody), findsNothing);
    repository.detailPending!.complete(
      repository.detailFor(repository.rows.single),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kind: assignment (immutable)'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<MaterialKind>), findsNothing);
    expect(
      tester
          .widget<TextField>(input('Assignment body (private)'))
          .controller!
          .text,
      fixtures.privateBody,
    );
  });
  for (final malformed in ['session', 'payload', 'kind', 'deleted']) {
    testWidgets('untrusted $malformed detail never exposes Save', (
      tester,
    ) async {
      final row = repository.rows.single;
      final wrong = MaterialDescriptor.fromJson({
        ...fixtures.materialRow(),
        'id': row.id,
        if (malformed == 'session') 'session_id': fixtures.otherId,
        if (malformed == 'kind') 'kind': 'link',
        if (malformed == 'deleted') ...{
          'deleted_at': '2026-10-19T04:00:00Z',
          'status': 'archived',
        },
      });
      repository.detailOverride = AdminMaterialDetail(
        descriptor: wrong,
        payload: malformed == 'payload'
            ? const LinkMaterialPayload(fixtures.privateTarget)
            : wrong.kind == MaterialKind.link
            ? const LinkMaterialPayload(fixtures.privateTarget)
            : const AssignmentMaterialPayload(fixtures.privateBody),
      );
      await show(tester);
      await tap(tester, 'Edit material');
      expect(find.text('Save material'), findsNothing);
      expect(find.textContaining('PROTECTED'), findsNothing);
      expect(repository.writes, 0);
      expect(buttonEnabled(tester, 'New material'), isFalse);
    });
  }
  for (final materialKind in [MaterialKind.assignment, MaterialKind.link]) {
    testWidgets(
      '${materialKind.name} publishing requires configuration and stays authoring state',
      (tester) async {
        repository.rows = [descriptor(kind: materialKind)];
        repository.body = '';
        repository.target = null;
        await show(tester);
        await tap(tester, 'Edit material');
        final published = tester.widget<DropdownButton<ContentStatus>>(
          find.byType(DropdownButton<ContentStatus>),
        );
        expect(
          published.items!
              .singleWhere((item) => item.value == ContentStatus.published)
              .enabled,
          isFalse,
        );
        if (materialKind == MaterialKind.assignment) {
          await enter(
            tester,
            'Assignment body (private)',
            fixtures.privateBody,
          );
        } else {
          await enter(
            tester,
            'HTTPS target (private, optional)',
            fixtures.privateTarget,
          );
        }
        expect(
          tester
              .widget<DropdownButton<ContentStatus>>(
                find.byType(DropdownButton<ContentStatus>),
              )
              .items!
              .singleWhere((item) => item.value == ContentStatus.published)
              .enabled,
          isTrue,
        );
        await status(tester, ContentStatus.published);
        await tap(tester, 'Save material');
        expect(repository.updates.single.draft.status, ContentStatus.published);
        expect(repository.updates.single.actorId, fixtures.actorId);
        expect(
          repository.updates.single.expected.id,
          repository.rows.single.id,
        );
        expect(repository.lists, hasLength(2));
      },
    );
  }
  testWidgets(
    'delete cancellation has no write and restore confirms draft then refetches',
    (tester) async {
      await show(tester);
      await tap(tester, 'Delete material');
      await tap(tester, 'Cancel');
      expect(repository.writes, 0);
      await tap(tester, 'Delete material');
      repository.onMutation = () =>
          repository.rows = [descriptor(deleted: true, revision: 2)];
      await tap(tester, 'Confirm delete');
      expect(repository.deletes, hasLength(1));
      await tap(tester, 'Include deleted');
      await tap(tester, 'Restore material');
      expect(
        find.textContaining('Restore this material to draft'),
        findsOneWidget,
      );
      repository.onMutation = () => repository.rows = [descriptor(revision: 3)];
      await tap(tester, 'Confirm restore');
      expect(repository.restores.single.expected.revision, 2);
      expect(repository.restores.single.actorId, fixtures.actorId);
      expect(repository.lists, hasLength(4));
      expect(find.textContaining('assignment • draft'), findsOneWidget);
    },
  );
  testWidgets(
    'pending save rejects duplicate taps and fresh read gates controls',
    (tester) async {
      await show(tester);
      await tap(tester, 'New material');
      await enter(tester, 'Title', 'New');
      repository.savePending = Completer<MaterialMutationResult>();
      await tester.ensureVisible(find.text('Save material'));
      await tester.tap(find.text('Save material'));
      await tester.pump();
      await tester.tap(find.text('Save material'));
      await tester.pump();
      expect(repository.creates, hasLength(1));
      repository.listPending = Completer<List<MaterialDescriptor>>();
      repository.savePending!.complete(
        MaterialMutationResult(descriptor(title: 'OBSOLETE SNAPSHOT')),
      );
      await tester.pump();
      expect(find.text('OBSOLETE SNAPSHOT'), findsNothing);
      expect(buttonEnabled(tester, 'New material'), isFalse);
      repository.listPending!.complete([descriptor(title: 'Fresh')]);
      await tester.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
      expect(buttonEnabled(tester, 'New material'), isTrue);
    },
  );
  testWidgets(
    'uncertain outcome clears form and requires explicit refetch before new intent',
    (tester) async {
      await show(tester);
      await tap(tester, 'Edit material');
      repository.saveError = const MaterialFailure(
        MaterialFailureKind.uncertain,
        requiresRefresh: true,
      );
      await tap(tester, 'Save material');
      expect(find.textContaining('may already have saved'), findsOneWidget);
      expect(find.text('Save material'), findsNothing);
      expect(buttonEnabled(tester, 'New material'), isFalse);
      expect(repository.lists, hasLength(1));
      expect(repository.writes, 1);
      repository.saveError = null;
      repository.rows = [descriptor(title: 'Server saved', revision: 2)];
      await tap(tester, 'Refresh materials');
      expect(find.text('Server saved'), findsOneWidget);
      expect(repository.writes, 1);
      expect(buttonEnabled(tester, 'New material'), isTrue);
    },
  );
  for (final materialKind in [MaterialKind.assignment, MaterialKind.link]) {
    testWidgets(
      'conflicted ${materialKind.name} preserves selectable read-only edits without autosubmit',
      (tester) async {
        repository.rows = [descriptor(kind: materialKind)];
        await show(tester);
        await tap(tester, 'Edit material');
        final label = materialKind == MaterialKind.assignment
            ? 'Assignment body (private)'
            : 'HTTPS target (private, optional)';
        final text = materialKind == MaterialKind.assignment
            ? 'MY PRIVATE EDITS'
            : 'https://example.invalid/my-edits';
        await enter(tester, label, text);
        repository.saveError = const MaterialFailure(
          MaterialFailureKind.conflict,
          requiresRefresh: true,
        );
        await tap(tester, 'Save material');
        final field = tester.widget<TextField>(input(label));
        expect(field.enabled, isTrue);
        expect(field.readOnly, isTrue);
        expect(field.enableInteractiveSelection, isTrue);
        expect(field.controller!.text, text);
        expect(buttonEnabled(tester, 'Save material'), isFalse);
        expect(repository.writes, 1);
        expect(repository.lists, hasLength(1));
        await tap(tester, 'Refresh materials');
        expect(find.text('Discard unsaved changes?'), findsOneWidget);
        await tap(tester, 'Cancel');
        expect(field.controller!.text, text);
        expect(repository.writes, 1);
        repository.rows = [
          descriptor(
            title: 'Reconciled server state',
            kind: materialKind,
            revision: 2,
          ),
        ];
        await tap(tester, 'Refresh materials');
        await tap(tester, 'Discard changes');
        expect(find.text('Reconciled server state'), findsOneWidget);
        expect(repository.writes, 1);
        expect(find.byType(TextFormField), findsNothing);
      },
    );
  }
  for (final loss in ['revocation', 'actor switch']) {
    for (final operation in ['load', 'detail', 'save']) {
      testWidgets('late $operation after $loss cannot restore protected data', (
        tester,
      ) async {
        final row = repository.rows.single;
        if (operation == 'load') {
          repository.listPending = Completer<List<MaterialDescriptor>>();
          await show(tester, settle: false);
        } else {
          await show(tester);
          if (operation == 'detail') {
            repository.detailPending = Completer<AdminMaterialDetail>();
            await tester.tap(find.text('Edit material'));
          } else {
            await tap(tester, 'Edit material');
            repository.savePending = Completer<MaterialMutationResult>();
            await tester.ensureVisible(find.text('Save material'));
            await tester.tap(find.text('Save material'));
          }
        }
        await tester.pump();
        if (loss == 'revocation') {
          auth.lock('device_revoked');
        } else {
          repository.currentActorId = fixtures.otherId;
        }
        if (operation == 'load') repository.listPending!.complete([row]);
        if (operation == 'detail') {
          repository.detailPending!.complete(repository.detailFor(row));
        }
        if (operation == 'save') {
          repository.savePending!.complete(MaterialMutationResult(row));
        }
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text(row.title), findsNothing);
        expect(find.textContaining('PROTECTED'), findsNothing);
        expect(repository.lists, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'actor switch during private detail invalidates at return boundary',
    (tester) async {
      final row = repository.rows.single;
      repository.detailPending = Completer<AdminMaterialDetail>();
      await show(tester);
      await tester.tap(find.text('Edit material'));
      await tester.pump();
      repository.currentActorId = fixtures.otherId;
      repository.detailPending!.complete(repository.detailFor(row));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Administrator access changed'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(repository.writes, 0);
    },
  );
  testWidgets(
    'rapid access close and reopen before frame clears editor permanently',
    (tester) async {
      await show(tester);
      await tap(tester, 'Edit material');
      final controller = tester
          .widget<TextField>(input('Assignment body (private)'))
          .controller!;
      auth.suspend();
      expect(controller.text, '');
      await tester.runAsync(auth.checkAccess);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('PROTECTED'), findsNothing);
      expect(repository.lists, hasLength(1));
    },
  );
  testWidgets(
    'background dismisses confirmation and prevents mutation after resume',
    (tester) async {
      await show(tester);
      await tap(tester, 'Delete material');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.writes, 0);
      expect(
        find.textContaining('Administrator access changed'),
        findsOneWidget,
      );
    },
  );
  testWidgets('actor change while confirming cannot create an intent', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Delete material');
    repository.currentActorId = fixtures.otherId;
    await tap(tester, 'Confirm delete');
    expect(repository.writes, 0);
    expect(find.textContaining('Administrator access changed'), findsOneWidget);
  });
  for (final deletedCourse in [false, true]) {
    testWidgets(
      'deleted ${deletedCourse ? 'course' : 'session'} allows list but disables authoring',
      (tester) async {
        await show(
          tester,
          course: parentCourse(deleted: deletedCourse),
          session: parentSession(deleted: !deletedCourse),
        );
        expect(find.text('Assignment'), findsOneWidget);
        expect(repository.lists, hasLength(1));
        expect(buttonEnabled(tester, 'New material'), isFalse);
        expect(buttonEnabled(tester, 'Edit material'), isFalse);
        expect(buttonEnabled(tester, 'Delete material'), isFalse);
      },
    );
  }
  testWidgets('mismatched session and missing actor do not load data', (
    tester,
  ) async {
    await show(tester, session: parentSession(courseId: fixtures.actorId));
    expect(repository.lists, isEmpty);
    expect(find.textContaining('does not match'), findsOneWidget);
    repository.currentActorId = null;
    await show(tester);
    expect(repository.lists, isEmpty);
    expect(find.textContaining('Administrator access changed'), findsOneWidget);
  });
  testWidgets(
    'unsaved Back and Close warn; cancel retains form and discard closes',
    (tester) async {
      await show(tester);
      await tap(tester, 'Edit material');
      await enter(tester, 'Title', 'Unsaved');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(closed, 0);
      await tap(tester, 'Close materials');
      await tap(tester, 'Discard changes');
      expect(closed, 1);
      expect(repository.writes, 0);
    },
  );
  testWidgets(
    'narrow large-font keyboard layout keeps Save and Cancel reachable',
    (tester) async {
      await show(tester, size: const Size(320, 640), scale: 1.7, keyboard: 260);
      await tap(tester, 'New material');
      await kind(tester, MaterialKind.link);
      await enter(tester, 'Title', 'Link');
      await enter(
        tester,
        'HTTPS target (private, optional)',
        fixtures.privateTarget,
      );
      await tester.ensureVisible(find.text('Save material'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tap(tester, 'Cancel edit');
      await tap(tester, 'Discard changes');
      expect(repository.writes, 0);
    },
  );
  testWidgets('late detail after disposal cannot touch disposed controllers', (
    tester,
  ) async {
    repository.detailPending = Completer<AdminMaterialDetail>();
    final row = repository.rows.single;
    await show(tester);
    await tester.tap(find.text('Edit material'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repository.detailPending!.complete(repository.detailFor(row));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.writes, 0);
  });
  testWidgets(
    'successful acknowledgement followed by failed refetch cannot enable stale controls',
    (tester) async {
      await show(tester);
      await tap(tester, 'Delete material');
      repository.onMutation = () =>
          repository.listError = StateError('PRIVATE refetch error');
      await tap(tester, 'Confirm delete');
      expect(repository.writes, 1);
      expect(repository.lists, hasLength(2));
      expect(find.text('OBSOLETE SNAPSHOT'), findsNothing);
      expect(buttonEnabled(tester, 'New material'), isFalse);
      repository.listError = null;
      repository.rows = [];
      await tap(tester, 'Refresh materials');
      expect(buttonEnabled(tester, 'New material'), isTrue);
      expect(repository.writes, 1);
    },
  );
  testWidgets('revocation cancels active delete dialog without writing', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Delete material');
    auth.lock('device_revoked');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changed device identity discards pending private detail', (
    tester,
  ) async {
    repository.detailPending = Completer<AdminMaterialDetail>();
    final row = repository.rows.single;
    await show(tester);
    await tester.tap(find.text('Edit material'));
    await tester.pump();
    auth.access = const AccessContext('admin', fixtures.otherId);
    repository.detailPending!.complete(repository.detailFor(row));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Administrator access changed'), findsOneWidget);
  });
  for (final materialKind in [MaterialKind.assignment, MaterialKind.link]) {
    testWidgets(
      'closed access clears preserved ${materialKind.name} conflict text before a frame',
      (tester) async {
        repository.rows = [descriptor(kind: materialKind)];
        await show(tester);
        await tap(tester, 'Edit material');
        final label = materialKind == MaterialKind.assignment
            ? 'Assignment body (private)'
            : 'HTTPS target (private, optional)';
        await enter(
          tester,
          label,
          materialKind == MaterialKind.assignment
              ? 'PRIVATE EDIT'
              : fixtures.privateTarget,
        );
        repository.saveError = const MaterialFailure(
          MaterialFailureKind.conflict,
          requiresRefresh: true,
        );
        await tap(tester, 'Save material');
        final controller = tester.widget<TextField>(input(label)).controller!;
        expect(controller.text, isNotEmpty);
        auth.suspend();
        expect(controller.text, '');
        await tester.runAsync(auth.checkAccess);
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(repository.writes, 1);
      },
    );
  }
  testWidgets(
    'disposing with an open confirmation removes only its dialog safely',
    (tester) async {
      await show(tester);
      await tap(tester, 'Delete material');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
