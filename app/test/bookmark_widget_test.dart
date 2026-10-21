import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/bookmarks/bookmark_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';
import 'catalog_lifecycle_test.dart' show LifecycleCatalogFake;
import 'catalog_screen_test.dart' show course, id, page;

class BookmarkFake implements BookmarkRepository {
  String? actor = id(999);
  @override
  String? get currentActorId => actor;
  CourseBookmark? state = CourseBookmark(
    courseId: id(1),
    saved: false,
    revision: 0,
  );
  CatalogPage<CatalogCourse> result = page([]);
  final intents = <SetCourseBookmarkRequest>[];
  final reads = <String>[];
  final pages = <({CatalogCursor? after, int limit})>[];
  Future<CourseBookmark?> Function()? onRead;
  Future<CourseBookmark> Function(SetCourseBookmarkRequest)? onSet;
  Future<CatalogPage<CatalogCourse>> Function()? onList;
  final cleanupActors = <String>[];
  Future<int> Function()? onClear;
  @override
  Future<int> clearUnavailableBookmarks({required String actorId}) async {
    cleanupActors.add(actorId);
    return onClear == null ? 0 : await onClear!();
  }

  @override
  Future<CourseBookmark?> getBookmark(String courseId) async {
    reads.add(courseId);
    return onRead == null ? state : await onRead!();
  }

  @override
  Future<CourseBookmark> setBookmark(SetCourseBookmarkRequest request) async {
    intents.add(request);
    if (onSet != null) return onSet!(request);
    state = CourseBookmark(
      courseId: request.courseId,
      saved: request.saved,
      revision: request.expectedRevision + 1,
    );
    return state!;
  }

