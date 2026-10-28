import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/course_image_selector.dart';
import 'package:summit_academy/content/material_file_selector.dart';
import 'package:summit_academy/content/material_file_upload_panel.dart';
import 'package:summit_academy/content/material_file_upload_repository.dart';
import 'package:summit_academy/content/material_models.dart';

import 'auth_fakes.dart';
import 'material_models_test.dart' as fixtures;

MaterialDescriptor material({
  MaterialKind kind = MaterialKind.file,
  bool deleted = false,
}) => MaterialDescriptor.fromJson(
  fixtures.materialRow(kind: kind, deleted: deleted),
);
SelectedMaterialFile selected({
  String name = 'Synthetic notes.txt',
  MaterialKind kind = MaterialKind.file,
}) => SelectedMaterialFile.fromBytes(
  kind: kind,
  fileName: name,
  bytes: kind == MaterialKind.pdf
      ? ascii.encode('%PDF-1.7\n%%EOF')
      : utf8.encode('Synthetic teaching fixture\n'),
);
MaterialFileUpload row({
  String name = 'Earlier notes.txt',
  String owner = fixtures.materialId,
  int number = 1,
  String state = 'uploaded',
  SelectedMaterialFile? file,
}) => MaterialFileUpload.fromJson({
  'asset_id': '11111111-1111-4111-8111-${number.toString().padLeft(12, '0')}',
  'material_id': owner,
  'file_name': file?.fileName ?? name,
  'content_type': file?.contentType ?? 'text/plain',
  'byte_length': file?.byteLength ?? 10,
  'state': state,
});

class UploadPanelRepositoryFake implements MaterialFileUploadRepository {
  @override
  String? currentActorId = fixtures.actorId;
  List<MaterialFileUpload> rows = [];
  final lists = <({String actorId, MaterialDescriptor material})>[];
  final uploads = <MaterialFileUploadRequest>[];
  final checks = <MaterialFileUploadRequest>[];
  Future<List<MaterialFileUpload>> Function()? onList;
  Future<MaterialFileUpload> Function(MaterialFileUploadRequest)? onUpload,
      onCheck;
  void Function(MaterialFileUploadPhase)? phaseCallback;
  @override
  Future<List<MaterialFileUpload>> listUploads({
    required String actorId,
    required MaterialDescriptor material,
  }) async {
    lists.add((actorId: actorId, material: material));
    return onList == null ? rows : onList!();
  }

  @override
  Future<MaterialFileUpload> upload(
    MaterialFileUploadRequest request, {
    void Function(MaterialFileUploadPhase)? onPhase,
  }) async {
    uploads.add(request);
    phaseCallback = onPhase;
    if (onUpload != null) return onUpload!(request);
    final result = row(file: request.file);
    rows = [result];
    return result;
  }

  @override
  Future<MaterialFileUpload> checkUpload(
    MaterialFileUploadRequest request, {
    void Function()? ensureActive,
  }) async {
    ensureActive?.call();
    checks.add(request);
    return onCheck == null ? row(file: request.file) : onCheck!(request);
  }
}

