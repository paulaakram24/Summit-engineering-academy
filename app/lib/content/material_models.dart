import 'dart:math';

import 'content_models.dart' show ContentStatus;
export 'content_models.dart' show ContentStatus;

const materialPageSize = 20;
const maxMaterialPosition = 2147483647;
const maxMaterialRevision = 0x7fffffffffffffff;
const materialDescriptorFields =
    'id,session_id,kind,title,summary,position,status,deleted_at,revision,created_by,created_at,updated_at';

enum MaterialKind { video, pdf, file, link, assignment }

enum MaterialFailureKind {
  invalidInput,
  conflict,
  operationReused,
  accessDenied,
  actorMismatch,
  unavailable,
  notReady,
  uncertain,
  requestFailed,
}

class MaterialFailure implements Exception {
  const MaterialFailure(this.kind, {this.requiresRefresh = false});
  final MaterialFailureKind kind;
  final bool requiresRefresh;
  String get message => switch (kind) {
    MaterialFailureKind.invalidInput =>
      'Check the material fields and try again.',
    MaterialFailureKind.conflict => 'This material changed. Refresh and reconcile your edits before trying again.',
    MaterialFailureKind.operationReused => 'This operation was already used for a different request. Refresh before starting a new edit.',
    MaterialFailureKind.accessDenied =>
      'Administrator access must be verified again.',
    MaterialFailureKind.actorMismatch => 'This request belongs to a different account. Sign in with the original account and refresh before retrying.',
    MaterialFailureKind.unavailable => 'The material or its parent session is unavailable. Refresh before continuing.',
    MaterialFailureKind.notReady => 'This material is not ready to publish.',
    MaterialFailureKind.uncertain => 'The material change could not be confirmed and may already have completed. Refresh before continuing. Retain the original request for an exact retry.',
    MaterialFailureKind.requestFailed => 'Unable to load materials. Check your connection and administrator access, then retry.',
  };
  @override
  String toString() => message;
}

bool isMaterialUuid(String value) =>
    RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(value);

/// Generate once per new intent, then retain the immutable request on retry.
String newMaterialOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool _catalogText(String value, int max, {bool required = false}) =>
    (!required || value.trim().isNotEmpty) &&
    value.runes.length <= max &&
    !value.contains('\u0000') &&
    !RegExp(r'https?://|www\.|<[^>]+>', caseSensitive: false).hasMatch(value);

/// Structural parity with the migration; never resolves or fetches the target.
bool isMaterialHttpsTarget(String value) =>
    value.runes.length <= 4096 &&
    !RegExp(r'[\s\x00-\x1f\x7f-\x9f\\<>]').hasMatch(value) &&
    RegExp(
      r'^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^\s\\<>]*)?$',
    ).hasMatch(value);

sealed class MaterialPayload {
  const MaterialPayload();
  String get bodyText => '';
  String? get targetUrl => null;
  bool validFor(MaterialKind kind) => switch (this) {
    EmptyMaterialPayload() =>
      kind == MaterialKind.video ||
          kind == MaterialKind.pdf ||
          kind == MaterialKind.file,
    AssignmentMaterialPayload() =>
      kind == MaterialKind.assignment &&
          bodyText.runes.length <= 10000 &&
          !bodyText.contains('\u0000'),
    LinkMaterialPayload() =>
      kind == MaterialKind.link &&
          (targetUrl == null || isMaterialHttpsTarget(targetUrl!)),
  };
}

final class EmptyMaterialPayload extends MaterialPayload {
  const EmptyMaterialPayload();
}

final class AssignmentMaterialPayload extends MaterialPayload {
  const AssignmentMaterialPayload(this.bodyText);
  @override
  final String bodyText;
}

final class LinkMaterialPayload extends MaterialPayload {
  const LinkMaterialPayload(this.targetUrl);
  @override
  final String? targetUrl;
}

final class MaterialDraft {
  const MaterialDraft({
    required this.kind,
    required this.title,
    required this.payload,
    this.summary = '',
    this.position = 0,
    this.status = ContentStatus.draft,
  });
  final MaterialKind kind;
  final String title, summary;
  final int position;
  final ContentStatus status;
  final MaterialPayload payload;

  void validate() {
    if (!_catalogText(title.trim(), 160, required: true) ||
        !_catalogText(summary, 10000) ||
        position < 0 ||
        position > maxMaterialPosition ||
        !payload.validFor(kind)) {
      throw const MaterialFailure(MaterialFailureKind.invalidInput);
    }
    if (status == ContentStatus.published &&
        switch (kind) {
          MaterialKind.video || MaterialKind.pdf || MaterialKind.file => true,
          MaterialKind.link => payload.targetUrl == null,
          MaterialKind.assignment => payload.bodyText.trim().isEmpty,
        }) {
      throw const MaterialFailure(MaterialFailureKind.notReady);
    }
  }
}

