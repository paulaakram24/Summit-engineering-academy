import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';
import 'package:summit_academy/catalog/catalog_screen.dart';

import 'auth_fakes.dart';
import 'catalog_lifecycle_test.dart' show LifecycleCatalogFake, outlinePage;
import 'catalog_screen_test.dart' show course, id, page;

const longTitle =
    'Advanced structural engineering and sustainable construction for complex urban infrastructure';
const longSessionTitle =
    'Practical analysis of reinforced concrete structures and resilient foundations under challenging environmental conditions';
const longCategory =
    'Civil engineering, structural systems, sustainable construction and infrastructure design';
const longLevel =
    'Advanced undergraduate and postgraduate professional engineering studies, final academic year';

CatalogCourse accessibleCourse() => CatalogCourse(
  id: id(1),
  title: longTitle,
  description:
      'A detailed course description for accessible engineering study.',
  instructor: 'Department of structural and environmental engineering',
  category: longCategory,
  level: longLevel,
  pricePiasters: 12345,
  position: 1,
  coverPath: null,
);

void main() {
  late FakeAuthRepository account;
  late AuthController auth;
  late LifecycleCatalogFake repository;

  setUp(() async {
    account = FakeAuthRepository()..hasSession = true;
    auth = AuthController(account);
    await auth.start();
    repository = LifecycleCatalogFake();
  });
  tearDown(() async {
    auth.dispose();
    await account.dispose();
  });

  Future<void> open(WidgetTester tester, double width, double scale) async {
    // testWidgets enables and disposes its semantics handle automatically.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(Size(width, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: CatalogScreen(auth: auth, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)), Size(width, 640));
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(CatalogScreen)))
          .scale(10),
      scale * 10,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'Initial layout must not overflow.',
    );
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 250,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      maxScrolls: 60,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Scrolling must not reveal layout overflow.',
    );
  }

  Future<void> guidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  }

  bool liveRegionFor(WidgetTester tester, String text) {
    SemanticsNode? node = tester.getSemantics(find.text(text));
    while (node != null) {
      if (node.getSemanticsData().flagsCollection.isLiveRegion) return true;
      node = node.parent;
    }
    return false;
  }

  for (final state in [
    'catalog error',
    'catalog no-results',
    'detail error',
    'detail unavailable',
  ]) {
    testWidgets('async $state is announced as a semantics live region', (
      tester,
    ) async {
      repository.result = page([course(1)]);
      await open(tester, 360, 2);
      late String message;
      if (state.startsWith('catalog')) {
        final delayed = Completer<CatalogPage<CatalogCourse>>();
        repository.pending = () => delayed.future;
        if (state == 'catalog no-results') {
          await tester.enterText(find.byType(TextField), 'No matching title');
          tester.testTextInput.hide();
        }
        await reveal(tester, find.text('Search'));
        await tester.tap(find.text('Search'));
        await tester.pump();
        if (state == 'catalog error') {
          delayed.completeError(
            const CatalogFailure(CatalogFailureKind.requestFailed),
          );
          message = const CatalogFailure(CatalogFailureKind.requestFailed)
              .message;
        } else {
          delayed.complete(page([]));
          message = 'No courses match your search or filters.';
        }
      } else {
        final delayed = Completer<CatalogCourse?>();
        repository.pendingDetail = () => delayed.future;
        await reveal(tester, find.text('View course: Engineering 1'));
        await tester.tap(find.text('View course: Engineering 1'));
        await tester.pump();
        if (state == 'detail error') {
          delayed.completeError(
            const CatalogFailure(CatalogFailureKind.requestFailed),
          );
          message = const CatalogFailure(CatalogFailureKind.requestFailed)
              .message;
        } else {
          delayed.complete(null);
          message = 'This course is unavailable. It may have been removed.';
        }
      }
      await tester.pumpAndSettle();
      await reveal(tester, find.text(message));
      expect(
        liveRegionFor(tester, message),
        isTrue,
        reason:
            'Async $state must be announced without moving accessibility focus; a label alone is insufficient.',
      );
    });
  }

  testWidgets(
    'expanded long category remains visually readable without ellipsis at 320 text3',
    (tester) async {
      repository.filters = CatalogFilters(
        categories: [longCategory],
        levels: [longLevel],
      );
      await open(tester, 320, 3);
      final field = find.byType(DropdownButtonFormField<String>).first;
      await reveal(tester, field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final option = find
          .descendant(
            of: find.byType(DropdownMenuItem<String>),
            matching: find.text(longCategory),
          )
          .last;
      await tester.scrollUntilVisible(
        option,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: option, matching: find.byType(RichText)),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'An expanded category option must expose its complete visual label, not only its semantics text.',
      );
    },
  );

  for (final width in [320.0, 360.0]) {
    for (final scale in [2.0, 3.0]) {
      final configuration = '${width.toInt()}x640 text$scale';
      testWidgets(
        'empty and no-match states stay reachable and labeled $configuration',
        (tester) async {
          await open(tester, width, scale);
          expect(
            find.bySemanticsLabel(RegExp('Search courses')),
            findsOneWidget,
          );
          await guidelines(tester);
          await reveal(tester, find.text('No published courses yet.'));
          expect(
            find.bySemanticsLabel('No published courses yet.'),
            findsOneWidget,
          );
          await reveal(tester, find.byType(TextField), delta: -250);
          await tester.enterText(find.byType(TextField), 'Unmatched course');
          tester.testTextInput.hide();
          await reveal(tester, find.text('Search'));
          expect(
            tester
                .getSemantics(find.text('Search'))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(find.text('Search'));
          await tester.pumpAndSettle();
          await reveal(
            tester,
            find.text('No courses match your search or filters.'),
          );
          expect(
            find.bySemanticsLabel('No courses match your search or filters.'),
            findsOneWidget,
          );
          await guidelines(tester);
        },
      );

      testWidgets('sanitized error and retry are accessible $configuration', (
        tester,
      ) async {
        repository.filtersError = StateError('PRIVATE_CANARY');
        await open(tester, width, scale);
        await reveal(tester, find.text('Retry catalog'));
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.bySemanticsLabel('Retry catalog'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.text('Retry catalog'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        await guidelines(tester);
        repository.filtersError = null;
        await tester.tap(find.text('Retry catalog'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('No published courses yet.'));
        expect(find.text('No published courses yet.'), findsOneWidget);
      });

      testWidgets(
        'long populated course and session detail remain readable $configuration',
        (tester) async {
          final item = accessibleCourse();
          repository.result = page([item]);
          repository.detail = item;
          repository.outline = outlinePage([
            CatalogSession(
              id: id(101),
              courseId: id(1),
              sessionNumber: 1,
              title: longSessionTitle,
              description:
                  'Accessible session description, with no protected playback.',
              pricePiasters: 0,
              position: 1,
              isFreePreview: true,
            ),
          ]);
          await open(tester, width, scale);
          await reveal(tester, find.byType(Card));
          expect(
            find.bySemanticsLabel(RegExp('Course cover unavailable')),
            findsOneWidget,
          );
          await reveal(tester, find.text(longTitle));
          // Cards can merge adjacent text into one semantics node; retain the
          // complete title rather than requiring a standalone node.
          expect(
            tester.getSemantics(find.text(longTitle)).getSemanticsData().label,
            contains(longTitle),
          );
          final title = tester.widget<Text>(find.text(longTitle));
          expect(title.maxLines, isNull);
          expect(title.overflow, isNot(TextOverflow.ellipsis));
          await reveal(tester, find.text('View course: $longTitle'));
          expect(
            find.bySemanticsLabel('View course: $longTitle'),
            findsOneWidget,
          );
          await guidelines(tester);
          // At 320/text3 the wrapped button can exceed the viewport height.
          // A user can still tap its visible portion; an off-screen center is
          // not a legitimate navigation failure.
          final button = find.widgetWithText(
            OutlinedButton,
            'View course: $longTitle',
          );
          final visible = tester
              .getRect(button)
              .intersect(tester.getRect(find.byType(ListView)));
          expect(visible.width, greaterThanOrEqualTo(48));
          expect(visible.height, greaterThanOrEqualTo(48));
          await tester.tapAt(visible.center);
          await tester.pumpAndSettle();
          expect(find.text('Back to catalog'), findsOneWidget);
          await reveal(tester, find.text('1. $longSessionTitle'));
          expect(
            tester
                .getSemantics(find.text('1. $longSessionTitle'))
                .getSemanticsData()
                .label,
            contains('1. $longSessionTitle'),
          );
          final sessionTitle = tester.widget<Text>(
            find.text('1. $longSessionTitle'),
          );
          expect(sessionTitle.maxLines, isNull);
          expect(sessionTitle.overflow, isNot(TextOverflow.ellipsis));
          await reveal(
            tester,
            find.text('Preview designated — playback not enabled'),
          );
          expect(
            tester
                .getSemantics(
                  find.text('Preview designated — playback not enabled'),
                )
                .getSemanticsData()
                .label,
            contains('Preview designated — playback not enabled'),
          );
          await reveal(tester, find.text('Back to catalog'), delta: -250);
          expect(find.bySemanticsLabel('Back to catalog'), findsOneWidget);
          await guidelines(tester);
          await tester.tap(find.text('Back to catalog'));
          await tester.pumpAndSettle();
          expect(repository.detailRequests, [id(1)]);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'long category and level options retain full semantics $configuration',
        (tester) async {
          repository.filters = CatalogFilters(
            categories: [longCategory],
            levels: [longLevel],
          );
          repository.result = page([course(1)]);
          await open(tester, width, scale);
          for (final label in ['Category', 'Level / year']) {
            final field = find.byWidgetPredicate(
              (widget) =>
                  widget is DropdownButtonFormField<String> &&
                  widget.decoration.labelText == label,
            );
            await reveal(
              tester,
              field,
              delta: label == 'Category' ? -250 : 250,
            );
            await tester.tap(field);
            await tester.pumpAndSettle();
            final option = label == 'Category' ? longCategory : longLevel;
            final menuText = find
                .descendant(
                  of: find.byType(DropdownMenuItem<String>),
                  matching: find.text(option),
                )
                .last;
            await tester.scrollUntilVisible(
              menuText,
              180,
              scrollable: find.byType(Scrollable).last,
            );
            final menuParagraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: menuText, matching: find.byType(RichText)),
            );
            expect(
              menuParagraph.didExceedMaxLines,
              isFalse,
              reason: 'The actual expanded menu, not the compact closed copy, must wrap the full label.',
            );
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape(option))),
              findsWidgets,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Expanded long filter must not overflow.',
            );
            await guidelines(tester);
            final menuItem = find.ancestor(
              of: menuText,
              matching: find.byType(DropdownMenuItem<String>),
            );
            final menuViewport = tester.getRect(find.byType(Scrollable).last);
            final visibleItem = tester
                .getRect(menuItem)
                .intersect(menuViewport);
            expect(visibleItem.height, greaterThanOrEqualTo(48));
            expect(visibleItem.width, greaterThanOrEqualTo(48));
            await tester.tapAt(visibleItem.center);
            await tester.pumpAndSettle();
            expect(
              label == 'Category'
                  ? repository.requests.last.category
                  : repository.requests.last.level,
              option,
              reason: 'The tap must actually select the expanded menu item.',
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Selected long filter must not overflow.',
            );
            final selected = find
                .descendant(of: field, matching: find.text(option))
                .last;
            final selectedRichText = find.descendant(
              of: selected,
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              selectedRichText,
            );
            expect(paragraph.maxLines, 2);
            expect(
              tester.getSemantics(selected).getSemanticsData().label,
              contains(option),
            );
            final textBounds = tester.getRect(selectedRichText);
            final fieldBounds = tester.getRect(field);
            expect(
              textBounds.top,
              greaterThanOrEqualTo(fieldBounds.top - 0.01),
            );
            expect(
              textBounds.bottom,
              lessThanOrEqualTo(fieldBounds.bottom + 0.01),
              reason: 'The compact selected label must fit within the closed field.',
            );
            await reveal(tester, field);
            final tooltip = find
                .ancestor(of: selected, matching: find.byType(Tooltip))
                .last;
            expect(tester.widget<Tooltip>(tooltip).message, option);
            await tester.longPress(selected);
            await tester.pumpAndSettle();
            // Tooltip uses Text.rich. OverlayPortal retains logical ancestors,
            // so field ancestry cannot distinguish its visible overlay.
            final tooltipText = find.byWidgetPredicate(
              (widget) =>
                  widget is Text && widget.textSpan?.toPlainText() == option,
            );
            expect(
              tooltipText,
              findsOneWidget,
              reason: 'Long-press must visibly reveal the complete label.',
            );
            final tooltipParagraph = find.descendant(
              of: tooltipText,
              matching: find.byType(RichText),
            );
            expect(
              tester
                  .renderObject<RenderParagraph>(tooltipParagraph)
                  .didExceedMaxLines,
              isFalse,
            );
            expect(tester.takeException(), isNull);
            Tooltip.dismissAllToolTips();
            await tester.pumpAndSettle();
          }
          expect(repository.requests.last.category, longCategory);
          expect(repository.requests.last.level, longLevel);
        },
      );
    }
  }
}