class FileSelectorFake implements MaterialFileSelector {
  SelectedMaterialFile? result = selected();
  Future<SelectedMaterialFile?> Function(AuthController, MaterialKind)?
  onSelect;
  final kinds = <MaterialKind>[];
  @override
  Future<SelectedMaterialFile?> select(
    AuthController auth,
    MaterialKind kind,
  ) async {
    kinds.add(kind);
    return onSelect == null ? result : onSelect!(auth, kind);
  }
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late UploadPanelRepositoryFake repository;
  late FileSelectorFake selector;
  late MaterialDescriptor descriptor;
  late int closed;
  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', fixtures.actorId);
    auth = AuthController(accounts);
    await auth.start();
    repository = UploadPanelRepositoryFake();
    selector = FileSelectorFake();
    descriptor = material();
    closed = 0;
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });

  Widget panel({
    MaterialFileUploadRepository? repo,
    MaterialFileSelector? pick,
    Key? key,
    VoidCallback? close,
    AuthController? controller,
  }) => MaterialFileUploadPanel(
    key: key,
    auth: controller ?? auth,
    material: descriptor,
    repository: repo ?? repository,
    selector: pick ?? selector,
    onClose: close ?? () => closed++,
  );
  Future<void> show(
    WidgetTester tester, {
    bool settle = true,
    bool withAuthPanel = false,
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
          child: Scaffold(
            body: withAuthPanel
                ? Column(
                    children: [
                      Offstage(child: AuthPanel(controller: auth)),
                      Expanded(child: panel()),
                    ],
                  )
                : panel(),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
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
  Future<void> choose(WidgetTester tester) => tap(tester, 'Choose file');
  Future<void> send(WidgetTester tester, {bool settle = true}) async {
    await tap(tester, 'Upload selected file');
    await tap(tester, 'Confirm upload', settle: settle);
  }

  void background(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void resume(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets(
    'initial list uses captured actor/material and honest quarantine-only empty state',
    (tester) async {
      await show(tester);
      expect(repository.lists.single.actorId, fixtures.actorId);
      expect(identical(repository.lists.single.material, descriptor), isTrue);
      expect(find.text('No uploads on this page.'), findsOneWidget);
      expect(find.textContaining('Private quarantine only'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Publish'), findsNothing);
    },
  );

  testWidgets(
    'list loading/error are sanitized and choose requires successful refresh',
    (tester) async {
      final pending = Completer<List<MaterialFileUpload>>();
      repository.onList = () => pending.future;
      await show(tester, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(button(tester, 'Choose file').onPressed, isNull);
      pending.completeError(StateError('/private/source.pdf secret body'));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret body'), findsNothing);
      expect(button(tester, 'Choose file').onPressed, isNull);
      repository.onList = null;
      await tap(tester, 'Refresh uploads');
      expect(button(tester, 'Choose file').onPressed, isNotNull);
    },
  );

  for (final variant in [
    'wrongMaterial',
    'duplicate',
    'oversized',
    'wrongKind',
  ]) {
    testWidgets(
      '$variant list is rejected without displaying private filenames',
      (tester) async {
        switch (variant) {
          case 'wrongMaterial':
            repository.rows = [row(owner: fixtures.otherId)];
          case 'duplicate':
            repository.rows = [row(), row()];
          case 'oversized':
            repository.rows = List.generate(21, (i) => row(number: i + 1));
          case 'wrongKind':
            descriptor = material(kind: MaterialKind.pdf);
            repository.rows = [row()];
        }
        await show(tester);
        expect(find.text('Earlier notes.txt'), findsNothing);
        expect(button(tester, 'Choose file').onPressed, isNull);
      },
    );
  }

  testWidgets(
    '20 recent uploaded/reserved statuses do not imply student availability',
    (tester) async {
      repository.rows = List.generate(
        20,
        (i) => row(
          number: i + 1,
          name: 'Fixture $i.txt',
          state: i == 0 ? 'reserved' : 'uploaded',
        ),
      );
      await show(tester);
      expect(find.text('Showing up to 20 recent uploads.'), findsOneWidget);
      expect(
        find.text(
          'Reserved — upload not confirmed. Not available to students.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Uploaded — awaiting trusted validation. Not available to students.',
        ),
        findsNWidgets(19),
      );
    },
  );

  for (final variant in [
    'student',
    'signedOut',
    'missingActor',
    'deleted',
    'unsupported',
  ]) {
    testWidgets('$variant cannot list or select', (tester) async {
      switch (variant) {
        case 'student':
          accounts.accessContext = const AccessContext(
            'student',
            fixtures.actorId,
          );
          await tester.runAsync(() => auth.checkAccess());
        case 'signedOut':
          auth.lock('connection');
        case 'missingActor':
          repository.currentActorId = null;
        case 'deleted':
          descriptor = material(deleted: true);
        case 'unsupported':
          descriptor = material(kind: MaterialKind.video);
      }
      await show(tester);
      expect(repository.lists, isEmpty);
      expect(find.text('Choose file'), findsNothing);
      expect(selector.kinds, isEmpty);
    });
  }

  testWidgets(
    'selection displays basename/type/size without preview or upload',
    (tester) async {
      await show(tester);
      await choose(tester);
      expect(selector.kinds, [MaterialKind.file]);
      expect(find.text('Synthetic notes.txt'), findsOneWidget);
      expect(
        find.text('${selector.result!.byteLength} bytes • text/plain'),
        findsOneWidget,
      );
      expect(find.text('Selected — not uploaded'), findsOneWidget);
      expect(repository.uploads, isEmpty);
      expect(find.byType(Image), findsNothing);
      await tap(tester, 'Discard selection');
      expect(find.text('Synthetic notes.txt'), findsNothing);
    },
  );

  testWidgets(
    'canceled/error selection preserves earlier unsaved selection and sends nothing',
    (tester) async {
      await show(tester);
      await choose(tester);
      selector.result = null;
      await choose(tester);
      expect(find.text('Synthetic notes.txt'), findsOneWidget);
      selector.onSelect = (_, _) async =>
          throw StateError('/private/secret.txt');
      await choose(tester);
      expect(find.text('Synthetic notes.txt'), findsOneWidget);
      expect(find.textContaining('/private/secret.txt'), findsNothing);
      expect(repository.uploads, isEmpty);
    },
  );

  testWidgets('wrong-kind selection is rejected without displaying its name', (
    tester,
  ) async {
    selector.result = selected(name: 'Different.pdf', kind: MaterialKind.pdf);
    await show(tester);
    await choose(tester);
    expect(find.text('Different.pdf'), findsNothing);
    expect(find.text('Upload selected file'), findsNothing);
  });

  testWidgets(
    'cancel confirmation means zero writes and keeps selected bytes',
    (tester) async {
      await show(tester);
      await choose(tester);
      await tap(tester, 'Upload selected file');
      expect(
        find.textContaining('does not replace an existing asset'),
        findsOneWidget,
      );
      expect(repository.uploads, isEmpty);
      await tap(tester, 'Cancel');
      expect(find.text('Synthetic notes.txt'), findsOneWidget);
      expect(repository.uploads, isEmpty);
    },
  );

  testWidgets(
    'duplicate upload/confirm callbacks produce one captured actor-bound request',
    (tester) async {
      final pending = Completer<MaterialFileUpload>();
      repository.onUpload = (_) => pending.future;
      await show(tester);
      await choose(tester);
      final start = button(tester, 'Upload selected file').onPressed!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = button(tester, 'Confirm upload').onPressed!;
      confirm();
      confirm();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      start();
      expect(repository.uploads, hasLength(1));
      final request = repository.uploads.single;
      expect(request.actorId, fixtures.actorId);
      expect(identical(request.material, descriptor), isTrue);
      expect(identical(request.file, selector.result), isTrue);
      expect(button(tester, 'Choose file').onPressed, isNull);
      repository.rows = [row(file: request.file)];
      pending.complete(repository.rows.single);
      await tester.pumpAndSettle();
      expect(repository.lists, hasLength(2));
    },
  );

  testWidgets(
    'repository phases are real named stages with no invented percentage',
    (tester) async {
      final pending = Completer<MaterialFileUpload>();
      repository.onUpload = (_) => pending.future;
      await show(tester);
      await choose(tester);
      await send(tester, settle: false);
      for (final (phase, label) in [
        (MaterialFileUploadPhase.preparing, 'Preparing upload…'),
        (MaterialFileUploadPhase.transferring, 'Transferring file…'),
        (MaterialFileUploadPhase.checking, 'Checking upload…'),
      ]) {
        repository.phaseCallback!(phase);
        await tester.pump();
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('%'), findsNothing);
      pending.complete(row(file: selector.result));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'confirmed upload clears local request and waits for fresh history',
    (tester) async {
      final pending = Completer<List<MaterialFileUpload>>();
      repository.onUpload = (request) async {
        repository.onList = () => pending.future;
        return row(file: request.file);
      };
      await show(tester);
      await choose(tester);
      await send(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Synthetic notes.txt'), findsNothing);
      expect(find.text('Check upload'), findsNothing);
      expect(button(tester, 'Choose file').onPressed, isNull);
      pending.complete([row(name: 'Fresh history.txt')]);
      await tester.pumpAndSettle();
      expect(find.text('Fresh history.txt'), findsOneWidget);
      expect(button(tester, 'Choose file').onPressed, isNotNull);
      expect(repository.lists, hasLength(2));
    },
  );

  testWidgets(
    'failed history after confirmed upload cannot enable new upload',
    (tester) async {
      repository.onUpload = (request) async {
        repository.onList = () async => throw StateError('private');
        return row(file: request.file);
      };
      await show(tester);
      await choose(tester);
      await send(tester);
      expect(button(tester, 'Choose file').onPressed, isNull);
      expect(find.text('Check upload'), findsNothing);
      repository.onList = null;
      await tap(tester, 'Refresh uploads');
      expect(button(tester, 'Choose file').onPressed, isNotNull);
    },
  );

  testWidgets(
    'uncertain upload retains exact request; checking never resends and reserved stays locked',
    (tester) async {
      repository.onUpload = (_) async => throw StateError('private response');
      await show(tester);
      await choose(tester);
      await send(tester);
      final request = repository.uploads.single;
      expect(find.text('Bound upload request (read-only)'), findsOneWidget);
      expect(find.textContaining('private response'), findsNothing);
      expect(button(tester, 'Choose file').onPressed, isNull);
      expect(repository.checks, isEmpty);
      await tap(tester, 'Refresh uploads');
      expect(button(tester, 'Choose file').onPressed, isNull);
      repository.onCheck = (r) async => row(file: r.file, state: 'reserved');
      await tap(tester, 'Check upload');
      expect(identical(repository.checks.single, request), isTrue);
      expect(
        find.textContaining('Reservation exists; upload is not confirmed.'),
        findsOneWidget,
      );
      expect(repository.uploads, hasLength(1));
      repository.onCheck = (r) async {
        repository.rows = [row(file: r.file)];
        return repository.rows.single;
      };
      await tap(tester, 'Check upload');
      expect(identical(repository.checks.last, request), isTrue);
      expect(repository.uploads, hasLength(1));
      expect(find.text('Check upload'), findsNothing);
      expect(button(tester, 'Choose file').onPressed, isNotNull);
    },
  );

  testWidgets(
    'history freshness: uncertain upload cannot assert empty after clearing preexisting history',
    (tester) async {
      repository.rows = [row()];
      repository.onUpload = (_) async =>
          throw const MaterialFileUploadFailure();
      await show(tester);
      expect(find.text('Earlier notes.txt'), findsOneWidget);
      await choose(tester);
      await send(tester);
      expect(repository.lists, hasLength(1));
      expect(repository.uploads, hasLength(1));
      expect(find.text('Bound upload request (read-only)'), findsOneWidget);
      expect(
        find.textContaining('The upload may already exist.'),
        findsOneWidget,
      );
      expect(button(tester, 'Choose file').onPressed, isNull);
      expect(find.text('No uploads on this page.'), findsNothing);
    },
  );

  for (final reserved in [true, false]) {
    testWidgets(
      'history freshness: ${reserved ? 'reserved' : 'uncertain'} status check cannot assert empty without list refetch',
      (tester) async {
        repository.rows = [row()];
        repository.onUpload = (_) async =>
            throw const MaterialFileUploadFailure();
        await show(tester);
        await choose(tester);
        await send(tester);
        final request = repository.uploads.single;
        // Restore a genuine nonempty list independently of upload freshness.
        // This isolates the check path even after the upload path is corrected.
        await tap(tester, 'Refresh uploads');
        expect(find.text('Earlier notes.txt'), findsOneWidget);
        expect(repository.lists, hasLength(2));
        repository.onCheck = (captured) async {
          if (!reserved) throw const MaterialFileUploadFailure();
          return row(file: captured.file, state: 'reserved');
        };
        await tap(tester, 'Check upload');
        expect(repository.checks.single, same(request));
        expect(repository.uploads, hasLength(1));
        expect(repository.lists, hasLength(2));
        expect(find.text('Bound upload request (read-only)'), findsOneWidget);
        expect(button(tester, 'Choose file').onPressed, isNull);
        expect(
          find.textContaining(
            reserved
                ? 'Reservation exists; upload is not confirmed.'
                : 'Upload status remains uncertain.',
          ),
          findsOneWidget,
        );
        expect(find.text('No uploads on this page.'), findsNothing);
      },
    );
  }

  testWidgets(
    'history freshness: genuine empty refresh still shows empty and retains uncertain request',
    (tester) async {
      repository.rows = [row()];
      repository.onUpload = (_) async =>
          throw const MaterialFileUploadFailure();
      await show(tester);
      await choose(tester);
      await send(tester);
      final request = repository.uploads.single;
      final history = Completer<List<MaterialFileUpload>>();
      repository.onList = () => history.future;
      await tap(tester, 'Refresh uploads', settle: false);
      expect(repository.lists, hasLength(2));
      expect(find.text('No uploads on this page.'), findsNothing);
      history.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No uploads on this page.'), findsOneWidget);
      expect(find.text('Bound upload request (read-only)'), findsOneWidget);
      expect(button(tester, 'Choose file').onPressed, isNull);
      expect(repository.uploads.single, same(request));
      expect(repository.checks, isEmpty);
    },
  );

  testWidgets(
    'failed/mismatched check never forges success or unlocks choosing',
    (tester) async {
      repository.onUpload = (_) async =>
          throw const MaterialFileUploadFailure();
      await show(tester);
      await choose(tester);
      await send(tester);
      repository.onCheck = (_) async => throw StateError('protected error');
      await tap(tester, 'Check upload');
      expect(find.textContaining('protected error'), findsNothing);
      repository.onCheck = (r) async =>
          row(file: r.file, owner: fixtures.otherId);
      await tap(tester, 'Check upload');
      expect(button(tester, 'Choose file').onPressed, isNull);
      expect(
        find.text(
          'Uploaded — awaiting trusted validation. Not available to students.',
        ),
        findsNothing,
      );
      expect(repository.uploads, hasLength(1));
    },
  );

  for (final operation in ['list', 'upload', 'check']) {
    testWidgets(
      '$operation accessChanged clears filenames and all further controls',
      (tester) async {
        const denied = MaterialFileUploadFailure(accessChanged: true);
        if (operation == 'list') repository.onList = () async => throw denied;
        await show(tester);
        if (operation != 'list') {
          repository.onUpload = (_) async => throw (operation == 'upload'
              ? denied
              : const MaterialFileUploadFailure());
          await choose(tester);
          await send(tester);
          if (operation == 'check') {
            repository.onCheck = (_) async => throw denied;
            await tap(tester, 'Check upload');
          }
        }
        expect(find.text('Synthetic notes.txt'), findsNothing);
        expect(find.text('Check upload'), findsNothing);
        expect(find.text('Choose file'), findsNothing);
        expect(
          find.textContaining('Administrator access changed.'),
          findsOneWidget,
        );
      },
    );
  }

  for (final operation in ['list', 'select', 'upload', 'check']) {
    for (final loss in ['background', 'actor', 'dispose']) {
      testWidgets('late $operation after $loss cannot restore private state', (
        tester,
      ) async {
        final pendingRows = Completer<List<MaterialFileUpload>>();
        final pendingFile = Completer<SelectedMaterialFile?>();
        final pendingUpload = Completer<MaterialFileUpload>();
        if (operation == 'list') repository.onList = () => pendingRows.future;
        await show(tester, settle: operation != 'list');
        if (operation == 'select') {
          selector.onSelect = (_, _) => pendingFile.future;
          await tap(tester, 'Choose file', settle: false);
        }
        if (operation == 'upload' || operation == 'check') {
          await choose(tester);
          repository.onUpload = (_) => operation == 'upload'
              ? pendingUpload.future
              : Future.error(const MaterialFileUploadFailure());
          await send(tester, settle: operation == 'check');
          if (operation == 'check') {
            repository.onCheck = (_) => pendingUpload.future;
            await tap(tester, 'Check upload', settle: false);
          }
        }
        switch (loss) {
          case 'background':
            background(tester);
            resume(tester);
          case 'actor':
            repository.currentActorId = fixtures.otherId;
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        if (operation == 'list') pendingRows.complete([row()]);
        if (operation == 'select') pendingFile.complete(selected());
        if (operation == 'upload' || operation == 'check') {
          pendingUpload.complete(row(file: selected()));
        }
        if (repository.phaseCallback != null) {
          expect(
            () =>
                repository.phaseCallback!(MaterialFileUploadPhase.transferring),
            throwsA(
              isA<MaterialFileUploadFailure>().having(
                (error) => error.accessChanged,
                'accessChanged',
                isTrue,
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Synthetic notes.txt'), findsNothing);
        expect(find.text('Earlier notes.txt'), findsNothing);
        expect(repository.lists, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final resultFirst in [true, false]) {
    testWidgets(
      '${resultFirst ? 'result then resume' : 'resume then result'} native handoff survives both panel and AuthPanel observers',
      (tester) async {
        final result = Completer<SelectedMaterialFile?>();
        selector.onSelect = (auth, _) =>
            CourseImageSelection.runValue<SelectedMaterialFile>(auth, (
              returned,
            ) async {
              final file = await result.future;
              await returned();
              return file;
            });
        await show(tester, withAuthPanel: true);
        await tap(tester, 'Choose file', settle: false);
        expect(CourseImageSelection.active(auth), isTrue);
        background(tester);
        if (resultFirst) {
          result.complete(selected());
          await tester.pump();
          expect(find.text('Synthetic notes.txt'), findsNothing);
          resume(tester);
        } else {
          resume(tester);
          result.complete(selected());
        }
        await tester.pumpAndSettle();
        expect(find.text('Synthetic notes.txt'), findsOneWidget);
        expect(auth.stage, AuthStage.ready);
        expect(CourseImageSelection.active(auth), isFalse);
        expect(repository.uploads, isEmpty);
      },
    );
  }

  testWidgets(
    'background during delayed picker revalidation clears selection rather than installing while paused',
    (tester) async {
      final result = Completer<SelectedMaterialFile?>();
      selector.onSelect = (auth, _) =>
          CourseImageSelection.runValue<SelectedMaterialFile>(auth, (
            returned,
          ) async {
            final file = await result.future;
            await returned();
            return file;
          });
      await show(tester);
      await tap(tester, 'Choose file', settle: false);
      final access = Completer<AccessContext>();
      accounts.accessCompleter = access;
      result.complete(selected());
      await tester.pump();
      expect(CourseImageSelection.active(auth), isFalse);
      background(tester);
      access.complete(const AccessContext('admin', fixtures.actorId));
      await tester.pump();
      resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic notes.txt'), findsNothing);
      expect(find.text('Choose file'), findsNothing);
    },
  );

  testWidgets(
    'auth/device replacement invalidates even while picker handoff is active',
    (tester) async {
      final result = Completer<SelectedMaterialFile?>();
      selector.onSelect = (auth, _) =>
          CourseImageSelection.runValue<SelectedMaterialFile>(auth, (
            returned,
          ) async {
            final file = await result.future;
            await returned();
            return file;
          });
      await show(tester);
      await tap(tester, 'Choose file', settle: false);
      accounts.accessContext = const AccessContext('admin', fixtures.otherId);
      await tester.runAsync(() => auth.checkAccess());
      result.complete(selected());
      await tester.pumpAndSettle();
      expect(find.text('Synthetic notes.txt'), findsNothing);
      expect(find.text('Choose file'), findsNothing);
      expect(CourseImageSelection.active(auth), isFalse);
    },
  );

  testWidgets(
    'background invalidates owned confirmation before frame and rejects retained callback',
    (tester) async {
      await show(tester);
      await choose(tester);
      await tap(tester, 'Upload selected file');
      final callback = button(tester, 'Confirm upload').onPressed!;
      background(tester);
      resume(tester);
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Synthetic notes.txt'), findsNothing);
      expect(repository.uploads, isEmpty);
    },
  );

  testWidgets(
    'dependency replacement clears selection/dialog and rejects old callbacks',
    (tester) async {
      await show(tester);
      await choose(tester);
      await tap(tester, 'Upload selected file');
      final callback = button(tester, 'Confirm upload').onPressed!;
      final replacement = UploadPanelRepositoryFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: panel(repo: replacement)),
        ),
      );
      callback();
      await tester.pumpAndSettle();
      expect(repository.uploads, isEmpty);
      expect(replacement.uploads, isEmpty);
      expect(find.text('Synthetic notes.txt'), findsNothing);
      expect(replacement.lists, hasLength(1));
    },
  );

  testWidgets(
    'dirty Close and Back cancel safely and final close blocks same-frame retained upload',
    (tester) async {
      await show(tester);
      await choose(tester);
      final callback = button(tester, 'Upload selected file').onPressed!;
      await tap(tester, 'Close uploads');
      await tap(tester, 'Cancel');
      expect(closed, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, 'Discard and close');
      callback();
      expect(closed, 1);
      expect(repository.uploads, isEmpty);
      expect(find.text('Synthetic notes.txt'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: panel(key: UniqueKey())),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.lists, hasLength(2));
      expect(find.text('Synthetic notes.txt'), findsNothing);
    },
  );

  testWidgets(
    'uncertain close warns about existing upload and does not resend bytes',
    (tester) async {
      repository.onUpload = (_) async =>
          throw const MaterialFileUploadFailure();
      await show(tester);
      await choose(tester);
      await send(tester);
      await tap(tester, 'Close uploads');
      expect(
        find.textContaining('Any transmitted upload may already exist.'),
        findsOneWidget,
      );
      await tap(tester, 'Discard and close');
      expect(closed, 1);
      expect(repository.uploads, hasLength(1));
      expect(repository.checks, isEmpty);
      expect(find.text('Check upload'), findsNothing);
    },
  );

  testWidgets(
    'disposal removes only owned dialog and leaves unrelated route intact',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final nav = GlobalKey<NavigatorState>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, value, _) =>
                  value ? panel() : const Text('Parent screen'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await choose(tester);
      await tap(tester, 'Upload selected file');
      final callback = button(tester, 'Confirm upload').onPressed!;
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Unrelated route'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Parent screen'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.uploads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [2.0, 3.0]) {
    testWidgets(
      '320-wide ${scale}x long private names, keyboard inset and dialogs remain accessible',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          selector.result = selected(
            name: '${List.filled(28, 'Long ').join()}notes.txt',
          );
          await show(
            tester,
            size: const Size(320, 640),
            scale: scale,
            keyboard: 220,
          );
          await choose(tester);
          await tap(tester, 'Upload selected file');
          expect(tester.takeException(), isNull);
          expect(tester, meetsGuideline(labeledTapTargetGuideline));
          expect(tester, meetsGuideline(androidTapTargetGuideline));
          await tap(tester, 'Cancel');
          expect(repository.uploads, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
