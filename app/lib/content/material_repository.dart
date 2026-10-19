import 'material_models.dart';
export 'material_models.dart';

/// Keep each request instance through uncertainty. New intent needs a new UUID;
/// do not mutate arguments or generate a replacement operation ID on retry.
/// Capture actorId from the authenticated client when creating the intent.
/// Preserve it on reconstruction; it is not the descriptor's authored-by ID.
final class CreateMaterialRequest {
  CreateMaterialRequest({
    required this.sessionId,
    required this.draft,
    required this.actorId,
    String? operationId,
  }) : operationId = operationId ?? newMaterialOperationId();
  final String sessionId, operationId, actorId;
  final MaterialDraft draft;
}

final class UpdateMaterialRequest {
  UpdateMaterialRequest({
    required this.expected,
    required this.draft,
    required this.actorId,
    String? operationId,
  }) : operationId = operationId ?? newMaterialOperationId();
  final MaterialDescriptor expected;
  final MaterialDraft draft;
  final String operationId, actorId;
}

final class MaterialLifecycleRequest {
  MaterialLifecycleRequest({
    required this.expected,
    required this.actorId,
    String? operationId,
  }) : operationId = operationId ?? newMaterialOperationId();
  final MaterialDescriptor expected;
  final String operationId, actorId;
}

/// Admin authoring only. Server role/admission checks remain authoritative.
/// There are no asset, student, delivery, signing or URL-launch operations here.
abstract class MaterialRepository {
  Future<List<MaterialDescriptor>> listMaterials(
    String sessionId, {
    int offset = 0,
    bool includeDeleted = false,
  });
  Future<AdminMaterialDetail> getAdminDetail(MaterialDescriptor expected);
  Future<MaterialMutationResult> createMaterial(CreateMaterialRequest request);
  Future<MaterialMutationResult> updateMaterial(UpdateMaterialRequest request);
  Future<MaterialMutationResult> deleteMaterial(
    MaterialLifecycleRequest request,
  );
  Future<MaterialMutationResult> restoreMaterial(
    MaterialLifecycleRequest request,
  );
}
