import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'material_file_selection.dart';
import 'material_models.dart';
export 'material_file_selection.dart';

enum MaterialFileUploadState { reserved, uploaded }

enum MaterialFileUploadPhase { preparing, transferring, checking }

final class MaterialFileUploadFailure implements Exception {
  const MaterialFileUploadFailure({this.accessChanged = false});
  final bool accessChanged;
  String get message => accessChanged
      ? 'Administrator access changed. Close and verify access again.'
      : 'The upload could not be confirmed. Refresh its status before trying again. Files are not ready for students until trusted validation is complete.';
  @override
  String toString() => message;
}

void _require(bool value) {
  if (!value) throw const MaterialFileUploadFailure();
}

/// Private admin status only. Uploaded means quarantined, not validated/ready.
final class MaterialFileUpload {
  factory MaterialFileUpload.fromJson(Object? value) {
    _require(value is Map<String, dynamic>);
    final row = value as Map<String, dynamic>;
    const keys = {
      'asset_id',
      'material_id',
      'file_name',
      'content_type',
      'byte_length',
      'state',
    };
    _require(row.length == keys.length && row.keys.every(keys.contains));
    _require(
      row['asset_id'] is String && isCatalogUuid(row['asset_id'] as String),
    );
    _require(
      row['material_id'] is String &&
          isCatalogUuid(row['material_id'] as String),
    );
    _require(row['file_name'] is String);
    final name = row['file_name'] as String;
    _require(
      name.isNotEmpty &&
          name.runes.length <= 160 &&
          !name.contains('/') &&
          !name.contains('\\') &&
          !name.runes.any((c) => c < 32 || (c >= 127 && c <= 159)),
    );
    final dot = name.lastIndexOf('.');
    _require(dot > 0 && name.substring(0, dot).trim().isNotEmpty);
    final ext = name.substring(dot + 1).toLowerCase();
    _require(
      (ext == 'pdf' && row['content_type'] == 'application/pdf') ||
          (ext == 'txt' && row['content_type'] == 'text/plain'),
    );
    _require(
      row['byte_length'] is int &&
          (row['byte_length'] as int) > 0 &&
          (row['byte_length'] as int) <= maxSelectedMaterialFileBytes,
    );
    final state = switch (row['state']) {
      'reserved' => MaterialFileUploadState.reserved,
      'uploaded' => MaterialFileUploadState.uploaded,
      _ => throw const MaterialFileUploadFailure(),
    };
    return MaterialFileUpload._(
      (row['asset_id'] as String).toLowerCase(),
      (row['material_id'] as String).toLowerCase(),
      name,
      row['content_type'] as String,
      row['byte_length'] as int,
      state,
    );
  }
  const MaterialFileUpload._(
    this.assetId,
    this.materialId,
    this.fileName,
    this.contentType,
    this.byteLength,
    this.state,
  );
  final String assetId, materialId, fileName, contentType;
  final int byteLength;
  final MaterialFileUploadState state;
}

/// Capture once for one selected file. Retain through uncertainty; never replace
/// its operation ID or bytes for an exact retry/reconciliation.
final class MaterialFileUploadRequest {
  factory MaterialFileUploadRequest({
    required String actorId,
    required MaterialDescriptor material,
    required SelectedMaterialFile file,
    String? operationId,
  }) {
    final operation = operationId ?? newMaterialOperationId();
    try {
      material.validate();
    } catch (_) {
      throw const MaterialFileUploadFailure();
    }
    _require(
      isCatalogUuid(actorId) &&
          isCatalogUuid(material.id) &&
          isCatalogUuid(material.sessionId) &&
          isCatalogUuid(operation) &&
          !material.isDeleted &&
          material.kind == file.kind &&
          (material.kind == MaterialKind.pdf ||
              material.kind == MaterialKind.file) &&
          material.revision >= 1 &&
          material.revision <= maxMaterialRevision,
    );
    return MaterialFileUploadRequest._(
      actorId.toLowerCase(),
      material,
      file,
      operation.toLowerCase(),
    );
  }
  const MaterialFileUploadRequest._(
    this.actorId,
    this.material,
    this.file,
    this.operationId,
  );
  final String actorId, operationId;
  final MaterialDescriptor material;
  final SelectedMaterialFile file;
}

abstract class MaterialFileUploadRepository {
  String? get currentActorId;
  Future<List<MaterialFileUpload>> listUploads({
    required String actorId,
    required MaterialDescriptor material,
  });
  Future<MaterialFileUpload> upload(
    MaterialFileUploadRequest request, {
    // Called before each next side effect; throwing aborts subsequent stages.
    void Function(MaterialFileUploadPhase phase)? onPhase,
  });

  /// Explicit reconciliation only; sends no file bytes and never retries upload.
  Future<MaterialFileUpload> checkUpload(
    MaterialFileUploadRequest request, {
    void Function()? ensureActive,
  });
}
