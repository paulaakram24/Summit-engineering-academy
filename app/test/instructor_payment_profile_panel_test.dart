import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/commerce/instructor_payment_profile_panel.dart';
import 'package:summit_academy/commerce/instructor_payment_repository.dart';

import 'auth_fakes.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const otherActor = '22222222-2222-4222-8222-222222222222';
InstructorPaymentProfile profile({
  String owner = actor,
  String name = 'Fictional Receiver',
  int revision = 1,
}) => InstructorPaymentProfile(
  instructorId: owner,
  recipientName: name,
  phoneNumber: '+12345678901',
  methodConfiguration: InstructorPaymentMethodConfiguration.instapayOnly,
  revision: revision,
);

class ProfilePanelFake implements InstructorPaymentRepository {
  @override
  String? currentActorId = actor;
  InstructorPaymentProfile? current = profile();
  final reads = <String>[];
  final writes = <SaveInstructorPaymentProfileRequest>[];
  Future<InstructorPaymentProfile?> Function()? onRead;
  Future<InstructorPaymentProfile> Function(
    SaveInstructorPaymentProfileRequest,
  )?
  onSave;
  @override
  Future<InstructorPaymentProfile?> getMyProfile({
    required String actorId,
  }) async {
    reads.add(actorId);
    return onRead == null ? current : await onRead!();
  }

  @override
  Future<InstructorPaymentProfile> saveMyProfile(
    SaveInstructorPaymentProfileRequest request,
  ) async {
    writes.add(request);
    if (onSave != null) return onSave!(request);
    return current = InstructorPaymentProfile(
      instructorId: request.actorId,
      recipientName: request.recipientName,
      phoneNumber: request.phoneNumber,
      methodConfiguration: request.methodConfiguration,
      revision: request.expectedRevision + 1,
    );
  }

