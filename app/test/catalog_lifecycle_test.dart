import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';

import 'auth_fakes.dart';
import 'catalog_screen_test.dart' show CatalogFake, course, id, page;

class LifecycleCatalogFake extends CatalogFake {
  final detailRequests = <String>[];
  final sessionRequests =
      <({String courseId, CatalogCursor? after, int limit})>[];
  Future<CatalogCourse?> Function()? pendingDetail;
  Future<CatalogPage<CatalogSession>> Function()? pendingOutline;

  @override
  Future<CatalogCourse?> getCourse(String courseId) async {
    detailRequests.add(courseId);
    return pendingDetail == null ? detail : await pendingDetail!();
  }

  @override
  Future<CatalogPage<CatalogSession>> listSessions(
    String courseId, {
    CatalogCursor? after,
    int limit = 20,
  }) async {
    sessionRequests.add((courseId: courseId, after: after, limit: limit));
    return pendingOutline == null ? outline : await pendingOutline!();
  }
}

CatalogSession outlineSession(int number, {int? position}) => CatalogSession(
  id: id(100 + number),
  courseId: id(1),
  sessionNumber: number,
  title: 'Outline $number',
  description: 'Outline description $number',
  pricePiasters: 100,
  position: position ?? number,
  isFreePreview: false,
);

