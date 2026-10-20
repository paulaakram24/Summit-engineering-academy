import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';

String id(int i) => '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}';
CatalogCourse course(int i, {int? position, String? cover}) => CatalogCourse(
  id: id(i),
  title: 'Engineering $i',
  description: 'Safe description $i',
  instructor: 'Instructor',
  category: 'Engineering',
  level: 'Year 1',
  pricePiasters: 12345,
  position: position ?? i,
  coverPath: cover,
);
CatalogPage<CatalogCourse> page(
  List<CatalogCourse> items, {
  bool more = false,
}) => CatalogPage(
  items: items,
  hasMore: more,
  nextCursor: more ? items.last.cursor : null,
);

class CatalogFake extends CatalogRepository {
  String? actor = id(999);
  @override
  String? get currentActorId => actor;
  final requests =
      <
        ({
          String? search,
          String? category,
          String? level,
          CatalogCursor? after,
        })
      >[];
  Future<CatalogPage<CatalogCourse>> Function()? pending;
  CatalogPage<CatalogCourse> result = page([]);
  CatalogCourse? detail;
  Object? filtersError;
  CatalogFilters filters = CatalogFilters(
    categories: ['Engineering'],
    levels: ['Year 1'],
  );
  CatalogPage<CatalogSession> outline = CatalogPage(
    items: [],
    hasMore: false,
    nextCursor: null,
  );
  @override
  Future<CatalogPage<CatalogCourse>> listCourses({
    String? search = '',
    String? category,
    String? level,
    CatalogCursor? after,
    int limit = 20,
  }) async {
    requests.add((
      search: search,
      category: category,
      level: level,
      after: after,
    ));
    return pending == null ? result : pending!();
  }

  @override
  Future<CatalogFilters> getFilters() async {
    if (filtersError != null) throw filtersError!;
    return filters;
  }

