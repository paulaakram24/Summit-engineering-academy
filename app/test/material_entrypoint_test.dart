import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_content_screen.dart';
import 'package:summit_academy/content/admin_materials_panel.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/content/material_repository.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';
import 'content_admin_screen_test.dart' show FakeContentRepository;

const _courseId = '11111111-1111-4111-8111-111111111121';
const _sessionId = '11111111-1111-4111-8111-111111111122';
const _course = Course(
  id: _courseId,
  title: 'Engineering course',
  instructor: 'Instructor',
  category: 'Engineering',
  level: 'Year 1',
  pricePiasters: 10000,
);

class _Materials extends MaterialRepository {
  @override
  String? get currentActorId => '11111111-1111-4111-8111-111111111123';
  final sessions = <String>[];
  @override
  Future<List<MaterialDescriptor>> listMaterials(
    String sessionId, {
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    sessions.add(sessionId);
    return [];
  }

  @override
  Future<AdminMaterialDetail> getAdminDetail(MaterialDescriptor expected) =>
      throw UnimplementedError();
  @override
  Future<MaterialMutationResult> createMaterial(
    CreateMaterialRequest request,
  ) => throw UnimplementedError();
  @override
  Future<MaterialMutationResult> updateMaterial(
    UpdateMaterialRequest request,
  ) => throw UnimplementedError();
  @override
  Future<MaterialMutationResult> deleteMaterial(
    MaterialLifecycleRequest request,
  ) => throw UnimplementedError();
  @override
  Future<MaterialMutationResult> restoreMaterial(
    MaterialLifecycleRequest request,
  ) => throw UnimplementedError();
}

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late FakeContentRepository content;
  late _Materials materials;
  setUp(() async {
    account = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext(
        'admin',
        '11111111-1111-4111-8111-111111111111',
      );
    auth = AuthController(account);
    await auth.start();
    content = FakeContentRepository()
      ..courses = [_course]
      ..sessions = [
        const CourseSession(
          id: _sessionId,
          courseId: _courseId,
          sessionNumber: 1,
          title: 'Engineering session',
          pricePiasters: 1000,
        ),
      ];
    materials = _Materials();
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
  });

  Future<void> sessionList(WidgetTester tester, {bool inject = true}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminContentScreen(
          repository: content,
          authController: auth,
          materialRepository: inject ? materials : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'app forwards material repository through auth to selected session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        SummitApp(
          authController: auth,
          contentRepository: content,
          materialRepository: materials,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Manage courses'));
      await tester.tap(find.text('Manage courses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Materials'));
      await tester.pumpAndSettle();
      final panel = tester.widget<AdminMaterialsPanel>(
        find.byType(AdminMaterialsPanel),
      );
      expect(panel.repository, same(materials));
      expect(panel.course.id, _courseId);
      expect(panel.session.id, _sessionId);
      expect(materials.sessions, [_sessionId]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AdminMaterialsPanel), findsNothing);
      expect(find.text('Course administration'), findsOneWidget);
      expect(find.text('1. Engineering session'), findsOneWidget);
      await tester.tap(find.text('Materials'));
      await tester.pumpAndSettle();
      expect(materials.sessions, [_sessionId, _sessionId]);
      auth.lock('session_replaced');
      await tester.pumpAndSettle();
      expect(find.byType(AdminMaterialsPanel), findsNothing);
      expect(find.text('Administrator access is required.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing material dependency does not expose a broken entry point',
    (tester) async {
      await sessionList(tester, inject: false);
      expect(find.text('Materials'), findsNothing);
      expect(materials.sessions, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('student cannot reach injected material authoring', (
    tester,
  ) async {
    account.accessContext = FakeAuthRepository.context;
    await tester.runAsync(() => auth.checkAccess());
    await tester.pumpWidget(
      SummitApp(
        authController: auth,
        contentRepository: content,
        materialRepository: materials,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manage courses'), findsNothing);
    expect(find.byType(AdminMaterialsPanel), findsNothing);
    expect(materials.sessions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deleted session cannot open material editor', (tester) async {
    content.lifecycleFilter = true;
    content.sessions = [
      CourseSession(
        id: _sessionId,
        courseId: _courseId,
        sessionNumber: 1,
        title: 'Deleted session',
        pricePiasters: 1000,
        status: ContentStatus.archived,
        deletedAt: DateTime.utc(2026, 10, 19),
      ),
    ];
    await sessionList(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Materials'),
    );
    expect(button.onPressed, isNull);
    expect(materials.sessions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'closing materials refreshes session list without leaving admin workspace',
    (tester) async {
      await sessionList(tester);
      await tester.tap(find.text('Materials'));
      await tester.pumpAndSettle();
      final before = content.sessionRequests.length;
      tester
          .widget<AdminMaterialsPanel>(find.byType(AdminMaterialsPanel))
          .onClose();
      await tester.pumpAndSettle();
      expect(find.byType(AdminMaterialsPanel), findsNothing);
      expect(find.text('Engineering session'), findsNothing);
      expect(find.text('1. Engineering session'), findsOneWidget);
      expect(content.sessionRequests.length, before + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