  @override
  Future<CoursePaymentInstructor?> getCourseInstructor({
    required String actorId,
    required String courseId,
  }) => throw StateError('Not a profile operation');
  @override
  Future<CoursePaymentInstructor> setCourseInstructor(
    SetCoursePaymentInstructorRequest request,
  ) => throw StateError('Not a profile operation');
  @override
  Future<PaymentInstructorPage> listInstructors({
    required String actorId,
    PaymentInstructorCursor? after,
    int limit = paymentInstructorDefaultLimit,
  }) => throw StateError('Not a profile operation');
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late ProfilePanelFake repository;
  late int closed;
  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', actor);
    auth = AuthController(accounts);
    await auth.start();
    repository = ProfilePanelFake();
    closed = 0;
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });

  Widget panel({
    InstructorPaymentRepository? repo,
    AuthController? controller,
    VoidCallback? close,
  }) => InstructorPaymentProfilePanel(
    auth: controller ?? auth,
    repository: repo ?? repository,
    onClose: close ?? () => closed++,
  );
  Future<void> show(
    WidgetTester tester, {
    bool settle = true,
    Size size = const Size(900, 1600),
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
          child: Scaffold(body: panel()),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  void backgroundAndResume(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  ButtonStyleButton button(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );
  String value(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;
  Future<void> confirmSave(WidgetTester tester, {bool settle = true}) async {
    await tap(tester, 'Save receiving details');
    await tap(tester, 'Confirm save', settle: settle);
  }

  testWidgets(
    'own existing profile loads and setup disclaimer never claims verification',
    (tester) async {
      await show(tester);
      expect(repository.reads, [actor]);
      expect(value(tester, 'Recipient name'), 'Fictional Receiver');
      expect(value(tester, 'Receiving phone number'), '+12345678901');
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        find.textContaining('Checkout and payments are not enabled here.'),
        findsOneWidget,
      );
      expect(find.text('Bank name'), findsNothing);
    },
  );

  testWidgets(
    'absent own profile creates revision zero intent only after confirmation',
    (tester) async {
      repository.current = null;
      await show(tester);
      expect(value(tester, 'Recipient name'), '');
      await enter(tester, 'Recipient name', '  Example Payee  ');
      await enter(tester, 'Receiving phone number', '1234567');
      await tap(tester, 'InstaPay and Vodafone Cash (same number)');
      await tap(tester, 'Save receiving details');
      expect(repository.writes, isEmpty);
      expect(
        find.textContaining(
          'This does not verify bank or wallet receiving capability',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Confirm save');
      final request = repository.writes.single;
      expect(request.actorId, actor);
      expect(request.expectedRevision, 0);
      expect(request.recipientName, 'Example Payee');
      expect(request.phoneNumber, '1234567');
      expect(
        request.methodConfiguration,
        InstructorPaymentMethodConfiguration.instapayAndVodafoneCash,
      );
      expect(repository.reads, [actor, actor]);
    },
  );

  testWidgets(
    'cancel save confirmation makes zero writes and preserves edits',
    (tester) async {
      await show(tester);
      await enter(tester, 'Recipient name', 'Unsaved Receiver');
      await tap(tester, 'Save receiving details');
      await tap(tester, 'Cancel');
      expect(repository.writes, isEmpty);
      expect(value(tester, 'Recipient name'), 'Unsaved Receiver');
    },
  );

  testWidgets('invalid recipient and formatted phone block confirmation', (
    tester,
  ) async {
    await show(tester);
    await enter(tester, 'Recipient name', ' ');
    await enter(tester, 'Receiving phone number', '+123 4567');
    await tap(tester, 'Save receiving details');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('without control characters.'), findsOneWidget);
    expect(find.textContaining('No spaces or formatting.'), findsOneWidget);
    expect(repository.writes, isEmpty);
  });

  testWidgets('loading failure is sanitized and requires manual refresh', (
    tester,
  ) async {
    final pending = Completer<InstructorPaymentProfile?>();
    repository.onRead = () => pending.future;
    await show(tester, settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    pending.completeError(StateError('secret server body'));
    await tester.pumpAndSettle();
    expect(find.textContaining('secret server body'), findsNothing);
    expect(find.textContaining('Refresh before editing.'), findsOneWidget);
    repository.onRead = null;
    await tap(tester, 'Refresh receiving setup');
    expect(value(tester, 'Recipient name'), 'Fictional Receiver');
  });

  testWidgets('wrong-actor detail cannot display private fields', (
    tester,
  ) async {
    repository.current = profile(
      owner: otherActor,
      name: 'Other private receiver',
    );
    await show(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Other private receiver'), findsNothing);
  });

  for (final access in [
    'student',
    'signedOut',
    'missingActor',
    'invalidActor',
    'getterFailure',
  ]) {
    testWidgets('$access cannot load or edit profile', (tester) async {
      if (access == 'student') {
        accounts.accessContext = const AccessContext('student', actor);
        await tester.runAsync(() => auth.checkAccess());
      }
      if (access == 'signedOut') auth.lock('connection');
      if (access == 'missingActor') repository.currentActorId = null;
      if (access == 'invalidActor') repository.currentActorId = 'invalid';
      if (access == 'getterFailure') repository = ThrowingActorFake();
      await show(tester);
      expect(repository.reads, isEmpty);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.textContaining('Administrator access changed.'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'success discards ack snapshot and waits for fresh profile before edits',
    (tester) async {
      await show(tester);
      await enter(tester, 'Recipient name', 'Submitted Receiver');
      final pendingRead = Completer<InstructorPaymentProfile?>();
      repository.onSave = (request) async {
        repository.onRead = () => pendingRead.future;
        return profile(name: request.recipientName, revision: 2);
      };
      await confirmSave(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.reads, [actor, actor]);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pendingRead.complete(profile(name: 'Fresh Receiver', revision: 3));
      await tester.pumpAndSettle();
      expect(value(tester, 'Recipient name'), 'Fresh Receiver');
      expect(button(tester, 'Save receiving details').onPressed, isNotNull);
      await tap(tester, 'Save receiving details');
      await tap(tester, 'Confirm save');
      expect(repository.writes.last.expectedRevision, 3);
    },
  );

  testWidgets('duplicate callbacks cannot double-confirm or double-save', (
    tester,
  ) async {
    await show(tester);
    final pending = Completer<InstructorPaymentProfile>();
    repository.onSave = (_) => pending.future;
    final start = button(tester, 'Save receiving details').onPressed!;
    start();
    start();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final confirm = button(tester, 'Confirm save').onPressed!;
    confirm();
    confirm();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    start();
    expect(repository.writes, hasLength(1));
    pending.complete(profile(revision: 2));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'uncertain save clears values, never retries and blocks writes until refresh succeeds',
    (tester) async {
      await show(tester);
      repository.onSave = (_) async => throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.timedOut,
      );
      await confirmSave(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('may already have saved'), findsOneWidget);
      expect(repository.writes, hasLength(1));
      expect(repository.reads, hasLength(1));
      repository.onRead = () async => throw StateError('private');
      await tap(tester, 'Refresh receiving setup');
      expect(find.byType(TextFormField), findsNothing);
      expect(repository.writes, hasLength(1));
      repository.onRead = null;
      await tap(tester, 'Refresh receiving setup');
      expect(button(tester, 'Save receiving details').onPressed, isNotNull);
      expect(repository.writes, hasLength(1));
    },
  );

  testWidgets(
    'conflict preserves selectable read-only values and cannot autosubmit',
    (tester) async {
      await show(tester);
      await enter(tester, 'Recipient name', 'Preserved Receiver');
      await enter(tester, 'Receiving phone number', '+7654321');
      repository.onSave = (_) async => throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.stateConflict,
      );
      await confirmSave(tester);
      expect(value(tester, 'Recipient name'), 'Preserved Receiver');
      expect(value(tester, 'Receiving phone number'), '+7654321');
      for (final input in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(input.readOnly, isTrue);
        expect(input.enabled, isTrue);
        expect(input.enableInteractiveSelection, isTrue);
      }
      expect(button(tester, 'Save receiving details').onPressed, isNull);
      expect(repository.writes, hasLength(1));
      await tap(tester, 'Refresh receiving setup');
      await tap(tester, 'Cancel');
      expect(value(tester, 'Recipient name'), 'Preserved Receiver');
      await tap(tester, 'Refresh receiving setup');
      await tap(tester, 'Discard changes');
      expect(value(tester, 'Recipient name'), 'Fictional Receiver');
      expect(repository.writes, hasLength(1));
    },
  );

  testWidgets('failed refetch after acknowledged save remains noneditable', (
    tester,
  ) async {
    await show(tester);
    repository.onSave = (request) async {
      repository.onRead = () async => throw StateError('private read failure');
      return profile(revision: 2);
    };
    await confirmSave(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Save acknowledged.'), findsNothing);
    expect(repository.writes, hasLength(1));
    expect(repository.reads, hasLength(2));
  });

  for (final phase in ['load', 'save']) {
    for (final loss in ['background', 'signout', 'actor', 'access', 'device']) {
      testWidgets('late $phase after $loss cannot restore protected values', (
        tester,
      ) async {
        final read = Completer<InstructorPaymentProfile?>();
        final save = Completer<InstructorPaymentProfile>();
        if (phase == 'load') repository.onRead = () => read.future;
        await show(tester, settle: phase != 'load');
        if (phase == 'save') {
          repository.onSave = (_) => save.future;
          await confirmSave(tester, settle: false);
        }
        switch (loss) {
          case 'background':
            backgroundAndResume(tester);
          case 'signout':
            auth.lock('connection');
          case 'actor':
            repository.currentActorId = otherActor;
          case 'access':
            await tester.runAsync(() => auth.checkAccess());
          case 'device':
            accounts.accessContext = const AccessContext('admin', otherActor);
            await tester.runAsync(() => auth.checkAccess());
        }
        if (phase == 'load') {
          read.complete(profile());
        } else {
          save.complete(profile(revision: 2));
        }
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(
          find.textContaining('Administrator access changed.'),
          findsOneWidget,
        );
        expect(repository.reads, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final kind in [
    InstructorPaymentFailureKind.accessRequired,
    InstructorPaymentFailureKind.actorChanged,
  ]) {
    testWidgets(
      '$kind save denial clears profile rather than preserving edits',
      (tester) async {
        await show(tester);
        await enter(tester, 'Recipient name', 'Private Unsaved');
        repository.onSave = (_) async => throw InstructorPaymentFailure(kind);
        await confirmSave(tester);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('Private Unsaved'), findsNothing);
      },
    );
  }

  testWidgets(
    'background confirmation invalidates before frame and retained callback makes no write',
    (tester) async {
      await show(tester);
      await tap(tester, 'Save receiving details');
      final callback = button(tester, 'Confirm save').onPressed!;
      backgroundAndResume(tester);
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(repository.writes, isEmpty);
    },
  );

  testWidgets(
    'actor changes during confirmation cannot transmit captured intent',
    (tester) async {
      await show(tester);
      await tap(tester, 'Save receiving details');
      repository.currentActorId = otherActor;
      button(tester, 'Confirm save').onPressed!();
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets(
    'dependency replacement discards old reads and old confirmation callbacks',
    (tester) async {
      await show(tester);
      await tap(tester, 'Save receiving details');
      final callback = button(tester, 'Confirm save').onPressed!;
      final replacement = ProfilePanelFake()
        ..current = profile(name: 'Replacement Receiver');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: panel(repo: replacement)),
        ),
      );
      callback();
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      expect(replacement.writes, isEmpty);
      expect(value(tester, 'Recipient name'), 'Replacement Receiver');
    },
  );

  testWidgets(
    'dirty Close and platform Back require discard confirmation and cancel writes nothing',
    (tester) async {
      await show(tester);
      await enter(tester, 'Recipient name', 'Unsaved Receiver');
      await tap(tester, 'Close receiving setup');
      await tap(tester, 'Cancel');
      expect(closed, 0);
      expect(value(tester, 'Recipient name'), 'Unsaved Receiver');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tap(tester, 'Discard changes');
      expect(closed, 1);
      expect(repository.writes, isEmpty);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets(
    'Close latches before frame so pending read and retained save cannot resurrect',
    (tester) async {
      final read = Completer<InstructorPaymentProfile?>();
      repository.onRead = () => read.future;
      await show(tester, settle: false);
      button(tester, 'Close receiving setup').onPressed!();
      read.complete(profile());
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.byType(TextFormField), findsNothing);
      expect(repository.writes, isEmpty);
    },
  );

  testWidgets(
    'disposed panel removes only its own dialog, preserving unrelated route above',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, showPanel, _) =>
                  showPanel ? panel() : const Text('Parent screen'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Save receiving details');
      final callback = button(tester, 'Confirm save').onPressed!;
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      expect(repository.writes, isEmpty);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Unrelated screen'), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Parent screen'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late save after dispose makes no refetch and no widget exception',
    (tester) async {
      final pending = Completer<InstructorPaymentProfile>();
      repository.onSave = (_) => pending.future;
      await show(tester);
      await confirmSave(tester, settle: false);
      await tester.pumpWidget(const SizedBox());
      pending.complete(profile(revision: 2));
      await tester.pumpAndSettle();
      expect(repository.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pushed Scaffold Close and confirmed AppBar Back each pop once', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Parent screen')),
      ),
    );
    void open() {
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Receiving setup')),
              body: SafeArea(
                child: panel(
                  close: () {
                    closed++;
                    navigator.currentState!.pop();
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    open();
    await tester.pumpAndSettle();
    await tap(tester, 'Close receiving setup');
    expect(closed, 1);
    expect(find.text('Parent screen'), findsOneWidget);
    open();
    await tester.pumpAndSettle();
    await enter(tester, 'Recipient name', 'Unsaved Receiver');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(closed, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tap(tester, 'Discard changes');
    expect(closed, 2);
    expect(find.text('Parent screen'), findsOneWidget);
    expect(repository.writes, isEmpty);
  });

  testWidgets(
    'replacement repository read wins over old delayed private profile',
    (tester) async {
      final read = Completer<InstructorPaymentProfile?>();
      repository.onRead = () => read.future;
      await show(tester, settle: false);
      final replacement = ProfilePanelFake()
        ..current = profile(name: 'Fresh Receiver');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: panel(repo: replacement)),
        ),
      );
      await tester.pumpAndSettle();
      read.complete(profile(name: 'Obsolete Private Receiver'));
      await tester.pumpAndSettle();
      expect(value(tester, 'Recipient name'), 'Fresh Receiver');
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'role loss clears even conflict-preserved controllers before next frame',
    (tester) async {
      await show(tester);
      await enter(tester, 'Recipient name', 'Private Preserved Receiver');
      repository.onSave = (_) async => throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.stateConflict,
      );
      await confirmSave(tester);
      final controllers = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((w) => w.controller!)
          .toList();
      accounts.accessContext = const AccessContext('student', actor);
      await tester.runAsync(() => auth.checkAccess());
      expect(
        controllers.every((controller) => controller.text.isEmpty),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      accounts.accessContext = const AccessContext('admin', actor);
      await tester.runAsync(() => auth.checkAccess());
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(repository.reads, hasLength(1));
    },
  );

  testWidgets(
    'read access denial closes panel rather than offering writable refresh',
    (tester) async {
      repository.onRead = () async => throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.accessRequired,
      );
      await show(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Refresh receiving setup'), findsNothing);
      expect(
        find.textContaining('Administrator access changed.'),
        findsOneWidget,
      );
    },
  );

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('320-wide ${scale}x validation errors wrap without truncation', (
      tester,
    ) async {
      repository.current = null;
      await show(tester, size: const Size(320, 640), scale: scale);
      await tap(tester, 'Save receiving details');
      for (final label in ['Recipient name', 'Receiving phone number']) {
        final input = tester.widget<TextField>(
          find.descendant(of: field(label), matching: find.byType(TextField)),
        );
        expect(input.decoration!.errorMaxLines, 16);
      }
      for (final message in [
        'Use 1–160 characters without control characters.',
        'Use 7–15 digits, optionally starting with +. No spaces or formatting.',
      ]) {
        final error = find.text(message);
        expect(error, findsOneWidget);
        await tester.ensureVisible(error);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(error);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(0));
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets(
      '320-wide ${scale}x text keyboard and confirmation stay accessible',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await show(
            tester,
            size: const Size(320, 640),
            scale: scale,
            keyboard: 220,
          );
          await enter(
            tester,
            'Recipient name',
            'Fictional Accessible Receiver',
          );
          await enter(tester, 'Receiving phone number', '+12345678901');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tap(tester, 'InstaPay and Vodafone Cash (same number)');
          await tap(tester, 'Save receiving details');
          expect(find.text('Save receiving details?'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(tester, meetsGuideline(labeledTapTargetGuideline));
          expect(tester, meetsGuideline(androidTapTargetGuideline));
          await tap(tester, 'Cancel');
          expect(repository.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

class ThrowingActorFake extends ProfilePanelFake {
  @override
  String? get currentActorId => throw StateError('private identity failure');
}
