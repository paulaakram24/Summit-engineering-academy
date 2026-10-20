import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';
import 'catalog_screen_test.dart' show CatalogFake, course, page;

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late CatalogFake repository;
  setUp(() async {
    account = FakeAuthRepository()..hasSession = true;
    auth = AuthController(account);
    await auth.start();
    repository = CatalogFake();
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogScreen(auth: auth, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'refresh retains a selected category removed from server options without a dropdown crash',
    (tester) async {
      await open(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engineering').last);
      await tester.pumpAndSettle();
      repository.filters = CatalogFilters(categories: [], levels: []);
      await tap(tester, 'Refresh catalog');
      expect(repository.requests.last.category, 'Engineering');
      expect(
        find.text('No courses match your search or filters.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tap(tester, 'Clear filters');
      expect(repository.requests.last.category, isNull);
      expect(find.text('No published courses yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'changing search after another page resets the cursor and removes every old card',
    (tester) async {
      repository.result = page(
        List.generate(20, (i) => course(i + 1)),
        more: true,
      );
      await open(tester);
      repository.result = page([course(21)]);
      await tester.scrollUntilVisible(
        find.text('Load more courses'),
        800,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, 'Load more courses');
      expect(repository.requests.last.after, isNotNull);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -800,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'new criteria');
      await tester.pump();
      repository.result = page([]);
      await tap(tester, 'Search');
      expect(repository.requests.last.after, isNull);
      expect(repository.requests.last.search, 'new criteria');
      expect(find.text('Engineering 21'), findsNothing);
      expect(
        find.text('No courses match your search or filters.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hardware Back leaves details first and only then returns to the signed-in app',
    (tester) async {
      repository.result = page([course(1)]);
      repository.detail = course(1);
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        SummitApp(authController: auth, catalogRepository: repository),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Browse courses');
      await tap(tester, 'View course: Engineering 1');
      expect(find.text('Session outline'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.text('Search courses'), findsOneWidget);
      expect(find.text('Session outline'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CatalogScreen), findsNothing);
      expect(auth.stage, AuthStage.ready);
    },
  );

  testWidgets(
    'confirmed unavailable course invalidates cached cards and requires a fresh catalog',
    (tester) async {
      repository.result = page([course(1)]);
      repository.detail = null;
      await open(tester);
      await tap(tester, 'View course: Engineering 1');
      expect(find.textContaining('This course is unavailable'), findsOneWidget);
      await tap(tester, 'Back to catalog');
      expect(find.text('Engineering 1'), findsNothing);
      expect(find.text('View course: Engineering 1'), findsNothing);
      expect(find.text('123.45 EGP'), findsNothing);
      expect(find.text('Tap Search to update results.'), findsOneWidget);
      repository.result = page([]);
      await tap(tester, 'Search');
      expect(repository.requests.last.after, isNull);
      expect(find.text('No published courses yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'dependency replacement closes permanently and cannot install an old delayed result',
    (tester) async {
      await open(tester);
      final old = Completer<CatalogPage<CatalogCourse>>();
      repository.pending = () => old.future;
      await tester.tap(find.text('Search'));
      await tester.pump();
      final replacement = CatalogFake()..result = page([course(2)]);
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogScreen(auth: auth, repository: replacement),
        ),
      );
      await tester.pump();
      old.complete(page([course(1)]));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(find.text('Engineering 1'), findsNothing);
      expect(find.text('Engineering 2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
