import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late AuthController auth;

  setUp(() {
    repo = FakeAuthRepository()
      ..hasSession = true
      ..details = const AccountProfile(
        name: 'Synthetic Learner',
        phone: '',
        university: '',
      );
    auth = AuthController(repo);
  });

  tearDown(() async {
    auth.dispose();
    await repo.dispose();
  });

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Finder phoneEditable() => find.descendant(
    of: field('Phone (required)'),
    matching: find.byType(EditableText),
  );

  Future<void> showFullApp(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(auth.start);
    await tester.pumpWidget(SummitApp(authController: auth));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Phone (required)'));
    await tester.pumpAndSettle();
    expect(auth.stage, AuthStage.completeProfile);
    expect(repo.calls, ['access', 'profile']);
  }

  Map<String, TextEditingController> controllers(WidgetTester tester) => {
    for (final label in [
      'Name (required)',
      'Phone (required)',
      'University (required)',
    ])
      label: tester.widget<TextFormField>(field(label)).controller!,
  };

  void expectSameControllers(
    WidgetTester tester,
    Map<String, TextEditingController> original,
  ) {
    for (final entry in original.entries) {
      expect(
        tester.widget<TextFormField>(field(entry.key)).controller,
        same(entry.value),
        reason: '${entry.key} controller replaced; repo.calls=${repo.calls}',
      );
    }
    expect(auth.stage, AuthStage.completeProfile);
    expect(
      repo.calls,
      ['access', 'profile'],
      reason: 'Visible focus/metrics/scroll must not trigger an access check.',
    );
  }

  testWidgets(
    'SummitApp blank Phone retains focus and controllers across keyboard metrics',
    (tester) async {
      await showFullApp(tester);
      final original = controllers(tester);
      final panelState = tester.state(find.byType(AuthPanel));
      await tester.tap(field('Phone (required)'));
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(phoneEditable()).focusNode;
      expect(focus.hasFocus, isTrue);

      // Simulate keyboard opening/resizing/closing, without lifecycle events.
      for (final bottom in [280.0, 340.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pumpAndSettle();
        expectSameControllers(tester, original);
        expect(tester.state(find.byType(AuthPanel)), same(panelState));
        expect(
          tester.widget<EditableText>(phoneEditable()).focusNode,
          same(focus),
        );
        expect(focus.hasFocus, isTrue, reason: 'Keyboard inset: $bottom');
        expect(original['Phone (required)']!.text, isEmpty);
      }
    },
  );

  testWidgets(
    'SummitApp transient inactive resumed preserves Phone focus draft and controllers without access checks',
    (tester) async {
      await showFullApp(tester);
      final original = controllers(tester);
      final panelState = tester.state(find.byType(AuthPanel));
      await tester.tap(field('Phone (required)'));
      await tester.enterText(field('Phone (required)'), '123');
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(phoneEditable()).focusNode;
      expect(focus.hasFocus, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      // Render the interruption before resuming: a same-frame cycle can hide
      // the checking screen and miss the lost-focus regression.
      await tester.pump(const Duration(milliseconds: 168));
      expectSameControllers(tester, original);
      expect(original['Phone (required)']!.text, '123');
      expect(focus.hasFocus, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => auth.settled);
      await tester.pumpAndSettle();
      expectSameControllers(tester, original);
      expect(tester.state(find.byType(AuthPanel)), same(panelState));
      expect(
        tester.widget<EditableText>(phoneEditable()).focusNode,
        same(focus),
      );
      expect(focus.hasFocus, isTrue);
      expect(original['Phone (required)']!.text, '123');
    },
  );

  testWidgets(
    'SummitApp duplicate resumed preserves Phone draft and focus without access checks',
    (tester) async {
      await showFullApp(tester);
      final original = controllers(tester);
      await tester.tap(field('Phone (required)'));
      await tester.enterText(field('Phone (required)'), '456');
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(phoneEditable()).focusNode;
      final observer =
          tester.state(find.byType(AuthPanel)) as WidgetsBindingObserver;

      // Deliver both notifications directly so binding-level deduplication
      // cannot make this guard pass without exercising the panel observer.
      for (var notification = 0; notification < 2; notification++) {
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.runAsync(() => auth.settled);
        await tester.pumpAndSettle();
        expectSameControllers(tester, original);
        expect(
          tester.widget<EditableText>(phoneEditable()).focusNode,
          same(focus),
        );
        expect(focus.hasFocus, isTrue);
        expect(original['Phone (required)']!.text, '456');
      }
    },
  );

  testWidgets(
    'SummitApp hidden paused clears protected state and resume revalidation failure blocks access',
    (tester) async {
      await showFullApp(tester);
      expect(auth.profile, isNotNull);
      expect(auth.access, isNotNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      // Hidden/paused suppress automatic frames; render the already-cleared
      // controller state explicitly before inspecting the background UI.
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(auth.stage, AuthStage.checking);
      expect(auth.profile, isNull);
      expect(auth.access, isNull);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Checking account access'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(auth.stage, AuthStage.checking);
      expect(repo.calls, ['access', 'profile']);

      final pending = Completer<AccessContext>();
      repo.accessCompleter = pending;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(repo.calls, ['access', 'profile', 'access']);
      expect(auth.stage, AuthStage.checking);
      expect(auth.profile, isNull);
      expect(auth.access, isNull);
      expect(find.byType(TextFormField), findsNothing);

      await tester.runAsync(() async {
        pending.completeError(const AccountFailure('device_revoked'));
        await auth.settled;
      });
      await tester.pumpAndSettle();
      expect(auth.stage, AuthStage.blocked);
      expect(auth.profile, isNull);
      expect(auth.access, isNull);
      expect(find.text('Account access unavailable'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(repo.calls, ['access', 'profile', 'access', 'localSignOut']);
    },
  );

  testWidgets(
    'SummitApp focused Phone draft survives keyboard and ListView scroll out and back',
    (tester) async {
      await showFullApp(tester);
      final original = controllers(tester);
      final panelState = tester.state(find.byType(AuthPanel));
      await tester.tap(field('Phone (required)'));
      await tester.enterText(field('Phone (required)'), '123');
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(phoneEditable()).focusNode;
      expect(focus.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expectSameControllers(tester, original);

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Scroll to both list extents while the keyboard reduces the viewport.
      scrollable.position.jumpTo(scrollable.position.minScrollExtent);
      await tester.pumpAndSettle();
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Phone (required)'));
      await tester.pumpAndSettle();

      expectSameControllers(tester, original);
      expect(tester.state(find.byType(AuthPanel)), same(panelState));
      expect(
        tester.widget<EditableText>(phoneEditable()).focusNode,
        same(focus),
      );
      expect(focus.hasFocus, isTrue);
      expect(original['Phone (required)']!.text, '123');
      expect(original['Name (required)']!.text, 'Synthetic Learner');
      expect(original['University (required)']!.text, isEmpty);
    },
  );
}
