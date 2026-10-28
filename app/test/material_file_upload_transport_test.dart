import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/content/material_file_upload_repository.dart';
import 'package:summit_academy/content/material_models.dart';
import 'package:summit_academy/content/supabase_material_file_upload_repository.dart';

import 'material_models_test.dart'
    show actorId, materialId, operationId, otherId, materialRow;

const switchedActor = '66666666-6666-4666-8666-666666666666';
const canary = 'PRIVATE_UPLOAD_CANARY';
const prepareRpc = '/rest/v1/rpc/prepare_material_file_upload';
const completeRpc = '/rest/v1/rpc/complete_material_file_upload';
const listRpc = '/rest/v1/rpc/list_material_file_uploads';
const objectPath = '$materialId/$otherId.pdf';
const binaryPath = '/storage/v1/object/material-upload-quarantine/$objectPath';

MaterialDescriptor descriptor({
  MaterialKind kind = MaterialKind.pdf,
  bool deleted = false,
}) => MaterialDescriptor.fromJson(materialRow(kind: kind, deleted: deleted));

SelectedMaterialFile selection({MaterialKind kind = MaterialKind.pdf}) =>
    SelectedMaterialFile.fromBytes(
      kind: kind,
      fileName: kind == MaterialKind.file
          ? 'Synthetic notes.txt'
          : 'Synthetic notes.pdf',
      bytes: utf8.encode(
        kind == MaterialKind.file
            ? 'Synthetic text\n'
            : '%PDF-1.7\nSynthetic fixture\n%%EOF\n',
      ),
    );

MaterialFileUploadRequest intent({
  String actor = actorId,
  MaterialKind kind = MaterialKind.pdf,
}) => MaterialFileUploadRequest(
  actorId: actor,
  material: descriptor(kind: kind),
  file: selection(kind: kind),
  operationId: operationId,
);

Map<String, dynamic> reservation({
  String state = 'reserved',
  String extension = 'pdf',
}) => {
  'asset_id': otherId,
  'path': '$materialId/$otherId.$extension',
  'state': state,
};

Map<String, dynamic> uploadRow({
  String state = 'uploaded',
  MaterialKind kind = MaterialKind.pdf,
}) {
  final file = selection(kind: kind);
  return {
    'asset_id': otherId,
    'material_id': materialId,
    'file_name': file.fileName,
    'content_type': file.contentType,
    'byte_length': file.byteLength,
    'state': state,
  };
}

Matcher uploadFailure({bool accessChanged = false}) =>
    isA<MaterialFileUploadFailure>()
        .having((error) => error.accessChanged, 'accessChanged', accessChanged)
        .having(
          (error) => error.toString(),
          'sanitized',
          isNot(contains(canary)),
        );

