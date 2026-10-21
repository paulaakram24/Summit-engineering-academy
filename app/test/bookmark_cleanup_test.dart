import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/bookmarks/bookmark_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';

import 'auth_fakes.dart';
import 'bookmark_widget_test.dart' show BookmarkFake;
import 'catalog_lifecycle_test.dart' show LifecycleCatalogFake;
import 'catalog_screen_test.dart' show course, id, page;

const cleanupAction = 'Remove unavailable saved courses';
const cleanupConfirm = 'Remove';

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late LifecycleCatalogFake catalog;
  late BookmarkFake bookmarks;
  late GlobalKey<NavigatorState> navigator;
  setUp(() async {
    account = FakeAuthRepository()..hasSession = true;
    auth = AuthController(account);
    await auth.start();
    catalog = LifecycleCatalogFake()..result = page([course(1)]);
    bookmarks = BookmarkFake()..result = page([course(1)]);
    navigator = GlobalKey<NavigatorState>();
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
  });
  Future<void> open(
    WidgetTester tester, {
    bool savedOnly = true,
    double width = 800,
    double scale = 1,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(Size(width, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: CatalogScreen(
          auth: auth,
          repository: catalog,
          bookmarkRepository: bookmarks,
          savedOnly: savedOnly,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAction(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text(cleanupAction),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(cleanupAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cleanupAction));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, {bool settle = true}) async {
    await tester.ensureVisible(find.text(cleanupConfirm));
    await tester.tap(find.text(cleanupConfirm));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  bool disabled(WidgetTester tester) =>
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, cleanupAction))
          .onPressed ==
      null;
  bool live(WidgetTester tester, String text) {
    SemanticsNode? node = tester.getSemantics(find.text(text));
    while (node != null) {
      if (node.getSemanticsData().flagsCollection.isLiveRegion) return true;
      node = node.parent;
    }
    return false;
  }

  testWidgets(
    'cleanup is only offered in Saved courses, including an empty visible list',
    (tester) async {
      await open(tester, savedOnly: false);
      expect(find.text(cleanupAction), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      bookmarks.result = page([]);
      await open(tester);
      expect(find.text(cleanupAction), findsOneWidget);
      expect(disabled(tester), isFalse);
      expect(bookmarks.cleanupActors, isEmpty);
    },
  );
  testWidgets('cancel explains exact scope and issues zero cleanup requests', (
    tester,
  ) async {
    await open(tester);
    await tapAction(tester);
    expect(find.textContaining('Only your saved references'), findsOneWidget);
    expect(
      find.textContaining('Purchases and enrollments are unchanged'),
      findsOneWidget,
    );
    expect(find.textContaining('No hidden course details'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(bookmarks.cleanupActors, isEmpty);
    expect(bookmarks.pages, hasLength(1));
  });
  for (final count in [0, 3]) {
    testWidgets(
      'confirmed cleanup announces exact $count and refetches before controls return',
      (tester) async {
        bookmarks.onClear = () async => count;
        await open(tester);
        await tapAction(tester);
        final refreshed = Completer<CatalogPage<CatalogCourse>>();
        bookmarks.onList = () => refreshed.future;
        await confirm(tester, settle: false);
        expect(bookmarks.cleanupActors, [id(999)]);
        expect(bookmarks.pages, hasLength(2));
        expect(find.text('Engineering 1'), findsNothing);
        expect(disabled(tester), isTrue);
        refreshed.complete(page([course(2)]));
        await tester.pumpAndSettle();
        expect(find.text('Engineering 2'), findsOneWidget);
        expect(disabled(tester), isFalse);
        final message = 'Removed $count unavailable saved courses.';
        expect(find.text(message), findsOneWidget);
        expect(live(tester, message), isTrue);
        expect(bookmarks.intents, isEmpty);
      },
    );
  }
  testWidgets(
    'duplicate taps open one dialog and confirmed in-flight cleanup cannot repeat',
    (tester) async {
      await open(tester);
      final action = tester
          .widget<TextButton>(find.widgetWithText(TextButton, cleanupAction))
          .onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final delayed = Completer<int>();
      bookmarks.onClear = () => delayed.future;
      await confirm(tester, settle: false);
      expect(bookmarks.cleanupActors, hasLength(1));
      expect(disabled(tester), isTrue);
      await tester.tap(find.text(cleanupAction));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bookmarks.cleanupActors, hasLength(1));
      delayed.complete(1);
      await tester.pumpAndSettle();
      expect(find.text('Removed 1 unavailable saved course.'), findsOneWidget);
    },
  );
  for (final loss in ['background', 'signout', 'actor']) {
    testWidgets(
      '$loss invalidates confirmation before any cleanup transmission',
      (tester) async {
        await open(tester);
        await tapAction(tester);
        if (loss == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else if (loss == 'signout') {
          account.emit(SessionEvent.signedOut);
        } else {
          bookmarks.actor = id(998);
          // Even before a frame/auth notification, stale confirmation is gated.
          await tester.tap(find.text(cleanupConfirm));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(bookmarks.cleanupActors, isEmpty);
        expect(find.textContaining('Catalog access closed'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'dependency replacement closes the owned dialog without reusing captured actor',
    (tester) async {
      await open(tester);
      await tapAction(tester);
      final old = bookmarks;
      bookmarks = BookmarkFake();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: CatalogScreen(
            auth: auth,
            repository: catalog,
            bookmarkRepository: bookmarks,
            savedOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(old.cleanupActors, isEmpty);
      expect(bookmarks.cleanupActors, isEmpty);
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
    },
  );
  testWidgets(
    'disposing screen removes its own confirmation but preserves an unrelated route above it',
    (tester) async {
      final showScreen = ValueNotifier(true);
      addTearDown(showScreen.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: ValueListenableBuilder<bool>(
            valueListenable: showScreen,
            builder: (_, show, _) => show
                ? CatalogScreen(
                    auth: auth,
                    repository: catalog,
                    bookmarkRepository: bookmarks,
                    savedOnly: true,
                  )
                : const Scaffold(body: Text('Underlying screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapAction(tester);
      final other = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unrelated route')),
      );
      unawaited(navigator.currentState!.push(other));
      await tester.pumpAndSettle();
      showScreen.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(other.isCurrent, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Underlying screen'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(bookmarks.cleanupActors, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cleanup completing after background cannot announce success or refetch metadata',
    (tester) async {
      final delayed = Completer<int>();
      bookmarks.onClear = () => delayed.future;
      await open(tester);
      await tapAction(tester);
      await confirm(tester, settle: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      delayed.complete(8);
      await tester.pumpAndSettle();
      expect(find.textContaining('Removed 8'), findsNothing);
      expect(bookmarks.pages, hasLength(1));
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets(
    'late cleanup after screen disposal cannot update the replacement screen',
    (tester) async {
      final delayed = Completer<int>();
      bookmarks.onClear = () => delayed.future;
      await open(tester);
      await tapAction(tester);
      await confirm(tester, settle: false);
      await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      delayed.complete(5);
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.textContaining('Removed 5'), findsNothing);
      expect(bookmarks.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain cleanup clears stale cards and blocks writes through failed refresh until explicit success',
    (tester) async {
      bookmarks.onClear = () async =>
          throw const BookmarkFailure(BookmarkFailureKind.timedOut);
      await open(tester);
      await tapAction(tester);
      await confirm(tester);
      expect(find.text('Engineering 1'), findsNothing);
      expect(find.textContaining('may already have completed'), findsOneWidget);
      expect(find.textContaining('Removed '), findsNothing);
      expect(disabled(tester), isTrue);
      bookmarks.onList = () async => throw StateError('PRIVATE_CANARY');
      await tester.tap(find.text('Refresh saved courses'));
      await tester.pumpAndSettle();
      expect(disabled(tester), isTrue);
      expect(bookmarks.cleanupActors, hasLength(1));
      bookmarks.onList = null;
      await tester.tap(find.text('Refresh saved courses'));
      await tester.pumpAndSettle();
      expect(disabled(tester), isFalse);
      expect(bookmarks.cleanupActors, hasLength(1));
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(bookmarks.intents, isEmpty);
    },
  );
  testWidgets(
    'cleanup access denial closes all saved metadata without a zero-count success',
    (tester) async {
      bookmarks.onClear = () async =>
          throw const BookmarkFailure(BookmarkFailureKind.accessRequired);
      await open(tester);
      await tapAction(tester);
      await confirm(tester);
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(find.textContaining('Removed '), findsNothing);
      expect(find.text('Engineering 1'), findsNothing);
    },
  );
  testWidgets(
    'successful cleanup with failed list refresh retains acknowledged count but blocks new writes',
    (tester) async {
      bookmarks.onClear = () async => 4;
      await open(tester);
      await tapAction(tester);
      bookmarks.onList = () async =>
          throw const BookmarkFailure(BookmarkFailureKind.timedOut);
      await confirm(tester);
      expect(find.text('Removed 4 unavailable saved courses.'), findsOneWidget);
      expect(find.text('Engineering 1'), findsNothing);
      expect(disabled(tester), isTrue);
      expect(bookmarks.cleanupActors, hasLength(1));
    },
  );
  for (final scale in [2.0, 3.0]) {
    testWidgets('cleanup dialog and actions accessible at 320x640 text$scale', (
      tester,
    ) async {
      await open(tester, width: 320, scale: scale);
      await tapAction(tester);
      await tester.ensureVisible(find.text(cleanupConfirm));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Remove unavailable saved references'),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bookmarks.cleanupActors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