  @override
  Future<CatalogPage<CatalogCourse>> listSavedCourses({
    CatalogCursor? after,
    int limit = 20,
  }) async {
    pages.add((after: after, limit: limit));
    return onList == null ? result : await onList!();
  }
}

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late LifecycleCatalogFake catalog;
  late BookmarkFake bookmarks;
  setUp(() async {
    account = FakeAuthRepository()..hasSession = true;
    auth = AuthController(account);
    await auth.start();
    catalog = LifecycleCatalogFake()
      ..result = page([course(1)])
      ..detail = course(1);
    bookmarks = BookmarkFake()..result = page([course(1)]);
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
  });
  Future<void> open(
    WidgetTester tester, {
    bool savedOnly = false,
    double width = 800,
    double scale = 1,
    bool settle = true,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> reveal(
    WidgetTester tester,
    String text, {
    double delta = 400,
  }) async {
    await tester.scrollUntilVisible(
      find.text(text),
      delta,
      maxScrolls: 60,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await reveal(tester, text);
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> detail(WidgetTester tester, {bool settle = true}) async {
    await reveal(tester, 'View course: Engineering 1');
    await tester.tap(find.text('View course: Engineering 1'));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  bool live(WidgetTester tester, String text) {
    SemanticsNode? node = tester.getSemantics(find.text(text));
    while (node != null) {
      if (node.getSemanticsData().flagsCollection.isLiveRegion) return true;
      node = node.parent;
    }
    return false;
  }

  testWidgets(
    'detail uses verified state, captures actor/revision and refetches after each explicit state',
    (tester) async {
      await open(tester);
      await detail(tester);
      expect(bookmarks.reads, [id(1)]);
      expect(find.text(bookmarkDisclaimer), findsOneWidget);
      await tap(tester, 'Save course for later');
      expect(bookmarks.intents.single.actorId, id(999));
      expect(bookmarks.intents.single.expectedRevision, 0);
      expect(bookmarks.intents.single.saved, isTrue);
      expect(bookmarks.reads, hasLength(2));
      expect(catalog.detailRequests, hasLength(2));
      expect(find.text('Remove from saved courses'), findsOneWidget);
      expect(live(tester, 'Course saved for later.'), isTrue);
      await tap(tester, 'Remove from saved courses');
      expect(bookmarks.intents.last.saved, isFalse);
      expect(bookmarks.intents.last.expectedRevision, 1);
      expect(bookmarks.reads, hasLength(3));
      expect(find.text('Save course for later'), findsOneWidget);
      await tap(tester, 'Back to catalog');
      expect(find.text('Engineering 1'), findsNothing);
      expect(find.text('Tap Search to update results.'), findsOneWidget);
    },
  );
  testWidgets(
    'duplicate taps during save emit one immutable intent and no optimistic saved state',
    (tester) async {
      final delayed = Completer<CourseBookmark>();
      bookmarks.onSet = (_) => delayed.future;
      await open(tester);
      await detail(tester);
      await tester.tap(find.text('Save course for later'));
      await tester.tap(find.text('Save course for later'));
      await tester.pump();
      expect(bookmarks.intents, hasLength(1));
      expect(bookmarks.reads, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save course for later'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Course saved for later.'), findsNothing);
      bookmarks.state = CourseBookmark(
        courseId: id(1),
        saved: true,
        revision: 1,
      );
      delayed.complete(bookmarks.state!);
      await tester.pumpAndSettle();
      expect(bookmarks.reads, hasLength(2));
      expect(find.text('Remove from saved courses'), findsOneWidget);
    },
  );
  for (final kind in [
    BookmarkFailureKind.timedOut,
    BookmarkFailureKind.stateConflict,
    BookmarkFailureKind.invalidResponse,
  ]) {
    testWidgets(
      '$kind requires explicit refresh, never retries mutation or guesses newer revision',
      (tester) async {
        bookmarks.onSet = (_) async => throw BookmarkFailure(kind);
        await open(tester);
        await detail(tester);
        await tap(tester, 'Save course for later');
        expect(bookmarks.intents, hasLength(1));
        expect(bookmarks.reads, hasLength(1));
        final message = kind == BookmarkFailureKind.stateConflict
            ? 'Saved-course state changed.'
            : 'may already have saved';
        expect(find.textContaining(message), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save course for later'),
              )
              .onPressed,
          isNull,
        );
        final delayed = Completer<CourseBookmark?>();
        bookmarks.onRead = () => delayed.future;
        await tester.tap(find.text('Retry course'));
        await tester.pump();
        expect(bookmarks.intents, hasLength(1));
        expect(find.text('Save course for later'), findsNothing);
        bookmarks.state = CourseBookmark(
          courseId: id(1),
          saved: true,
          revision: 4,
        );
        delayed.complete(bookmarks.state);
        await tester.pumpAndSettle();
        expect(find.text('Remove from saved courses'), findsOneWidget);
        expect(bookmarks.intents, hasLength(1));
        bookmarks.onRead = null;
        bookmarks.onSet = null;
        await tap(tester, 'Remove from saved courses');
        expect(bookmarks.intents.last.expectedRevision, 4);
      },
    );
  }
  for (final operation in ['list', 'state', 'save']) {
    for (final loss in ['background', 'signout', 'actor']) {
      testWidgets(
        'delayed $operation after $loss cannot restore data or send another mutation',
        (tester) async {
          final delayedList = Completer<CatalogPage<CatalogCourse>>();
          final delayedState = Completer<CourseBookmark?>();
          final delayedSave = Completer<CourseBookmark>();
          if (operation == 'list') bookmarks.onList = () => delayedList.future;
          if (operation == 'state') {
            bookmarks.onRead = () => delayedState.future;
          }
          if (operation == 'save') bookmarks.onSet = (_) => delayedSave.future;
          await open(
            tester,
            savedOnly: operation == 'list',
            settle: operation != 'list',
          );
          if (operation != 'list') {
            await detail(tester, settle: operation != 'state');
          }
          if (operation == 'save') {
            await tester.tap(find.text('Save course for later'));
            await tester.pump();
          }
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
          }
          if (operation == 'list') delayedList.complete(page([course(1)]));
          if (operation == 'state') {
            delayedState.complete(
              CourseBookmark(courseId: id(1), saved: false, revision: 0),
            );
          }
          if (operation == 'save') {
            delayedSave.complete(
              CourseBookmark(courseId: id(1), saved: true, revision: 1),
            );
          }
          await tester.pumpAndSettle();
          expect(find.textContaining('Catalog access closed'), findsOneWidget);
          expect(find.text('Engineering 1'), findsNothing);
          expect(find.text('Safe description 1'), findsNothing);
          expect(find.text('Course saved for later.'), findsNothing);
          expect(bookmarks.intents, hasLength(operation == 'save' ? 1 : 0));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'late save after Back or disposal does not restore old detail/card',
    (tester) async {
      final delayed = Completer<CourseBookmark>();
      bookmarks.onSet = (_) => delayed.future;
      await open(tester);
      await detail(tester);
      await tester.tap(find.text('Save course for later'));
      await tester.pump();
      await tester.tap(find.text('Back to catalog'));
      await tester.pumpAndSettle();
      expect(find.text('Engineering 1'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: Text('Closed')));
      delayed.complete(
        CourseBookmark(courseId: id(1), saved: true, revision: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Closed'), findsOneWidget);
      expect(bookmarks.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  for (final unavailable in ['state-null', 'save-denied']) {
    testWidgets('$unavailable clears saved metadata and cursor before Back', (
      tester,
    ) async {
      if (unavailable == 'state-null') bookmarks.state = null;
      await open(tester, savedOnly: true);
      await detail(tester);
      if (unavailable == 'save-denied') {
        bookmarks.onSet = (_) async =>
            throw const BookmarkFailure(BookmarkFailureKind.courseUnavailable);
        await tap(tester, 'Save course for later');
      }
      expect(find.textContaining('This course is unavailable'), findsOneWidget);
      expect(find.text('Safe description 1'), findsNothing);
      await tap(tester, 'Back to catalog');
      expect(find.text('Engineering 1'), findsNothing);
      expect(
        find.text('Refresh saved courses to update results.'),
        findsOneWidget,
      );
    });
  }
  testWidgets(
    'saved-only pagination uses 20/cursor and never calls public search/filter',
    (tester) async {
      bookmarks.result = page(
        List.generate(20, (i) => course(i + 1)),
        more: true,
      );
      await open(tester, savedOnly: true);
      expect(catalog.requests, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      bookmarks.result = page([course(21)]);
      await tap(tester, 'Load more courses');
      expect(bookmarks.pages.last.limit, 20);
      expect(bookmarks.pages.last.after!.id, id(20));
      expect(bookmarks.pages.last.after!.position, 20);
      expect(find.text('Engineering 21'), findsOneWidget);
      expect(find.text('Load more courses'), findsNothing);
    },
  );
  testWidgets('duplicate across saved pages rejected instead of duplicated', (
    tester,
  ) async {
    bookmarks.result = page(
      List.generate(20, (i) => course(i + 1)),
      more: true,
    );
    await open(tester, savedOnly: true);
    bookmarks.result = page([course(1, position: 21)]);
    await tap(tester, 'Load more courses');
    await tester.scrollUntilVisible(
      find.textContaining('could not be verified'),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(bookmarks.pages, hasLength(2));
  });
  testWidgets(
    'saved empty differs from load failure and retry uses no mutation',
    (tester) async {
      bookmarks.result = page([]);
      await open(tester, savedOnly: true);
      expect(find.textContaining('No available saved courses'), findsOneWidget);
      bookmarks.onList = () async => throw StateError('PRIVATE_CANARY');
      await tap(tester, 'Refresh saved courses');
      expect(find.textContaining('No available saved courses'), findsNothing);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(bookmarks.intents, isEmpty);
      bookmarks.onList = null;
      await tap(tester, 'Retry catalog');
      expect(find.textContaining('No available saved courses'), findsOneWidget);
    },
  );
  testWidgets('access denial on paging clears every saved card', (
    tester,
  ) async {
    bookmarks.result = page(
      List.generate(20, (i) => course(i + 1)),
      more: true,
    );
    await open(tester, savedOnly: true);
    bookmarks.onList = () async =>
        throw const BookmarkFailure(BookmarkFailureKind.accessRequired);
    await tap(tester, 'Load more courses');
    expect(find.textContaining('Catalog access closed'), findsOneWidget);
    expect(find.textContaining('Engineering'), findsNothing);
  });
  testWidgets(
    'Saved courses entry is injection gated and forwards same repositories',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        SummitApp(authController: auth, catalogRepository: catalog),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved courses'), findsNothing);
      await tester.pumpWidget(
        SummitApp(
          authController: auth,
          catalogRepository: catalog,
          bookmarkRepository: bookmarks,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Saved courses'));
      await tester.tap(find.text('Saved courses'));
      await tester.pumpAndSettle();
      final screen = tester.widget<CatalogScreen>(find.byType(CatalogScreen));
      expect(screen.savedOnly, isTrue);
      expect(screen.bookmarkRepository, same(bookmarks));
      expect(screen.repository, same(catalog));
      expect(find.text(bookmarkDisclaimer), findsOneWidget);
    },
  );
  for (final scale in [2.0, 3.0]) {
    testWidgets(
      'bookmark control and live status accessible at 320 text$scale',
      (tester) async {
        await open(tester, width: 320, scale: scale);
        await detail(tester);
        await reveal(tester, 'Save course for later');
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        expect(
          tester
              .getSemantics(find.text('Save course for later'))
              .getSemanticsData()
              .flagsCollection
              .isToggled
              .toBoolOrNull(),
          isFalse,
        );
        await tester.tap(find.text('Save course for later'));
        await tester.pumpAndSettle();
        await reveal(tester, 'Remove from saved courses');
        expect(
          tester
              .getSemantics(find.text('Remove from saved courses'))
              .getSemanticsData()
              .flagsCollection
              .isToggled
              .toBoolOrNull(),
          isTrue,
        );
        await reveal(tester, 'Course saved for later.', delta: -400);
        expect(live(tester, 'Course saved for later.'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