  @override
  Future<CatalogCourse?> getCourse(String courseId) async => detail;
  @override
  Future<CatalogPage<CatalogSession>> listSessions(
    String courseId, {
    CatalogCursor? after,
    int limit = 20,
  }) async => outline;
}

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
  Future<void> open(WidgetTester tester, {CatalogCoverLoader? cover}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
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

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('empty catalog is honest; no purchase or admin controls', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('No published courses yet.'), findsOneWidget);
    expect(find.text('Buy'), findsNothing);
    expect(find.text('New course'), findsNothing);
    expect(repository.requests.single.search, '');
  });
  testWidgets('server search and clear reset cursor and no-match state', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Later page needle');
    await tester.pump();
    expect(find.text('No published courses yet.'), findsNothing);
    await tap(tester, 'Search');
    expect(repository.requests.last.search, 'Later page needle');
    expect(repository.requests.last.after, isNull);
    expect(
      find.text('No courses match your search or filters.'),
      findsOneWidget,
    );
    await tap(tester, 'Clear filters');
    expect(repository.requests.last.search, '');
    expect(find.text('No published courses yet.'), findsOneWidget);
  });
  testWidgets('category and level are sent to server before pagination', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Engineering').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year 1').last);
    await tester.pumpAndSettle();
    expect(repository.requests.last.category, 'Engineering');
    expect(repository.requests.last.level, 'Year 1');
    expect(repository.requests.last.after, isNull);
  });
  testWidgets('edited search invalidates an older delayed page', (
    tester,
  ) async {
    await open(tester);
    final old = Completer<CatalogPage<CatalogCourse>>();
    repository.pending = () => old.future;
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new query');
    await tester.pump();
    repository.pending = null;
    repository.result = page([course(2)]);
    await tap(tester, 'Search');
    old.complete(page([course(1)]));
    await tester.pumpAndSettle();
    expect(find.text('Engineering 1'), findsNothing);
    expect(find.text('Engineering 2'), findsOneWidget);
  });
  testWidgets('append keyset page uses last returned cursor', (tester) async {
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
    expect(repository.requests.last.after!.id, id(20));
    expect(find.text('Load more courses'), findsNothing);
    expect(find.text('Engineering 21'), findsOneWidget);
  });
  testWidgets('cross-page duplicate is rejected instead of appended', (
    tester,
  ) async {
    repository.result = page(
      List.generate(20, (i) => course(i + 1)),
      more: true,
    );
    await open(tester);
    repository.result = page([course(1, position: 21)]);
    await tester.scrollUntilVisible(
      find.text('Load more courses'),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, 'Load more courses');
    await tester.scrollUntilVisible(
      find.text('Retry catalog'),
      -800,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry catalog'), findsOneWidget);
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });
  testWidgets('details refetch safe data and back preserves query', (
    tester,
  ) async {
    repository.result = page([course(1)]);
    repository.detail = course(1);
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Engineering');
    await tap(tester, 'Search');
    await tap(tester, 'View course: Engineering 1');
    expect(find.text('Course price: 123.45 EGP'), findsOneWidget);
    expect(find.text('Safe description 1'), findsOneWidget);
    expect(find.text('No published sessions yet.'), findsOneWidget);
    await tap(tester, 'Back to catalog');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Engineering',
    );
    expect(find.text('Engineering 1'), findsOneWidget);
  });
  testWidgets('unavailable detail is not shown from cached card', (
    tester,
  ) async {
    repository.result = page([course(1)]);
    await open(tester);
    await tap(tester, 'View course: Engineering 1');
    expect(find.textContaining('This course is unavailable'), findsOneWidget);
    expect(find.text('Safe description 1'), findsNothing);
  });
  testWidgets('preview designation and zero price do not enable playback', (
    tester,
  ) async {
    repository.result = page([course(1)]);
    repository.detail = course(1);
    repository.outline = CatalogPage(
      items: [
        CatalogSession(
          id: id(100),
          courseId: id(1),
          sessionNumber: 1,
          title: 'Preview session',
          description: 'Outline only',
          pricePiasters: 0,
          position: 0,
          isFreePreview: true,
        ),
      ],
      hasMore: false,
      nextCursor: null,
    );
    await open(tester);
    await tap(tester, 'View course: Engineering 1');
    expect(find.text('0.00 EGP'), findsOneWidget);
    expect(
      find.text('Preview designated — playback not enabled'),
      findsOneWidget,
    );
    expect(find.text('Play'), findsNothing);
    expect(find.text('Available'), findsNothing);
  });
  testWidgets('wrong-course outline is rejected and clears detail', (
    tester,
  ) async {
    repository.result = page([course(1)]);
    repository.detail = course(1);
    repository.outline = CatalogPage(
      items: [
        CatalogSession(
          id: id(100),
          courseId: id(2),
          sessionNumber: 1,
          title: 'Wrong parent',
          description: '',
          pricePiasters: 0,
          position: 0,
          isFreePreview: false,
        ),
      ],
      hasMore: false,
      nextCursor: null,
    );
    await open(tester);
    await tap(tester, 'View course: Engineering 1');
    expect(find.text('Wrong parent'), findsNothing);
    expect(find.text('Retry course'), findsOneWidget);
  });
  testWidgets('auth loss clears cards and rejects late response', (
    tester,
  ) async {
    await open(tester);
    final response = Completer<CatalogPage<CatalogCourse>>();
    repository.pending = () => response.future;
    await tester.tap(find.text('Search'));
    await tester.pump();
    account.emit(SessionEvent.signedOut);
    await tester.pump();
    response.complete(page([course(1)]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Catalog access closed'), findsOneWidget);
    expect(find.text('Engineering 1'), findsNothing);
  });
  testWidgets('background clears catalog and requires reopen', (tester) async {
    repository.result = page([course(1)]);
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Catalog access closed'), findsOneWidget);
    expect(find.text('Engineering 1'), findsNothing);
  });
  testWidgets('filters failure is sanitized and retryable', (tester) async {
    repository.filtersError = StateError('CANARY_SECRET');
    await open(tester);
    expect(find.textContaining('CANARY_SECRET'), findsNothing);
    expect(find.text('Retry catalog'), findsOneWidget);
    expect(find.text('No published courses yet.'), findsNothing);
    repository.filtersError = null;
    await tap(tester, 'Retry catalog');
    expect(find.text('No published courses yet.'), findsOneWidget);
  });
  testWidgets('private cover load failure keeps accessible fallback', (
    tester,
  ) async {
    repository.result = page([course(1, cover: '${id(1)}/${id(800)}.png')]);
    await open(tester, cover: (_) async => throw StateError('CANARY_PATH'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Course cover unavailable',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('CANARY_PATH'), findsNothing);
  });
  testWidgets('late cover result after query change is discarded', (
    tester,
  ) async {
    repository.result = page([course(1, cover: '${id(1)}/${id(800)}.png')]);
    final bytes = Completer<Uint8List?>();
    await open(tester, cover: (_) => bytes.future);
    await tester.enterText(find.byType(TextField), 'changed');
    bytes.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'student entrypoint forwards repository and never admin actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        SummitApp(authController: auth, catalogRepository: repository),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Browse courses'));
      await tester.tap(find.text('Browse courses'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.text('Manage courses'), findsNothing);
      expect(find.text('No published courses yet.'), findsOneWidget);
    },
  );
  testWidgets('missing repository hides unfinished entrypoint', (tester) async {
    await tester.pumpWidget(SummitApp(authController: auth));
    await tester.pumpAndSettle();
    expect(find.text('Browse courses'), findsNothing);
  });
  testWidgets('revoked admission during paging clears every cached card', (
    tester,
  ) async {
    repository.result = page(
      List.generate(20, (i) => course(i + 1)),
      more: true,
    );
    await open(tester);
    repository.pending = () async =>
        throw const CatalogFailure(CatalogFailureKind.accessRequired);
    await tester.scrollUntilVisible(
      find.text('Load more courses'),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, 'Load more courses');
    expect(find.textContaining('Catalog access closed'), findsOneWidget);
    expect(find.textContaining('Engineering'), findsNothing);
  });
  testWidgets(
    'actor change closes permanently even if original actor returns',
    (tester) async {
      repository.result = page([course(1)]);
      await open(tester);
      repository.actor = id(998);
      await tap(tester, 'Refresh catalog');
      repository.actor = id(999);
      await tester.pump();
      expect(find.textContaining('Catalog access closed'), findsOneWidget);
      expect(find.text('Engineering 1'), findsNothing);
    },
  );
  testWidgets(
    'details start at top and back restores later-card scroll position',
    (tester) async {
      repository.result = page(List.generate(20, (i) => course(i + 1)));
      repository.detail = course(20);
      await open(tester);
      await tester.scrollUntilVisible(
        find.text('View course: Engineering 20'),
        800,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('View course: Engineering 20'));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final before = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(before, greaterThan(100));
      await tap(tester, 'View course: Engineering 20');
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        0,
      );
      await tap(tester, 'Back to catalog');
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        closeTo(before, 1),
      );
    },
  );
  testWidgets('small screen and large text render without overflow', (
    tester,
  ) async {
    repository.result = page([course(1)]);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: CatalogScreen(auth: auth, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View course: Engineering 1'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