CatalogPage<CatalogSession> outlinePage(
  List<CatalogSession> items, {
  bool more = false,
}) => CatalogPage(
  items: items,
  hasMore: more,
  nextCursor: more ? items.last.cursor : null,
);

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late LifecycleCatalogFake repository;
  // Repository-owned fixture only: never reads a user's gallery or device.
  late Uint8List png;
  setUpAll(() {
    png = File('assets/sea-logo.png').readAsBytesSync();
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
  setUp(() async {
    account = FakeAuthRepository()..hasSession = true;
    auth = AuthController(account);
    await auth.start();
    repository = LifecycleCatalogFake()
      ..result = page([course(1)])
      ..detail = course(1)
      ..outline = outlinePage([outlineSession(1)]);
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> open(WidgetTester tester, {CatalogCoverLoader? cover}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogScreen(
          auth: auth,
          repository: repository,
          loadCover: cover,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> startDetail(WidgetTester tester) async {
    await tester.ensureVisible(find.text('View course: Engineering 1'));
    await tester.tap(find.text('View course: Engineering 1'));
    // Deliberately do not settle while an unresolved request animates progress.
    await tester.pump();
  }

  Future<void> loadMore(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Load more sessions'),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Load more sessions'));
    await tester.tap(find.text('Load more sessions'));
    await tester.pump();
  }

  testWidgets(
    'late course detail after Back cannot reopen detail or request outline',
    (tester) async {
      final delayed = Completer<CatalogCourse?>();
      repository.pendingDetail = () => delayed.future;
      await open(tester);
      await startDetail(tester);
      expect(repository.detailRequests, [id(1)]);
      await tester.tap(find.text('Back to catalog'));
      await tester.pumpAndSettle();
      delayed.complete(course(1));
      await tester.pumpAndSettle();
      expect(find.text('Search courses'), findsOneWidget);
      expect(find.text('Back to catalog'), findsNothing);
      expect(find.text('Safe description 1'), findsNothing);
      expect(repository.sessionRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final loss in ['background', 'signout']) {
    testWidgets('late outline after $loss cannot restore protected data', (
      tester,
    ) async {
      final delayed = Completer<CatalogPage<CatalogSession>>();
      repository.pendingOutline = () => delayed.future;
      await open(tester);
      await startDetail(tester);
      expect(repository.sessionRequests, hasLength(1));
      if (loss == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        account.hasSession = false;
        repository.actor = null;
        account.emit(SessionEvent.signedOut);
      }
      // Complete before the next frame to exercise synchronous invalidation.
      delayed.complete(outlinePage([outlineSession(99)]));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(find.text('Safe description 1'), findsNothing);
      expect(find.text('99. Outline 99'), findsNothing);
      expect(find.text('Session outline'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(repository.sessionRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'outline page20 forwards last cursor, rechecks parent and appends final page',
    (tester) async {
      repository.outline = outlinePage(
        List.generate(20, (i) => outlineSession(i + 1)),
        more: true,
      );
      await open(tester);
      await startDetail(tester);
      await tester.pumpAndSettle();
      expect(repository.sessionRequests.single.courseId, id(1));
      expect(repository.sessionRequests.single.limit, 20);
      expect(repository.sessionRequests.single.after, isNull);
      final delayed = Completer<CatalogPage<CatalogSession>>();
      repository.pendingOutline = () => delayed.future;
      await loadMore(tester);
      expect(repository.detailRequests, [id(1), id(1)]);
      final request = repository.sessionRequests.last;
      expect(request.courseId, id(1));
      expect(request.limit, 20);
      expect(request.after!.id, id(120));
      expect(request.after!.position, 20);
      // The loading indicator changes the viewport layout; bring the lazy
      // footer back into view before inspecting the disabled control.
      await tester.scrollUntilVisible(
        find.text('Load more sessions'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Load more sessions'),
            )
            .onPressed,
        isNull,
      );
      // A second tap on the disabled control must not issue another request.
      await tester.tap(find.text('Load more sessions'));
      await tester.pump();
      expect(repository.sessionRequests, hasLength(2));
      delayed.complete(outlinePage([outlineSession(21)]));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('21. Outline 21'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('21. Outline 21'), findsOneWidget);
      expect(find.text('Load more sessions'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('1. Outline 1'),
        -800,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1. Outline 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outline rejects a repeated ID moved forward across pages and refreshes on explicit retry',
    (tester) async {
      repository.outline = outlinePage(
        List.generate(20, (i) => outlineSession(i + 1)),
        more: true,
      );
      await open(tester);
      await startDetail(tester);
      await tester.pumpAndSettle();
      repository.outline = outlinePage([outlineSession(1, position: 21)]);
      await loadMore(tester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry course'),
        -800,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.text('Session outline'), findsNothing);
      expect(find.text('1. Outline 1'), findsNothing);
      expect(find.text('Load more sessions'), findsNothing);
      expect(repository.sessionRequests, hasLength(2));
      repository.outline = outlinePage([outlineSession(22)]);
      await tester.tap(find.text('Retry course'));
      await tester.pumpAndSettle();
      expect(repository.sessionRequests.last.after, isNull);
      expect(repository.detailRequests, hasLength(3));
      expect(find.text('22. Outline 22'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parent disappearing during outline pagination clears stale description and sessions',
    (tester) async {
      repository.outline = outlinePage(
        List.generate(20, (i) => outlineSession(i + 1)),
        more: true,
      );
      await open(tester);
      await startDetail(tester);
      await tester.pumpAndSettle();
      repository.detail = null;
      await loadMore(tester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('This course is unavailable'),
        -800,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('This course is unavailable'), findsOneWidget);
      expect(find.text('Safe description 1'), findsNothing);
      expect(find.text('Session outline'), findsNothing);
      expect(repository.sessionRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid repository PNG is decoded and displayed then removed on signout',
    (tester) async {
      repository.result = page([course(1, cover: '${id(1)}/${id(800)}.png')]);
      final requested = <String>[];
      await open(
        tester,
        cover: (item) async {
          requested.add(item.id);
          return png;
        },
      );
      await tester.runAsync(() async {
        await precacheImage(
          MemoryImage(png),
          tester.element(find.byType(CatalogScreen)),
        );
      });
      await tester.pumpAndSettle();
      expect(requested, [id(1)]);
      expect(find.image(MemoryImage(png)), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        'Engineering 1 course cover',
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      account.hasSession = false;
      repository.actor = null;
      account.emit(SessionEvent.signedOut);
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('Engineering 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('valid PNG completing after auth loss cannot install an image', (
    tester,
  ) async {
    repository.result = page([course(1, cover: '${id(1)}/${id(800)}.png')]);
    final delayed = Completer<Uint8List?>();
    await open(tester, cover: (_) => delayed.future);
    account.emit(SessionEvent.signedOut);
    delayed.complete(png);
    await tester.pumpAndSettle();
    expect(find.textContaining('Catalog access closed'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