void main() {
  late SupabaseClient client;
  late SupabaseMaterialFileUploadRepository repository;
  late List<http.Request> requests;
  late Map<String, Object?> responses;
  Future<http.Response> Function(http.Request request)? override;

  Future<void> signIn(String actor, {int lifetime = 3600}) async {
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime}))).replaceAll('=', '')}.synthetic-signature',
        'token_type': 'bearer',
        'refresh_token': 'synthetic-refresh',
        'user': {
          'id': actor,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-21T00:00:00Z',
        },
      }),
    );
  }

  void expectMultipart(http.Request wire, SelectedMaterialFile file) {
    final contentType = wire.headers['content-type']!;
    expect(contentType, startsWith('multipart/form-data; boundary='));
    final boundary = contentType.split('boundary=').last;
    final parts = latin1.decode(wire.bodyBytes).split('--$boundary');
    expect(parts, hasLength(4));
    expect(parts.first, isEmpty);
    expect(parts.last, '--\r\n');
    expect(
      parts[1],
      '\r\ncontent-disposition: form-data; name="cacheControl"\r\n\r\n0\r\n',
    );
    final filePart = parts[2].split('\r\n\r\n');
    expect(filePart, hasLength(2));
    expect(filePart.first, contains('content-type: ${file.contentType}'));
    expect(
      filePart.first,
      contains('content-disposition: form-data; name=""; filename=""'),
    );
    expect(
      latin1.encode(filePart.last),
      orderedEquals([...file.bytes, 13, 10]),
    );
    expect(wire.headers['x-upsert'], 'false');
    expect(wire.url.toString(), isNot(contains(file.fileName)));
    expect(wire.headers.toString(), isNot(contains(file.fileName)));
    expect(latin1.decode(wire.bodyBytes), isNot(contains(file.fileName)));
  }

  http.Response reply(
    http.Request request,
    Object? value, {
    int status = 200,
  }) => http.Response(
    jsonEncode(value),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  List<http.Request> getTaskRequests() => requests
      .where(
        (request) =>
            request.url.path.startsWith('/rest/') ||
            request.url.path.startsWith('/storage/'),
      )
      .toList();

  setUp(() async {
    requests = [];
    override = null;
    responses = {
      prepareRpc: reservation(),
      binaryPath: {'Key': 'material-upload-quarantine/$objectPath'},
      completeRpc: uploadRow(),
      listRpc: [uploadRow()],
    };
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (override != null) return override!(request);
        return reply(request, responses[request.url.path] ?? {});
      }),
    );
    repository = SupabaseMaterialFileUploadRepository(client);
    await signIn(actorId);
  });
  tearDown(() => client.dispose());

  group('wire contract', () {
    test('inactive reconciliation guard prevents any HTTP request', () async {
      await expectLater(
        repository.checkUpload(
          intent(),
          ensureActive: () =>
              throw const MaterialFileUploadFailure(accessChanged: true),
        ),
        throwsA(uploadFailure(accessChanged: true)),
      );
      expect(getTaskRequests(), isEmpty);
    });

    test(
      'losing access during reconciliation preparation prevents finalization',
      () async {
        final started = Completer<void>();
        final pending = Completer<http.Response>();
        late http.Request preparation;
        var active = true;
        override = (request) async {
          if (request.url.path == prepareRpc) {
            preparation = request;
            started.complete();
            return pending.future;
          }
          return reply(request, responses[request.url.path]);
        };
        final result = repository.checkUpload(
          intent(),
          ensureActive: () {
            if (!active) {
              throw const MaterialFileUploadFailure(accessChanged: true);
            }
          },
        );
        final expectation = expectLater(
          result,
          throwsA(uploadFailure(accessChanged: true)),
        );
        await started.future;
        active = false;
        pending.complete(reply(preparation, reservation()));
        await expectation;
        expect(getTaskRequests().map((r) => r.url.path), [prepareRpc]);
      },
    );

    test('reserve, binary, finalize use exact paths and parameters with one pinned JWT', () async {
      final request = intent();
      final jwt = client.auth.currentSession!.accessToken;
      final headers = Map<String, String>.from(client.headers);
      final storageHeaders = Map<String, String>.from(client.storage.headers);
      final phases = <MaterialFileUploadPhase>[];
      final result = await repository.upload(request, onPhase: phases.add);
      expect(result.assetId, otherId);
      expect(result.state, MaterialFileUploadState.uploaded);
      expect(phases, MaterialFileUploadPhase.values);
      final wire = getTaskRequests();
      expect(wire.map((r) => r.url.path), [
        prepareRpc,
        binaryPath,
        completeRpc,
      ]);
      expect(wire.every((r) => r.method == 'POST'), isTrue);
      expect(
        wire.every((r) => r.headers['authorization'] == 'Bearer $jwt'),
        isTrue,
      );
      expect(jsonDecode(wire.first.body), {
        'p_material_id': materialId,
        'p_expected_revision': request.material.revision,
        'p_file_name': request.file.fileName,
        'p_content_type': 'application/pdf',
        'p_byte_length': request.file.byteLength,
        'p_operation_id': operationId,
      });
      expect(jsonDecode(wire.last.body), {'p_asset_id': otherId});
      for (final rpc in [wire.first, wire.last]) {
        final params = jsonDecode(rpc.body) as Map;
        expect(
          params.keys.any(
            (key) =>
                key.toString().contains('owner') ||
                key.toString().contains('actor'),
          ),
          isFalse,
        );
      }
      final binary = wire[1];
      expectMultipart(binary, request.file);
      expect(client.headers, headers);
      expect(client.storage.headers, storageHeaders);
    });

    test('TXT file maps to text/plain and deterministic txt object key', () async {
      final request = intent(kind: MaterialKind.file);
      responses[prepareRpc] = reservation(extension: 'txt');
      responses[completeRpc] = uploadRow(kind: MaterialKind.file);
      responses[binaryPath.replaceAll('.pdf', '.txt')] = {
        'Key':
            'material-upload-quarantine/${objectPath.replaceAll('.pdf', '.txt')}',
      };
      await repository.upload(request);
      final wire = getTaskRequests();
      expect(wire[1].url.path, binaryPath.replaceAll('.pdf', '.txt'));
      expectMultipart(wire[1], request.file);
      expect((jsonDecode(wire[0].body) as Map)['p_content_type'], 'text/plain');
    });

    test(
      'uploaded reservation skips binary and revalidates exact final status',
      () async {
        responses[prepareRpc] = reservation(state: 'uploaded');
        final phases = <MaterialFileUploadPhase>[];
        await repository.upload(intent(), onPhase: phases.add);
        expect(getTaskRequests().map((r) => r.url.path), [
          prepareRpc,
          completeRpc,
        ]);
        expect(phases, [
          MaterialFileUploadPhase.preparing,
          MaterialFileUploadPhase.checking,
        ]);
      },
    );

    for (final state in ['reserved', 'uploaded']) {
      test(
        'checkUpload $state reconciles same operation without binary resend',
        () async {
          responses[prepareRpc] = reservation(state: state);
          final request = intent();
          await repository.checkUpload(request);
          expect(getTaskRequests().map((r) => r.url.path), [
            prepareRpc,
            completeRpc,
          ]);
          expect(
            (jsonDecode(getTaskRequests().first.body) as Map)['p_operation_id'],
            operationId,
          );
          expect(
            getTaskRequests().every((r) => !r.url.path.startsWith('/storage/')),
            isTrue,
          );
        },
      );
    }

    test(
      'list is bounded read-only RPC, immutable and sends only material ID',
      () async {
        final result = await repository.listUploads(
          actorId: actorId,
          material: descriptor(),
        );
        expect(result.single.assetId, otherId);
        expect(getTaskRequests().single.url.path, listRpc);
        expect(jsonDecode(getTaskRequests().single.body), {
          'p_material_id': materialId,
        });
        expect(() => result.clear(), throwsUnsupportedError);
        responses[listRpc] = [];
        expect(
          await repository.listUploads(
            actorId: actorId,
            material: descriptor(),
          ),
          isEmpty,
        );
      },
    );

    test(
      'list permits PDF and TXT for generic file material, not TXT for PDF',
      () async {
        responses[listRpc] = [uploadRow(kind: MaterialKind.file)];
        expect(
          (await repository.listUploads(
            actorId: actorId,
            material: descriptor(kind: MaterialKind.file),
          )).single.contentType,
          'text/plain',
        );
        await expectLater(
          repository.listUploads(actorId: actorId, material: descriptor()),
          throwsA(uploadFailure()),
        );
      },
    );
  });

  group('strict transport projections', () {
    test('reserve rejects extra/missing fields, wrong types/state and unsafe object paths before binary', () async {
      for (final bad in <Object?>[
        null,
        [],
        {},
        {...reservation(), 'owner_id': canary},
        {...reservation()}..remove('state'),
        {...reservation(), 'asset_id': 'bad'},
        {...reservation(), 'asset_id': 7},
        {...reservation(), 'state': 'ready'},
        {...reservation(), 'state': null},
        {...reservation(), 'path': null},
        {...reservation(), 'path': '../$objectPath'},
        {...reservation(), 'path': '$otherId/$otherId.pdf'},
        {...reservation(), 'path': '$materialId/$otherId.txt'},
        {...reservation(), 'path': 'https://example.invalid/$objectPath'},
      ]) {
        requests.clear();
        responses[prepareRpc] = bad;
        await expectLater(
          repository.upload(intent()),
          throwsA(uploadFailure()),
        );
        expect(getTaskRequests().map((r) => r.url.path), [prepareRpc]);
      }
    });

    test(
      'completion must match every selected field and uploaded state',
      () async {
        for (final bad in <Object?>[
          null,
          [],
          {},
          {...uploadRow(), 'path': canary},
          {...uploadRow()}..remove('state'),
          {...uploadRow(), 'asset_id': operationId},
          {...uploadRow(), 'material_id': otherId},
          {...uploadRow(), 'file_name': 'Different.pdf'},
          {...uploadRow(kind: MaterialKind.file)},
          {...uploadRow(), 'byte_length': selection().byteLength + 1},
          {...uploadRow(), 'state': 'reserved'},
          {...uploadRow(), 'state': 'ready'},
        ]) {
          requests.clear();
          responses[completeRpc] = bad;
          await expectLater(
            repository.upload(intent()),
            throwsA(uploadFailure()),
          );
          expect(getTaskRequests(), hasLength(3));
        }
      },
    );

    test('list rejects malformed envelopes, over20, duplicates, wrong entity and MIME', () async {
      for (final bad in <Object?>[
        null,
        {},
        {'items': []},
        [null],
        List.generate(21, (_) => uploadRow()),
        [
          uploadRow(),
          {...uploadRow(), 'asset_id': otherId.toUpperCase()},
        ],
        [
          {...uploadRow(), 'material_id': operationId},
        ],
        [
          {...uploadRow(), 'content_type': 'image/png'},
        ],
        [
          {...uploadRow(), 'state': 'ready'},
        ],
        [
          {...uploadRow(), 'path': canary},
        ],
      ]) {
        requests.clear();
        responses[listRpc] = bad;
        await expectLater(
          repository.listUploads(actorId: actorId, material: descriptor()),
          throwsA(uploadFailure()),
        );
        expect(getTaskRequests(), hasLength(1));
      }
      responses[listRpc] = List.generate(
        20,
        (i) => {
          ...uploadRow(),
          'asset_id':
              '77777777-7777-4777-8777-${i.toString().padLeft(12, '0')}',
        },
      );
      expect(
        await repository.listUploads(actorId: actorId, material: descriptor()),
        hasLength(20),
      );
    });
  });

  group('actor boundaries', () {
    for (final phase in [prepareRpc, binaryPath, completeRpc]) {
      for (final change in ['switch', 'A-B-A', 'signout']) {
        test(
          '$change while $phase is pending rejects reply and starts no following phase',
          () async {
            final blocked = Completer<http.Response>();
            final reached = Completer<http.Request>();
            override = (request) async {
              if (request.url.path == phase) {
                reached.complete(request);
                return blocked.future;
              }
              return reply(request, responses[request.url.path] ?? {});
            };
            final token = client.auth.currentSession!.accessToken;
            final assertion = expectLater(
              repository.upload(intent()),
              throwsA(uploadFailure(accessChanged: true)),
            );
            final wire = await reached.future;
            if (change == 'signout') {
              await client.auth.signOut(scope: SignOutScope.local);
            } else {
              await signIn(switchedActor);
              if (change == 'A-B-A') await signIn(actorId);
            }
            blocked.complete(reply(wire, responses[phase]));
            await assertion;
            final task = getTaskRequests();
            expect(
              task.map((r) => r.url.path),
              [
                prepareRpc,
                binaryPath,
                completeRpc,
              ].take([prepareRpc, binaryPath, completeRpc].indexOf(phase) + 1),
            );
            expect(
              task.every((r) => r.headers['authorization'] == 'Bearer $token'),
              isTrue,
            );
          },
        );
      }
    }

    for (final phase in MaterialFileUploadPhase.values) {
      test(
        'identity changed synchronously by $phase callback blocks its network phase',
        () async {
          final assertion = expectLater(
            repository.upload(
              intent(),
              onPhase: (current) {
                if (current == phase) {
                  unawaited(client.auth.signOut(scope: SignOutScope.local));
                }
              },
            ),
            throwsA(uploadFailure(accessChanged: true)),
          );
          await assertion;
          expect(getTaskRequests(), hasLength(phase.index));
        },
      );
    }

    test('same-actor refresh keeps original JWT across all phases and leaves fresh global headers alone', () async {
      final token = client.auth.currentSession!.accessToken;
      override = (request) async {
        if (request.url.path == prepareRpc) {
          await signIn(actorId, lifetime: 7200);
        }
        return reply(request, responses[request.url.path] ?? {});
      };
      await repository.upload(intent());
      expect(client.auth.currentSession!.accessToken, isNot(token));
      expect(
        getTaskRequests().every(
          (r) => r.headers['authorization'] == 'Bearer $token',
        ),
        isTrue,
      );
      expect(
        client.storage.from('unrelated').headers['Authorization'],
        isNot('Bearer $token'),
      );
    });

    for (final action in ['upload', 'check', 'list']) {
      Future<Object?> run() => switch (action) {
        'upload' => repository.upload(intent()),
        'check' => repository.checkUpload(intent()),
        _ => repository.listUploads(actorId: actorId, material: descriptor()),
      };
      test(
        '$action rejects absent, expired and mismatched actor before network',
        () async {
          await signIn(switchedActor);
          await expectLater(run(), throwsA(uploadFailure(accessChanged: true)));
          await signIn(actorId, lifetime: -100);
          await expectLater(run(), throwsA(uploadFailure(accessChanged: true)));
          await client.auth.signOut(scope: SignOutScope.local);
          requests.clear();
          await expectLater(run(), throwsA(uploadFailure(accessChanged: true)));
          expect(getTaskRequests(), isEmpty);
        },
      );
    }

    test('delayed list A-B-A cannot return old metadata', () async {
      final reached = Completer<http.Request>();
      final blocked = Completer<http.Response>();
      override = (request) {
        reached.complete(request);
        return blocked.future;
      };
      final assertion = expectLater(
        repository.listUploads(actorId: actorId, material: descriptor()),
        throwsA(uploadFailure(accessChanged: true)),
      );
      final request = await reached.future;
      await signIn(switchedActor);
      await signIn(actorId);
      blocked.complete(reply(request, [uploadRow()]));
      await assertion;
      expect(getTaskRequests(), hasLength(1));
    });

    test('custom-token-only client cannot upload or reconcile without GoTrue identity', () async {
      var calls = 0;
      final isolated = SupabaseClient(
        'https://example.test',
        'sb_publishable_test',
        accessToken: () async => canary,
        httpClient: MockClient((request) async {
          calls++;
          return reply(request, {});
        }),
      );
      addTearDown(isolated.dispose);
      final isolatedRepository = SupabaseMaterialFileUploadRepository(isolated);
      await expectLater(
        isolatedRepository.upload(intent()),
        throwsA(uploadFailure(accessChanged: true)),
      );
      await expectLater(
        isolatedRepository.checkUpload(intent()),
        throwsA(uploadFailure(accessChanged: true)),
      );
      expect(calls, 0);
    });
  });

  group('fail closed without retries', () {
    for (final phase in [prepareRpc, binaryPath, completeRpc]) {
      for (final error in ['network', 'server', 'json']) {
        test(
          '$phase $error failure is sanitized, stops and never retries',
          () async {
            override = (request) async {
              if (request.url.path == phase) {
                // Use the SDK's retry-eligible exception type: StateError
                // would not demonstrate that retryAttempts: 0 is effective.
                if (error == 'network') throw http.ClientException(canary);
                if (error == 'json') {
                  return http.Response(
                    '{"$canary":',
                    200,
                    request: request,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return reply(request, {
                  'code': '42501',
                  'message': canary,
                  'details': canary,
                  'statusCode': '403',
                  'error': canary,
                }, status: 403);
              }
              return reply(request, responses[request.url.path] ?? {});
            };
            await expectLater(
              repository.upload(intent()),
              throwsA(uploadFailure()),
            );
            expect(
              getTaskRequests(),
              hasLength(
                [prepareRpc, binaryPath, completeRpc].indexOf(phase) + 1,
              ),
            );
          },
        );
      }
    }

    for (final phase in [prepareRpc, completeRpc]) {
      test(
        'backend access-required at $phase marks accessChanged and sends no later phase',
        () async {
          override = (request) async => request.url.path == phase
              ? reply(request, {
                  'code': '42501',
                  'message': 'material_upload_access_required',
                  'details': canary,
                }, status: 403)
              : reply(request, responses[request.url.path] ?? {});
          await expectLater(
            repository.upload(intent()),
            throwsA(uploadFailure(accessChanged: true)),
          );
          expect(getTaskRequests(), hasLength(phase == prepareRpc ? 1 : 3));
        },
      );
    }

    for (final phase in [prepareRpc, binaryPath, completeRpc]) {
      testWidgets(
        '$phase timeout rejects late completion without another phase or binary resend',
        (tester) async {
          repository = SupabaseMaterialFileUploadRepository(
            client,
            timeout: const Duration(milliseconds: 50),
          );
          final blocked = Completer<http.Response>();
          http.Request? pendingRequest;
          override = (request) async {
            if (request.url.path == phase) {
              pendingRequest = request;
              return blocked.future;
            }
            return reply(request, responses[request.url.path] ?? {});
          };
          Object? failure;
          var completed = false;
          unawaited(
            repository
                .upload(intent())
                .then<void>(
                  (_) {
                    completed = true;
                  },
                  onError: (Object error) {
                    failure = error;
                    completed = true;
                  },
                ),
          );
          await tester.pump();
          expect(pendingRequest, isNotNull);
          await tester.pump(
            phase == binaryPath
                ? const Duration(minutes: 2, seconds: 1)
                : const Duration(milliseconds: 100),
          );
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          expect(completed, isTrue);
          expect(failure, uploadFailure());
          final before = getTaskRequests().length;
          blocked.complete(reply(pendingRequest!, responses[phase]));
          await tester.pump();
          expect(getTaskRequests(), hasLength(before));
          expect(
            before,
            [prepareRpc, binaryPath, completeRpc].indexOf(phase) + 1,
          );
        },
      );
    }

    test('failed binary can only reconcile explicitly with same operation and no second transfer', () async {
      override = (request) async {
        if (request.url.path == binaryPath) throw StateError(canary);
        return reply(request, responses[request.url.path] ?? {});
      };
      final request = intent();
      await expectLater(repository.upload(request), throwsA(uploadFailure()));
      override = null;
      await repository.checkUpload(request);
      expect(getTaskRequests().map((r) => r.url.path), [
        prepareRpc,
        binaryPath,
        prepareRpc,
        completeRpc,
      ]);
      expect(
        jsonDecode(getTaskRequests()[0].body),
        jsonDecode(getTaskRequests()[2].body),
      );
    });
  });

  group('pure upload status and immutable request', () {
    test('request guards invalid descriptor IDs and revision bounds without JSON parsing', () {
      final valid = descriptor();
      MaterialDescriptor unchecked({
        String id = materialId,
        String? session,
        int revision = 1,
      }) => MaterialDescriptor(
        id: id,
        sessionId: session ?? valid.sessionId,
        kind: valid.kind,
        title: valid.title,
        summary: valid.summary,
        position: valid.position,
        status: valid.status,
        revision: revision,
        createdBy: valid.createdBy,
        createdAt: valid.createdAt,
        updatedAt: valid.updatedAt,
        deletedAt: null,
      );
      for (final material in [
        unchecked(id: 'bad'),
        unchecked(session: 'bad'),
        unchecked(revision: 0),
        unchecked(revision: maxMaterialRevision + 1),
      ]) {
        expect(
          () => MaterialFileUploadRequest(
            actorId: actorId,
            material: material,
            file: selection(),
            operationId: operationId,
          ),
          throwsA(uploadFailure()),
        );
      }
      expect(getTaskRequests(), isEmpty);
    });

    test('fixed failure text never reveals token, filename or file body', () {
      final jwt = client.auth.currentSession!.accessToken;
      for (final changed in [false, true]) {
        final failure = MaterialFileUploadFailure(accessChanged: changed);
        expect(failure.toString(), failure.message);
        expect(failure.toString(), isNot(contains(jwt)));
        expect(failure.toString(), isNot(contains(selection().fileName)));
        expect(failure.toString(), isNot(contains('Synthetic fixture')));
      }
    });

    test('exact six-field model accepts only reserved/uploaded and bounded PDF/TXT metadata', () {
      for (final state in ['reserved', 'uploaded']) {
        for (final kind in [MaterialKind.pdf, MaterialKind.file]) {
          final row = MaterialFileUpload.fromJson(
            uploadRow(state: state, kind: kind),
          );
          expect(row.materialId, materialId);
          expect(row.state.name, state);
        }
      }
      for (final size in [1, maxSelectedMaterialFileBytes]) {
        expect(
          MaterialFileUpload.fromJson({...uploadRow(), 'byte_length': size})
              .byteLength,
          size,
        );
      }
    });

    test('status rejects missing/extra fields, unknown states, noninteger sizes and invalid names/MIME', () {
      final invalid = <Object?>[
        null,
        [],
        {},
        for (final key in uploadRow().keys) {...uploadRow()}..remove(key),
        {...uploadRow(), 'signed_url': canary},
        {...uploadRow(), 'state': 'clean'},
        {...uploadRow(), 'asset_id': 'bad'},
        {...uploadRow(), 'material_id': null},
        for (final size in [
          0,
          -1,
          maxSelectedMaterialFileBytes + 1,
          1.0,
          '1',
          null,
          true,
        ])
          {...uploadRow(), 'byte_length': size},
        for (final name in [
          '',
          '.pdf',
          ' .pdf',
          'x.exe',
          'x.pdf\n',
          'folder/x.pdf',
          'folder\\x.pdf',
          'x\u007f.pdf',
          '${'x' * 161}.pdf',
        ])
          {...uploadRow(), 'file_name': name},
        {...uploadRow(), 'content_type': 'text/plain'},
        {...uploadRow(), 'content_type': 'application/octet-stream'},
      ];
      for (final value in invalid) {
        expect(
          () => MaterialFileUpload.fromJson(value),
          throwsA(uploadFailure()),
        );
      }
    });

    test('request rejects wrong kind/deleted/invalid actor or operation without network', () {
      for (final kind in [
        MaterialKind.video,
        MaterialKind.link,
        MaterialKind.assignment,
        MaterialKind.file,
      ]) {
        expect(
          () => MaterialFileUploadRequest(
            actorId: actorId,
            material: descriptor(kind: kind),
            file: selection(),
            operationId: operationId,
          ),
          throwsA(uploadFailure()),
        );
      }
      expect(
        () => MaterialFileUploadRequest(
          actorId: actorId,
          material: descriptor(deleted: true),
          file: selection(),
        ),
        throwsA(uploadFailure()),
      );
      for (final value in ['', 'bad', '$actorId\n']) {
        expect(() => intent(actor: value), throwsA(uploadFailure()));
        expect(
          () => MaterialFileUploadRequest(
            actorId: actorId,
            material: descriptor(),
            file: selection(),
            operationId: value,
          ),
          throwsA(uploadFailure()),
        );
      }
      expect(getTaskRequests(), isEmpty);
    });

    test(
      'request captures normalized actor/operation and immutable owned bytes',
      () {
        final request = MaterialFileUploadRequest(
          actorId: actorId.toUpperCase(),
          material: descriptor(),
          file: selection(),
          operationId: operationId.toUpperCase(),
        );
        expect(request.actorId, actorId);
        expect(request.operationId, operationId);
        expect(() => request.file.bytes[0] = 0, throwsUnsupportedError);
        expect(request.toString(), isNot(contains('Synthetic notes')));
        expect(
          MaterialFileUpload.fromJson(uploadRow()).toString(),
          isNot(contains('Synthetic notes')),
        );
      },
    );
  });
}
