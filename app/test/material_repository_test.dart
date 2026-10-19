import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/content/material_repository.dart';

import 'material_models_test.dart';

void main() {
  test('immutable request retains operation ID and expected snapshot for exact retry', () {
    final expected = MaterialDescriptor.fromJson(materialRow(revision: 7));
    final create = CreateMaterialRequest(
      actorId: actorId,
      sessionId: sessionId,
      draft: materialDraft(),
    );
    final update = UpdateMaterialRequest(
      actorId: actorId,
      expected: expected,
      draft: materialDraft(),
    );
    final lifecycle = MaterialLifecycleRequest(
      actorId: actorId,
      expected: expected,
    );
    final operations = [
      create.operationId,
      update.operationId,
      lifecycle.operationId,
    ];
    expect(operations.toSet(), hasLength(3));
    expect([
      create.operationId,
      update.operationId,
      lifecycle.operationId,
    ], operations);
    expect(update.expected.revision, 7);
    expect(identical(update.expected, expected), isTrue);
    expect(identical(lifecycle.expected, expected), isTrue);
    expect([
      create.actorId,
      update.actorId,
      lifecycle.actorId,
    ], everyElement(actorId));
  });
  test(
    'caller can retain an explicit operation across request reconstruction',
    () {
      final expected = MaterialDescriptor.fromJson(materialRow());
      expect(
        CreateMaterialRequest(
          actorId: actorId,
          sessionId: sessionId,
          draft: materialDraft(),
          operationId: operationId,
        ).operationId,
        operationId,
      );
      expect(
        UpdateMaterialRequest(
          actorId: actorId,
          expected: expected,
          draft: materialDraft(),
          operationId: operationId,
        ).operationId,
        operationId,
      );
      expect(
        MaterialLifecycleRequest(
          actorId: actorId,
          expected: expected,
          operationId: operationId,
        ).operationId,
        operationId,
      );
    },
  );
  test('origin actor is retained independently of the descriptor author', () {
    final authoredByA = MaterialDescriptor.fromJson(materialRow());
    final updateByB = UpdateMaterialRequest(
      actorId: otherId,
      expected: authoredByA,
      draft: materialDraft(),
      operationId: operationId,
    );
    final lifecycleByB = MaterialLifecycleRequest(
      actorId: otherId,
      expected: authoredByA,
      operationId: operationId,
    );
    expect(updateByB.actorId, otherId);
    expect(lifecycleByB.actorId, otherId);
    expect(updateByB.expected.createdBy, actorId);
    expect(lifecycleByB.expected.createdBy, actorId);
    final reconstructed = UpdateMaterialRequest(
      actorId: updateByB.actorId,
      expected: updateByB.expected,
      draft: updateByB.draft,
      operationId: updateByB.operationId,
    );
    expect(reconstructed.actorId, otherId);
    expect(reconstructed.operationId, operationId);
  });
}