void _require(bool condition) {
  if (!condition) {
    throw const MaterialFailure(MaterialFailureKind.requestFailed);
  }
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _require(value is Map<String, dynamic>);
  final row = value as Map<String, dynamic>;
  _require(row.length == keys.length && row.keys.every(keys.contains));
  return row;
}

DateTime _timestamp(Object? value) {
  _require(value is String && RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value));
  final parsed = DateTime.tryParse(value as String);
  _require(parsed != null);
  return parsed!.toUtc();
}

/// Admin authoring metadata only. This is not a student delivery projection.
final class MaterialDescriptor {
  const MaterialDescriptor({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.summary,
    required this.position,
    required this.status,
    required this.revision,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });
  final String id, sessionId, title, summary, createdBy;
  final MaterialKind kind;
  final ContentStatus status;
  final int position, revision;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  void validate() {
    _require(
      isMaterialUuid(id) &&
          isMaterialUuid(sessionId) &&
          isMaterialUuid(createdBy),
    );
    _require(
      _catalogText(title, 160, required: true) && _catalogText(summary, 10000),
    );
    _require(
      position >= 0 &&
          position <= maxMaterialPosition &&
          revision >= 1 &&
          revision <= maxMaterialRevision,
    );
    _require(!isDeleted || status == ContentStatus.archived);
    _require(
      status != ContentStatus.published ||
          kind == MaterialKind.link ||
          kind == MaterialKind.assignment,
    );
    _require(!updatedAt.isBefore(createdAt));
  }

  factory MaterialDescriptor.fromJson(Object? value) {
    try {
      final row = _object(value, materialDescriptorFields.split(',').toSet());
      _require(row['position'] is int && row['revision'] is int);
      final descriptor = MaterialDescriptor(
        id: row['id'] as String,
        sessionId: row['session_id'] as String,
        kind: MaterialKind.values.byName(row['kind'] as String),
        title: row['title'] as String,
        summary: row['summary'] as String,
        position: row['position'] as int,
        status: ContentStatus.values.byName(row['status'] as String),
        revision: row['revision'] as int,
        createdBy: row['created_by'] as String,
        createdAt: _timestamp(row['created_at']),
        updatedAt: _timestamp(row['updated_at']),
        deletedAt: row['deleted_at'] == null
            ? null
            : _timestamp(row['deleted_at']),
      );
      descriptor.validate();
      return descriptor;
    } catch (_) {
      throw const MaterialFailure(MaterialFailureKind.requestFailed);
    }
  }
}

/// Private authoring payload; intentionally has no JSON/diagnostic serializer.
final class AdminMaterialDetail {
  const AdminMaterialDetail({required this.descriptor, required this.payload});
  final MaterialDescriptor descriptor;
  final MaterialPayload payload;
  MaterialDraft toDraft() => MaterialDraft(
    kind: descriptor.kind,
    title: descriptor.title,
    summary: descriptor.summary,
    position: descriptor.position,
    status: descriptor.status,
    payload: payload,
  );
  factory AdminMaterialDetail.fromJson(Object? value) {
    try {
      final row = _object(value, {'descriptor', 'body_text', 'target_url'});
      final descriptor = MaterialDescriptor.fromJson(row['descriptor']);
      final body = row['body_text'] as String;
      final target = row['target_url'] as String?;
      final MaterialPayload payload = switch (descriptor.kind) {
        MaterialKind.assignment => AssignmentMaterialPayload(body),
        MaterialKind.link => LinkMaterialPayload(target),
        _ => const EmptyMaterialPayload(),
      };
      _require(
        (descriptor.kind == MaterialKind.assignment || body == '') &&
            (descriptor.kind == MaterialKind.link || target == null),
      );
      MaterialDraft(
        kind: descriptor.kind,
        title: descriptor.title,
        summary: descriptor.summary,
        position: descriptor.position,
        status: descriptor.status,
        payload: payload,
      ).validate();
      return AdminMaterialDetail(descriptor: descriptor, payload: payload);
    } catch (_) {
      throw const MaterialFailure(MaterialFailureKind.requestFailed);
    }
  }
}

/// May be the original cached operation result, even after later edits/deletion.
/// Always refresh list/detail before displaying current controls or editing again.
final class MaterialMutationResult {
  const MaterialMutationResult(this.snapshot);
  final MaterialDescriptor snapshot;
  bool get requiresRefresh => true;
}
