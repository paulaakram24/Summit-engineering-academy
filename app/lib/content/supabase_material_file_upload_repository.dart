import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'material_file_upload_repository.dart';
import 'material_models.dart';

class SupabaseMaterialFileUploadRepository
    implements MaterialFileUploadRepository {
  SupabaseMaterialFileUploadRepository(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  });
  final SupabaseClient client;
  final Duration timeout;
  @override
  String? get currentActorId => client.auth.currentUser?.id;

  Session _session() {
    try {
      final session = client.auth.currentSession;
      if (session == null ||
          session.isExpired ||
          session.accessToken.isEmpty ||
          !isCatalogUuid(session.user.id) ||
          client.auth.currentUser?.id.toLowerCase() !=
              session.user.id.toLowerCase()) {
        throw const MaterialFileUploadFailure(accessChanged: true);
      }
      return session;
    } catch (_) {
      throw const MaterialFileUploadFailure(accessChanged: true);
    }
  }

  Future<T> _bound<T>(
    String actorId,
    Future<T> Function(Session, void Function()) work,
  ) async {
    final session = _session();
    final actor = session.user.id.toLowerCase();
    var changed = false;
    void check() {
      if (changed ||
          actor != actorId.toLowerCase() ||
          _session().user.id.toLowerCase() != actor) {
        throw const MaterialFileUploadFailure(accessChanged: true);
      }
    }

    check();
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session?.user.id.toLowerCase() != actor) changed = true;
      },
      onError: (Object _) {
        changed = true;
      },
    );
    try {
      final value = await work(session, check);
      check();
      return value;
    } on MaterialFileUploadFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw MaterialFileUploadFailure(
        accessChanged:
            error.code == '42501' &&
            error.message == 'material_upload_access_required',
      );
    } catch (_) {
      throw const MaterialFileUploadFailure();
    } finally {
      await subscription.cancel();
      check();
    }
  }

  Future<Object?> _rpc(
    Session session,
    String name,
    Map<String, dynamic> params,
  ) => client
      .rpc(name, params: params)
      .setHeader('Authorization', 'Bearer ${session.accessToken}')
      .timeout(timeout);

  @override
  Future<List<MaterialFileUpload>> listUploads({
    required String actorId,
    required MaterialDescriptor material,
  }) async {
    if (!isCatalogUuid(actorId) || !isCatalogUuid(material.id)) {
      throw const MaterialFileUploadFailure();
    }
    return _bound(actorId, (session, check) async {
      final value = await _rpc(session, 'list_material_file_uploads', {
        'p_material_id': material.id,
      });
      check();
      if (value is! List || value.length > 20) {
        throw const MaterialFileUploadFailure();
      }
      final rows = value.map(MaterialFileUpload.fromJson).toList();
      if (rows.any(
            (r) =>
                r.materialId != material.id.toLowerCase() ||
                (material.kind == MaterialKind.pdf &&
                    r.contentType != 'application/pdf'),
          ) ||
          rows.map((r) => r.assetId).toSet().length != rows.length) {
        throw const MaterialFileUploadFailure();
      }
      return List.unmodifiable(rows);
    });
  }

  Future<({String id, String path, bool uploaded})> _prepare(
    Session session,
    MaterialFileUploadRequest request,
  ) async {
    final value = await _rpc(session, 'prepare_material_file_upload', {
      'p_material_id': request.material.id,
      'p_expected_revision': request.material.revision,
      'p_file_name': request.file.fileName,
      'p_content_type': request.file.contentType,
      'p_byte_length': request.file.byteLength,
      'p_operation_id': request.operationId,
    });
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        !value.keys.every({'asset_id', 'path', 'state'}.contains) ||
        value['asset_id'] is! String ||
        !isCatalogUuid(value['asset_id'] as String) ||
        (value['state'] != 'reserved' && value['state'] != 'uploaded')) {
      throw const MaterialFileUploadFailure();
    }
    final id = (value['asset_id'] as String).toLowerCase();
    final path =
        '${request.material.id.toLowerCase()}/$id.${request.file.extension}';
    if (value['path'] != path) throw const MaterialFileUploadFailure();
    return (id: id, path: path, uploaded: value['state'] == 'uploaded');
  }

  MaterialFileUpload _verified(
    Object? value,
    String id,
    MaterialFileUploadRequest request,
  ) {
    final row = MaterialFileUpload.fromJson(value);
    if (row.assetId != id ||
        row.materialId != request.material.id.toLowerCase() ||
        row.fileName != request.file.fileName ||
        row.contentType != request.file.contentType ||
        row.byteLength != request.file.byteLength ||
        row.state != MaterialFileUploadState.uploaded) {
      throw const MaterialFileUploadFailure();
    }
    return row;
  }

  @override
  Future<MaterialFileUpload> upload(
    MaterialFileUploadRequest request, {
    void Function(MaterialFileUploadPhase phase)? onPhase,
  }) => _bound(request.actorId, (session, check) async {
    check();
    onPhase?.call(MaterialFileUploadPhase.preparing);
    check();
    final prepared = await _prepare(session, request);
    check();
    if (!prepared.uploaded) {
      onPhase?.call(MaterialFileUploadPhase.transferring);
      check();
      await client.storage
          .from('material-upload-quarantine')
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .uploadBinary(
            prepared.path,
            request.file.bytes,
            fileOptions: FileOptions(
              contentType: request.file.contentType,
              upsert: false,
              cacheControl: '0',
            ),
            retryAttempts: 0,
          )
          .timeout(const Duration(minutes: 2));
      check();
    }
    onPhase?.call(MaterialFileUploadPhase.checking);
    check();
    final value = await _rpc(session, 'complete_material_file_upload', {
      'p_asset_id': prepared.id,
    });
    check();
    return _verified(value, prepared.id, request);
  });

  @override
  Future<MaterialFileUpload> checkUpload(
    MaterialFileUploadRequest request, {
    void Function()? ensureActive,
  }) => _bound(request.actorId, (session, check) async {
    ensureActive?.call();
    check();
    final prepared = await _prepare(session, request);
    check();
    ensureActive?.call();
    check();
    final value = await _rpc(session, 'complete_material_file_upload', {
      'p_asset_id': prepared.id,
    });
    check();
    ensureActive?.call();
    return _verified(value, prepared.id, request);
  });
}
