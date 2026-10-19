import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/content/material_repository.dart';
import 'package:summit_academy/content/supabase_material_repository.dart';

import 'material_models_test.dart';

void main() {
  late SupabaseClient client;
  late SupabaseMaterialRepository repository;
  late List<http.Request> requests;
  late Object? response;
  int status = 200;
  Object? networkError;
  Completer<http.Response>? pending;
  Future<void> signInAs(String id) => client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic-signature',
      'token_type': 'bearer',
      'refresh_token': 'synthetic-refresh-token',
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-19T03:00:00Z',
      },
    }),
  );
  setUp(() async {
    requests = [];
    status = 200;
    response = materialRow();
    networkError = null;
    pending = null;
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (networkError != null) throw networkError!;
        if (pending != null) return pending!.future;
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repository = SupabaseMaterialRepository(client);
    await signInAs(actorId);
  });
  tearDown(() async {
    await client.dispose();
  });
  MaterialDescriptor expected({
    int revision = 1,
    bool deleted = false,
    MaterialKind kind = MaterialKind.assignment,
  }) => MaterialDescriptor.fromJson(
    materialRow(revision: revision, deleted: deleted, kind: kind),
  );
  Matcher failure(MaterialFailureKind kind, {bool? refresh}) =>
      isA<MaterialFailure>()
          .having((e) => e.kind, 'kind', kind)
          .having((e) => e.requiresRefresh, 'refresh', refresh ?? anything)
          .having((e) => e.toString(), 'sanitized', isNot(contains('CANARY')));

  Future<MaterialMutationResult> Function() retainedMutation(
    String action, {
    String origin = actorId,
  }) {
    switch (action) {
      case 'create':
        final request = CreateMaterialRequest(
          actorId: origin,
          sessionId: sessionId,
          draft: materialDraft(),
        );
        return () => repository.createMaterial(request);
      case 'update':
        final request = UpdateMaterialRequest(
          actorId: origin,
          expected: expected(),
          draft: materialDraft(),
        );
        return () => repository.updateMaterial(request);
      case 'delete':
        final request = MaterialLifecycleRequest(
          actorId: origin,
          expected: expected(),
        );
        return () => repository.deleteMaterial(request);
      case 'restore':
        final request = MaterialLifecycleRequest(
          actorId: origin,
          expected: expected(deleted: true),
        );
        return () => repository.restoreMaterial(request);
      default:
        throw StateError('Unknown test action');
    }
  }

  test(
    'currentActorId reads live identity without network and clears on sign-out',
    () async {
      expect(repository.currentActorId, actorId);
      expect(requests, isEmpty);
      await signInAs(otherId);
      expect(repository.currentActorId, otherId);
      expect(requests, isEmpty);
      await client.auth.signOut(scope: SignOutScope.local);
      final count = requests.length;
      expect(repository.currentActorId, isNull);
      expect(requests, hasLength(count));
    },
  );
  test('currentActorId fails safely for a custom-token client without GoTrue identity', () async {
    final tokenClient = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      accessToken: () async => 'synthetic-token',
      httpClient: MockClient((request) async {
        fail('The identity getter must not make a network request');
      }),
    );
    addTearDown(tokenClient.dispose);
    expect(SupabaseMaterialRepository(tokenClient).currentActorId, isNull);
  });

  Map<String, dynamic> mutationRow(String action) => materialRow(
    revision: action == 'create' ? 1 : 2,
    deleted: action == 'delete',
  );

  test(
    'never-authenticated client blocks every mutation with no network',
    () async {
      var calls = 0;
      final anonymous = SupabaseClient(
        'https://example.test',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('{}', 200, request: request);
        }),
      );
      addTearDown(anonymous.dispose);
      repository = SupabaseMaterialRepository(anonymous);
      for (final action in ['create', 'update', 'delete', 'restore']) {
        await expectLater(
          retainedMutation(action)(),
          throwsA(failure(MaterialFailureKind.accessDenied, refresh: true)),
        );
      }
      expect(calls, 0);
    },
  );
  test('malformed origin IDs are rejected before any RPC', () async {
    for (final action in ['create', 'update', 'delete', 'restore']) {
      await expectLater(
        retainedMutation(action, origin: 'bad')(),
        throwsA(failure(MaterialFailureKind.invalidInput, refresh: false)),
      );
    }
    expect(requests, isEmpty);
  });
  test(
    'create confirms origin creator and does not change shared client headers',
    () async {
      final before = {...client.headers};
      response = {...materialRow(), 'created_by': otherId};
      await expectLater(
        retainedMutation('create')(),
        throwsA(failure(MaterialFailureKind.uncertain, refresh: true)),
      );
      expect(client.headers, before);
      expect(
        client.rest.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );
  for (final action in ['create', 'update', 'delete', 'restore']) {
    test(
      '$action cross-actor retained retry is blocked before RPC; same actor retry stays exact',
      () async {
        final change = retainedMutation(action);
        response = mutationRow(action);
        await change();
        final firstBody = requests.single.body;
        await signInAs(otherId);
        await expectLater(
          change(),
          throwsA(failure(MaterialFailureKind.actorMismatch, refresh: true)),
        );
        expect(requests, hasLength(1));
        // Reconstructing the repository must not silently rebind the retained request.
        repository = SupabaseMaterialRepository(client);
        await expectLater(
          change(),
          throwsA(failure(MaterialFailureKind.actorMismatch, refresh: true)),
        );
        expect(requests, hasLength(1));
        await signInAs(actorId);
        final retry = await change();
        expect(retry.requiresRefresh, isTrue);
        expect(requests, hasLength(2));
        expect(requests.last.body, firstBody);
      },
    );
    test(
      '$action signed-out identity is blocked before any mutation network',
      () async {
        final change = retainedMutation(action);
        await client.auth.signOut(scope: SignOutScope.local);
        requests.clear();
        expect(client.auth.currentUser, isNull);
        expect(client.auth.currentSession, isNull);
        await expectLater(
          change(),
          throwsA(failure(MaterialFailureKind.accessDenied, refresh: true)),
        );
        expect(requests, isEmpty);
      },
    );
    for (final signOut in [false, true]) {
      test(
        '$action discards response after ${signOut ? 'sign-out' : 'actor change'} with sanitized refresh failure',
        () async {
          final change = retainedMutation(action);
          pending = Completer<http.Response>();
          final result = change();
          final assertion = expectLater(
            result,
            throwsA(
              failure(
                signOut
                    ? MaterialFailureKind.accessDenied
                    : MaterialFailureKind.actorMismatch,
                refresh: true,
              ),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(requests, hasLength(1));
          final originalRequest = requests.single;
          // Do not delay the test fixture's logout HTTP request on the pending RPC.
          final rpcPending = pending!;
          pending = null;
          if (signOut) {
            await client.auth.signOut(scope: SignOutScope.local);
          } else {
            await signInAs(otherId);
          }
          rpcPending.complete(
            http.Response(
              jsonEncode(mutationRow(action)),
              200,
              request: originalRequest,
              headers: {'content-type': 'application/json'},
            ),
          );
          await assertion;
          expect(
            requests.where((r) => r.url.path.startsWith('/rest/')),
            hasLength(1),
          );
        },
      );
    }
  }
  test('create timeout under A cannot be retried under B, but exact retry under A recovers cached snapshot', () async {
    repository = SupabaseMaterialRepository(
      client,
      timeout: const Duration(milliseconds: 20),
    );
    final change = retainedMutation('create');
    final tokenA = client.auth.currentSession!.accessToken;
    pending = Completer<http.Response>();
    await expectLater(
      change(),
      throwsA(failure(MaterialFailureKind.uncertain, refresh: true)),
    );
    final original = requests.single;
    expect(original.headers['authorization'], 'Bearer $tokenA');
    await signInAs(otherId);
    await expectLater(
      change(),
      throwsA(failure(MaterialFailureKind.actorMismatch, refresh: true)),
    );
    expect(requests, hasLength(1));
    pending!.complete(
      http.Response(
        jsonEncode(materialRow()),
        200,
        request: original,
        headers: {'content-type': 'application/json'},
      ),
    );
    pending = null;
    await Future<void>.delayed(Duration.zero);
    await signInAs(actorId);
    final retry = await change();
    expect(retry.snapshot.id, materialId);
    expect(retry.requiresRefresh, isTrue);
    expect(requests, hasLength(2));
    expect(requests.last.body, original.body);
  });
  test(
    'token pinned to checked actor across SDK asynchronous token selection',
    () async {
      final tokenA = client.auth.currentSession!.accessToken;
      pending = Completer<http.Response>();
      final change = retainedMutation('create');
      final result = change();
      final assertion = expectLater(
        result,
        throwsA(failure(MaterialFailureKind.actorMismatch, refresh: true)),
      );
      await signInAs(otherId);
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      expect(requests.single.headers['authorization'], 'Bearer $tokenA');
      expect(client.auth.currentSession!.accessToken, isNot(tokenA));
      pending!.complete(
        http.Response(
          jsonEncode(materialRow()),
          200,
          request: requests.single,
          headers: {'content-type': 'application/json'},
        ),
      );
      await assertion;
    },
  );
  for (final action in ['update', 'delete', 'restore']) {
    test('admin B may $action material authored by admin A', () async {
      await signInAs(otherId);
      response = mutationRow(action);
      final result = await retainedMutation(action, origin: otherId)();
      expect(result.snapshot.createdBy, actorId);
      expect(result.requiresRefresh, isTrue);
      expect(requests, hasLength(1));
    });
  }

  test('list uses descriptor allowlist, immutable session filter and 20-row ordered offsets', () async {
    response = [materialRow()];
    final rows = await repository.listMaterials(sessionId, offset: 20);
    expect(rows.single.id, materialId);
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/rest/v1/session_materials');
    expect(request.url.queryParameters, {
      'select': materialDescriptorFields,
      'session_id': 'eq.$sessionId',
      'deleted_at': 'is.null',
      'order': 'position.asc.nullslast,id.asc.nullslast',
      'offset': '20',
      'limit': '20',
    });
    expect(request.url.queryParameters['select'], isNot(contains('*')));
    expect(() => rows.clear(), throwsUnsupportedError);
    response = [materialRow(deleted: true)];
    expect(
      (await repository.listMaterials(
        sessionId,
        includeDeleted: true,
      )).single.isDeleted,
      isTrue,
    );
    expect(requests.last.url.queryParameters, isNot(contains('deleted_at')));
  });
  test(
    '20 plus next page with tied positions remains deterministically ordered',
    () async {
      Map<String, dynamic> row(int n) => {
        ...materialRow(),
        'id': '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}',
      };
      response = List.generate(20, (i) => row(i + 1));
      expect(await repository.listMaterials(sessionId), hasLength(20));
      response = List.generate(5, (i) => row(i + 21));
      expect(
        await repository.listMaterials(sessionId, offset: 20),
        hasLength(5),
      );
      response = [];
      expect(await repository.listMaterials(sessionId, offset: 40), isEmpty);
    },
  );
  for (final invalid in [
    'wrong-session',
    'deleted',
    'duplicates',
    'unordered',
    'overpage',
    'protected',
    'malformed',
  ]) {
    test('list rejects $invalid response', () async {
      response = switch (invalid) {
        'wrong-session' => [
          {...materialRow(), 'session_id': otherId},
        ],
        'deleted' => [materialRow(deleted: true)],
        'duplicates' => [materialRow(), materialRow()],
        'unordered' => [
          {...materialRow(), 'id': otherId},
          materialRow(),
        ],
        'overpage' => List.generate(21, (_) => materialRow()),
        'protected' => [
          {...materialRow(), 'body_text': privateBody},
        ],
        _ => [
          {'id': materialId},
        ],
      };
      await expectLater(
        repository.listMaterials(sessionId),
        throwsA(failure(MaterialFailureKind.requestFailed)),
      );
    });
  }
  test(
    'detail calls only admin RPC and accepts a newer deleted recovery snapshot',
    () async {
      response = {
        'descriptor': materialRow(revision: 4, deleted: true),
        'body_text': privateBody,
        'target_url': null,
      };
      final detail = await repository.getAdminDetail(expected());
      expect(detail.descriptor.revision, 4);
      expect(detail.descriptor.isDeleted, isTrue);
      expect(detail.payload, isA<AssignmentMaterialPayload>());
      expect(detail.payload.bodyText, privateBody);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/get_admin_material_detail',
      );
      expect(jsonDecode(requests.single.body), {'p_material_id': materialId});
    },
  );
  for (final field in [
    'id',
    'session_id',
    'kind',
    'created_by',
    'created_at',
    'revision',
  ]) {
    test('detail rejects changed $field or older revision', () async {
      final row = {
        ...materialRow(revision: 2),
        field: switch (field) {
          'kind' => 'link',
          'created_at' => '2026-10-19T02:00:00Z',
          'revision' => 1,
          _ => otherId,
        },
      };
      response = {'descriptor': row, 'body_text': '', 'target_url': null};
      await expectLater(
        repository.getAdminDetail(expected(revision: 2)),
        throwsA(failure(MaterialFailureKind.requestFailed)),
      );
    });
  }
  for (final kind in MaterialKind.values) {
    test(
      'create ${kind.name} sends exact signature and accepts draft revision one only',
      () async {
        response = materialRow(kind: kind);
        final draft = materialDraft(kind: kind);
        final request = CreateMaterialRequest(
          actorId: actorId,
          sessionId: sessionId,
          draft: draft,
        );
        final result = await repository.createMaterial(request);
        expect(result.requiresRefresh, isTrue);
        expect(result.snapshot.kind, kind);
        expect(
          requests.single.url.path,
          '/rest/v1/rpc/create_session_material',
        );
        expect(jsonDecode(requests.single.body), {
          'p_session_id': sessionId,
          'p_kind': kind.name,
          'p_title': 'Material',
          'p_summary': 'Catalog summary',
          'p_position': 0,
          'p_body_text': kind == MaterialKind.assignment ? privateBody : '',
          'p_target_url': kind == MaterialKind.link ? privateTarget : null,
          'p_operation_id': request.operationId,
        });
        expect(result.toString(), isNot(contains('CANARY')));
        expect(result.snapshot.toString(), isNot(contains('CANARY')));
      },
    );
  }
  test('create exact retry reuses generated operation and returns historical snapshot requiring refresh', () async {
    final request = CreateMaterialRequest(
      actorId: actorId,
      sessionId: sessionId,
      draft: materialDraft(),
    );
    final first = await repository.createMaterial(request);
    // Even if current server state has advanced, exact replay returns original rev 1.
    final retry = await repository.createMaterial(request);
    expect(first.snapshot.revision, 1);
    expect(retry.snapshot.revision, 1);
    expect(retry.requiresRefresh, isTrue);
    expect(requests, hasLength(2));
    expect(requests[0].body, requests[1].body);
  });
  test('update complete replacement carries only editable fields, retained operation and expected revision', () async {
    response = materialRow(revision: 8, status: ContentStatus.published);
    final request = UpdateMaterialRequest(
      actorId: actorId,
      expected: expected(revision: 7),
      draft: materialDraft(status: ContentStatus.published),
    );
    final result = await repository.updateMaterial(request);
    expect(result.snapshot.revision, 8);
    expect(result.requiresRefresh, isTrue);
    expect(requests.single.url.path, '/rest/v1/rpc/update_session_material');
    expect(jsonDecode(requests.single.body), {
      'p_material_id': materialId,
      'p_expected_revision': 7,
      'p_title': 'Material',
      'p_summary': 'Catalog summary',
      'p_position': 0,
      'p_status': 'published',
      'p_body_text': privateBody,
      'p_target_url': null,
      'p_operation_id': request.operationId,
    });
    await repository.updateMaterial(request);
    expect(requests[0].body, requests[1].body);
  });
  for (final restore in [false, true]) {
    test(
      '${restore ? 'restore' : 'delete'} uses revision RPC and checks resulting lifecycle',
      () async {
        response = materialRow(revision: 6, deleted: !restore);
        final request = MaterialLifecycleRequest(
          actorId: actorId,
          expected: expected(revision: 5, deleted: restore),
        );
        final result = restore
            ? await repository.restoreMaterial(request)
            : await repository.deleteMaterial(request);
        expect(result.snapshot.isDeleted, !restore);
        expect(
          result.snapshot.status,
          restore ? ContentStatus.draft : ContentStatus.archived,
        );
        expect(result.requiresRefresh, isTrue);
        expect(
          requests.single.url.path,
          '/rest/v1/rpc/${restore ? 'restore' : 'delete'}_session_material',
        );
        expect(jsonDecode(requests.single.body), {
          'p_material_id': materialId,
          'p_expected_revision': 5,
          'p_operation_id': request.operationId,
        });
      },
    );
  }
  for (final action in ['create', 'update', 'delete', 'restore']) {
    for (final invalid in [
      'id',
      'session',
      'kind',
      'revision',
      'lifecycle',
      'metadata',
      'protected',
    ]) {
      if (action == 'create' && invalid == 'id') {
        continue; // Create allocates its server ID.
      }
      test(
        '$action rejects unconfirmed $invalid result without another write',
        () async {
          var row = materialRow(
            revision: action == 'create' ? 1 : 2,
            deleted: action == 'delete',
          );
          row = switch (invalid) {
            'id' => {...row, 'id': otherId},
            'session' => {...row, 'session_id': otherId},
            'kind' => {...row, 'kind': 'link'},
            'revision' => {...row, 'revision': 3},
            'lifecycle' => {...row, 'status': 'published', 'deleted_at': null},
            'metadata' => {...row, 'title': 'Wrong title'},
            _ => {...row, 'body_text': privateBody},
          };
          response = row;
          final Future<MaterialMutationResult> result = switch (action) {
            'create' => repository.createMaterial(
              CreateMaterialRequest(
                actorId: actorId,
                sessionId: sessionId,
                draft: materialDraft(),
              ),
            ),
            'update' => repository.updateMaterial(
              UpdateMaterialRequest(
                actorId: actorId,
                expected: expected(),
                draft: materialDraft(),
              ),
            ),
            'delete' => repository.deleteMaterial(
              MaterialLifecycleRequest(actorId: actorId, expected: expected()),
            ),
            _ => repository.restoreMaterial(
              MaterialLifecycleRequest(
                actorId: actorId,
                expected: expected(deleted: true),
              ),
            ),
          };
          await expectLater(
            result,
            throwsA(failure(MaterialFailureKind.uncertain, refresh: true)),
          );
          expect(requests, hasLength(1));
        },
      );
    }
  }
  for (final (code, message, kind) in [
    ('40001', 'material_changed', MaterialFailureKind.conflict),
    ('22023', 'material_operation_reused', MaterialFailureKind.operationReused),
    ('42501', 'admin_required', MaterialFailureKind.accessDenied),
    ('42501', 'parent_unavailable', MaterialFailureKind.unavailable),
    ('42501', 'material_unavailable', MaterialFailureKind.unavailable),
    ('22023', 'material_not_ready', MaterialFailureKind.notReady),
    ('22023', 'invalid_material_input', MaterialFailureKind.invalidInput),
    ('22023', 'invalid_material_payload', MaterialFailureKind.invalidInput),
    ('40001', 'PRIVATE_CANARY', MaterialFailureKind.uncertain),
  ]) {
    test(
      'server $code/$message maps to sanitized $kind and requests refresh',
      () async {
        status = 400;
        response = {
          'code': code,
          'message': message,
          'details': privateBody,
          'hint': privateTarget,
        };
        await expectLater(
          repository.updateMaterial(
            UpdateMaterialRequest(
              actorId: actorId,
              expected: expected(),
              draft: materialDraft(),
            ),
          ),
          throwsA(failure(kind, refresh: true)),
        );
        expect(requests, hasLength(1));
      },
    );
  }
  test(
    'transport failure is uncertain for writes and sanitized for reads',
    () async {
      networkError = StateError(privateBody);
      final request = CreateMaterialRequest(
        actorId: actorId,
        sessionId: sessionId,
        draft: materialDraft(),
      );
      await expectLater(
        repository.createMaterial(request),
        throwsA(failure(MaterialFailureKind.uncertain, refresh: true)),
      );
      final originalBody = requests.single.body;
      networkError = null;
      await repository.createMaterial(request);
      expect(requests.last.body, originalBody);
      networkError = StateError(privateTarget);
      await expectLater(
        repository.listMaterials(sessionId),
        throwsA(failure(MaterialFailureKind.requestFailed, refresh: false)),
      );
    },
  );
  test('timeout never retries automatically; same request remains stable after late response', () async {
    repository = SupabaseMaterialRepository(
      client,
      timeout: const Duration(milliseconds: 20),
    );
    pending = Completer<http.Response>();
    final request = CreateMaterialRequest(
      actorId: actorId,
      sessionId: sessionId,
      draft: materialDraft(),
    );
    await expectLater(
      repository.createMaterial(request),
      throwsA(failure(MaterialFailureKind.uncertain, refresh: true)),
    );
    expect(requests, hasLength(1));
    pending!.complete(
      http.Response(
        jsonEncode(materialRow()),
        200,
        request: requests.single,
        headers: {'content-type': 'application/json'},
      ),
    );
    pending = null;
    await repository.createMaterial(request);
    expect(requests, hasLength(2));
    expect(requests[0].body, requests[1].body);
  });
  test(
    'invalid IDs, offsets, kinds, states and operation IDs never send requests',
    () async {
      final invalidCalls = <Future<Object?>>[
        repository.listMaterials('bad'),
        repository.listMaterials(sessionId, offset: -1),
        repository.listMaterials(sessionId, offset: maxMaterialPosition),
        repository.createMaterial(
          CreateMaterialRequest(
            actorId: actorId,
            sessionId: 'bad',
            draft: materialDraft(),
          ),
        ),
        repository.createMaterial(
          CreateMaterialRequest(
            actorId: actorId,
            sessionId: sessionId,
            draft: materialDraft(),
            operationId: 'bad',
          ),
        ),
        repository.createMaterial(
          CreateMaterialRequest(
            actorId: actorId,
            sessionId: sessionId,
            draft: materialDraft(status: ContentStatus.published),
          ),
        ),
        repository.updateMaterial(
          UpdateMaterialRequest(
            actorId: actorId,
            expected: expected(),
            draft: materialDraft(kind: MaterialKind.link),
          ),
        ),
        repository.updateMaterial(
          UpdateMaterialRequest(
            actorId: actorId,
            expected: expected(deleted: true),
            draft: materialDraft(),
          ),
        ),
        repository.updateMaterial(
          UpdateMaterialRequest(
            actorId: actorId,
            expected: expected(revision: maxMaterialRevision),
            draft: materialDraft(),
          ),
        ),
        repository.deleteMaterial(
          MaterialLifecycleRequest(
            actorId: actorId,
            expected: expected(deleted: true),
          ),
        ),
        repository.restoreMaterial(
          MaterialLifecycleRequest(actorId: actorId, expected: expected()),
        ),
        repository.deleteMaterial(
          MaterialLifecycleRequest(
            actorId: actorId,
            expected: expected(),
            operationId: 'bad',
          ),
        ),
      ];
      await Future.wait(
        invalidCalls.map(
          (call) => expectLater(call, throwsA(isA<MaterialFailure>())),
        ),
      );
      expect(requests, isEmpty);
    },
  );
}
