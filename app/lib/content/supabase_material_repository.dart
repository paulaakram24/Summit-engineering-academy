import 'package:supabase_flutter/supabase_flutter.dart';

import 'material_repository.dart';

class SupabaseMaterialRepository implements MaterialRepository {
  SupabaseMaterialRepository(
    this.client, {
    this.timeout = const Duration(seconds: 20),
  });
  final SupabaseClient client;
  final Duration timeout;

  @override
  String? get currentActorId {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  void _input(bool valid) {
    if (!valid) throw const MaterialFailure(MaterialFailureKind.invalidInput);
  }

  void _response(bool valid) {
    if (!valid) throw const MaterialFailure(MaterialFailureKind.requestFailed);
  }

  Session _actorSession(String actorId) {
    _input(isMaterialUuid(actorId));
    Session? session;
    String? liveActor;
    try {
      session = client.auth.currentSession;
      liveActor = client.auth.currentUser?.id;
    } catch (_) {
      // Custom-token clients have no authenticated GoTrue identity. Fail closed.
    }
    if (session == null ||
        liveActor == null ||
        !isMaterialUuid(liveActor) ||
        session.accessToken.isEmpty ||
        session.isExpired) {
      throw const MaterialFailure(
        MaterialFailureKind.accessDenied,
        requiresRefresh: true,
      );
    }
    if (liveActor.toLowerCase() != actorId.toLowerCase() ||
        session.user.id.toLowerCase() != actorId.toLowerCase()) {
      throw const MaterialFailure(
        MaterialFailureKind.actorMismatch,
        requiresRefresh: true,
      );
    }
    return session;
  }

  Future<dynamic> _mutationRpc(
    String actorId,
    String name,
    Map<String, dynamic> params,
  ) async {
    final session = _actorSession(actorId);
    try {
      // Pin this request's token without changing shared client headers. The
      // SDK resolves auth asynchronously; a concurrent sign-in must not lend
      // another actor's token to this actor-scoped idempotency operation.
      return await client
          .rpc(name, params: params)
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
    } finally {
      // Discard successful and failed responses after sign-out/actor change.
      // A previously transmitted write may already have committed.
      _actorSession(actorId);
    }
  }

  Future<T> _request<T>(
    Future<T> Function() action, {
    bool mutation = false,
    String? actorId,
  }) async {
    try {
      return await action().timeout(timeout);
    } on MaterialFailure catch (error) {
      if (error.kind == MaterialFailureKind.accessDenied ||
          error.kind == MaterialFailureKind.actorMismatch) {
        rethrow;
      }
      throw MaterialFailure(
        mutation
            ? MaterialFailureKind.uncertain
            : MaterialFailureKind.requestFailed,
        requiresRefresh: mutation,
      );
    } on PostgrestException catch (error) {
      final kind = switch ((error.code, error.message)) {
        ('40001', 'material_changed') => MaterialFailureKind.conflict,
        ('22023', 'material_operation_reused') =>
          MaterialFailureKind.operationReused,
        ('42501', 'admin_required') => MaterialFailureKind.accessDenied,
        ('42501', 'parent_unavailable' || 'material_unavailable') =>
          MaterialFailureKind.unavailable,
        ('22023', 'material_not_ready') => MaterialFailureKind.notReady,
        ('22023', 'invalid_material_input' || 'invalid_material_payload') =>
          MaterialFailureKind.invalidInput,
        _ =>
          mutation
              ? MaterialFailureKind.uncertain
              : MaterialFailureKind.requestFailed,
      };
      throw MaterialFailure(kind, requiresRefresh: mutation);
    } catch (_) {
      throw MaterialFailure(
        mutation
            ? MaterialFailureKind.uncertain
            : MaterialFailureKind.requestFailed,
        requiresRefresh: mutation,
      );
    } finally {
      // Check again at the repository return boundary, after parsing/timeout.
      if (actorId != null) _actorSession(actorId);
    }
  }

  void _expected(
    MaterialDescriptor expected,
    String operationId, {
    required bool deleted,
  }) {
    _descriptorInput(expected);
    _input(
      isMaterialUuid(operationId) &&
          expected.revision < maxMaterialRevision &&
          expected.isDeleted == deleted,
    );
  }

  void _descriptorInput(MaterialDescriptor descriptor) {
    try {
      descriptor.validate();
    } catch (_) {
      throw const MaterialFailure(MaterialFailureKind.invalidInput);
    }
  }

  bool _sameEntity(MaterialDescriptor a, MaterialDescriptor b) =>
      a.id.toLowerCase() == b.id.toLowerCase() &&
      a.sessionId.toLowerCase() == b.sessionId.toLowerCase() &&
      a.kind == b.kind &&
      a.createdBy.toLowerCase() == b.createdBy.toLowerCase() &&
      a.createdAt.isAtSameMomentAs(b.createdAt);

  void _draftMatches(MaterialDescriptor row, MaterialDraft draft) {
    _response(
      row.kind == draft.kind &&
          row.title == draft.title.trim() &&
          row.summary == draft.summary &&
          row.position == draft.position &&
          row.status == draft.status,
    );
  }

  @override
  Future<List<MaterialDescriptor>> listMaterials(
    String sessionId, {
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    _input(
      isMaterialUuid(sessionId) &&
          offset >= 0 &&
          offset <= maxMaterialPosition - materialPageSize,
    );
    return _request(() async {
      var query = client
          .from('session_materials')
          .select(materialDescriptorFields)
          .eq('session_id', sessionId);
      if (!includeDeleted) query = query.isFilter('deleted_at', null);
      final rows = await query
          .order('position', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + materialPageSize - 1);
      _response(rows.length <= materialPageSize);
      final result = rows
          .map(MaterialDescriptor.fromJson)
          .toList(growable: false);
      final ids = <String>{};
      MaterialDescriptor? previous;
      for (final row in result) {
        _response(
          row.sessionId.toLowerCase() == sessionId.toLowerCase() &&
              (includeDeleted || !row.isDeleted) &&
              ids.add(row.id.toLowerCase()),
        );
        if (previous != null) {
          _response(
            row.position > previous.position ||
                (row.position == previous.position &&
                    row.id.toLowerCase().compareTo(previous.id.toLowerCase()) >
                        0),
          );
        }
        previous = row;
      }
      return List.unmodifiable(result);
    });
  }

  @override
  Future<AdminMaterialDetail> getAdminDetail(
    MaterialDescriptor expected,
  ) async {
    _descriptorInput(expected);
    return _request(() async {
      final row = await client.rpc(
        'get_admin_material_detail',
        params: {'p_material_id': expected.id},
      );
      final detail = AdminMaterialDetail.fromJson(row);
      _response(
        _sameEntity(detail.descriptor, expected) &&
            detail.descriptor.revision >= expected.revision,
      );
      return detail;
    });
  }

  Map<String, dynamic> _editable(MaterialDraft draft) => {
    'p_title': draft.title.trim(),
    'p_summary': draft.summary,
    'p_position': draft.position,
    'p_body_text': draft.payload.bodyText,
    'p_target_url': draft.payload.targetUrl,
  };

  @override
  Future<MaterialMutationResult> createMaterial(
    CreateMaterialRequest request,
  ) async {
    _actorSession(request.actorId);
    _input(
      isMaterialUuid(request.sessionId) &&
          isMaterialUuid(request.operationId) &&
          request.draft.status == ContentStatus.draft,
    );
    request.draft.validate();
    return _request(
      () async {
        final row = MaterialDescriptor.fromJson(
          await _mutationRpc(request.actorId, 'create_session_material', {
            'p_session_id': request.sessionId,
            'p_kind': request.draft.kind.name,
            ..._editable(request.draft),
            'p_operation_id': request.operationId,
          }),
        );
        _response(
          row.sessionId.toLowerCase() == request.sessionId.toLowerCase() &&
              row.revision == 1 &&
              row.createdBy.toLowerCase() == request.actorId.toLowerCase() &&
              !row.isDeleted,
        );
        _draftMatches(row, request.draft);
        return MaterialMutationResult(row);
      },
      mutation: true,
      actorId: request.actorId,
    );
  }

  @override
  Future<MaterialMutationResult> updateMaterial(
    UpdateMaterialRequest request,
  ) async {
    _actorSession(request.actorId);
    _expected(request.expected, request.operationId, deleted: false);
    _input(request.expected.kind == request.draft.kind);
    request.draft.validate();
    return _request(
      () async {
        final row = MaterialDescriptor.fromJson(
          await _mutationRpc(request.actorId, 'update_session_material', {
            'p_material_id': request.expected.id,
            'p_expected_revision': request.expected.revision,
            ..._editable(request.draft),
            'p_status': request.draft.status.name,
            'p_operation_id': request.operationId,
          }),
        );
        _response(
          _sameEntity(row, request.expected) &&
              row.revision == request.expected.revision + 1 &&
              !row.isDeleted,
        );
        _draftMatches(row, request.draft);
        return MaterialMutationResult(row);
      },
      mutation: true,
      actorId: request.actorId,
    );
  }

  Future<MaterialMutationResult> _lifecycle(
    MaterialLifecycleRequest request, {
    required bool restore,
  }) async {
    _actorSession(request.actorId);
    _expected(request.expected, request.operationId, deleted: restore);
    return _request(
      () async {
        final row = MaterialDescriptor.fromJson(
          await _mutationRpc(
            request.actorId,
            restore ? 'restore_session_material' : 'delete_session_material',
            {
              'p_material_id': request.expected.id,
              'p_expected_revision': request.expected.revision,
              'p_operation_id': request.operationId,
            },
          ),
        );
        _response(
          _sameEntity(row, request.expected) &&
              row.revision == request.expected.revision + 1 &&
              row.isDeleted == !restore &&
              row.status ==
                  (restore ? ContentStatus.draft : ContentStatus.archived) &&
              row.title == request.expected.title &&
              row.summary == request.expected.summary &&
              row.position == request.expected.position,
        );
        return MaterialMutationResult(row);
      },
      mutation: true,
      actorId: request.actorId,
    );
  }

  @override
  Future<MaterialMutationResult> deleteMaterial(
    MaterialLifecycleRequest request,
  ) => _lifecycle(request, restore: false);
  @override
  Future<MaterialMutationResult> restoreMaterial(
    MaterialLifecycleRequest request,
  ) => _lifecycle(request, restore: true);
}
