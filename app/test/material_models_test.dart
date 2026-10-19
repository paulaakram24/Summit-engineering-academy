import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/content/material_models.dart';

const sessionId = '11111111-1111-4111-8111-111111111111';
const materialId = '22222222-2222-4222-8222-222222222222';
const actorId = '33333333-3333-4333-8333-333333333333';
const operationId = '44444444-4444-4444-8444-444444444444';
const otherId = '55555555-5555-4555-8555-555555555555';
const privateBody = 'PROTECTED_BODY_CANARY';
const privateTarget = 'https://example.invalid/PROTECTED_TARGET_CANARY';

Map<String, dynamic> materialRow({
  MaterialKind kind = MaterialKind.assignment,
  int revision = 1,
  bool deleted = false,
  ContentStatus? status,
}) => {
  'id': materialId,
  'session_id': sessionId,
  'kind': kind.name,
  'title': 'Material',
  'summary': 'Catalog summary',
  'position': 0,
  'status':
      (status ?? (deleted ? ContentStatus.archived : ContentStatus.draft)).name,
  'deleted_at': deleted ? '2026-10-19T04:00:00Z' : null,
  'revision': revision,
  'created_by': actorId,
  'created_at': '2026-10-19T03:00:00Z',
  'updated_at': '2026-10-19T04:00:00Z',
};

MaterialDraft materialDraft({
  MaterialKind kind = MaterialKind.assignment,
  ContentStatus status = ContentStatus.draft,
}) => MaterialDraft(
  kind: kind,
  title: ' Material ',
  summary: 'Catalog summary',
  status: status,
  payload: switch (kind) {
    MaterialKind.assignment => const AssignmentMaterialPayload(privateBody),
    MaterialKind.link => const LinkMaterialPayload(privateTarget),
    _ => const EmptyMaterialPayload(),
  },
);

void main() {
  for (final kind in MaterialKind.values) {
    test('${kind.name} descriptor and matching typed payload', () {
      final descriptor = MaterialDescriptor.fromJson(materialRow(kind: kind));
      expect(descriptor.kind, kind);
      expect(descriptor.revision, 1);
      expect(descriptor.createdAt, DateTime.utc(2026, 10, 19, 3));
      expect(materialDraft(kind: kind).validate, returnsNormally);
      final detail = AdminMaterialDetail.fromJson({
        'descriptor': materialRow(kind: kind),
        'body_text': kind == MaterialKind.assignment ? privateBody : '',
        'target_url': kind == MaterialKind.link ? privateTarget : null,
      });
      expect(detail.payload.validFor(kind), isTrue);
      expect(detail.toString(), isNot(contains('CANARY')));
      expect(detail.payload.toString(), isNot(contains('CANARY')));
    });
  }
  test('descriptor parser enforces exact safe keys and required types', () {
    final invalid = <Object?>[
      null,
      [],
      {},
      {...materialRow(), 'body_text': privateBody},
      {...materialRow(), 'target_url': privateTarget},
      {...materialRow()}..remove('deleted_at'),
      {...materialRow(), 'revision': '1'},
      {...materialRow(), 'revision': 1.0},
      {...materialRow(), 'revision': 0},
      {...materialRow(), 'position': -1},
      {...materialRow(), 'position': maxMaterialPosition + 1},
      {...materialRow(), 'id': 'bad'},
      {...materialRow(), 'session_id': 'bad'},
      {...materialRow(), 'created_by': 'bad'},
      {...materialRow(), 'kind': 'html'},
      {...materialRow(), 'status': 'unknown'},
      {...materialRow(), 'title': ''},
      {...materialRow(), 'summary': 'https://example.invalid/secret'},
      {...materialRow(), 'created_at': '2026-10-19'},
      {...materialRow(), 'updated_at': '2026-10-19T02:00:00Z'},
      {...materialRow(deleted: true), 'status': 'published'},
      materialRow(kind: MaterialKind.video, status: ContentStatus.published),
    ];
    for (final row in invalid) {
      expect(
        () => MaterialDescriptor.fromJson(row),
        throwsA(isA<MaterialFailure>()),
      );
    }
  });
  test('timestamps compare instants across offsets and parse deleted recovery state', () {
    final row = MaterialDescriptor.fromJson({
      ...materialRow(deleted: true),
      'created_at': '2026-10-19T05:00:00+02:00',
    });
    expect(row.createdAt, DateTime.utc(2026, 10, 19, 3));
    expect(row.isDeleted, isTrue);
    expect(row.status, ContentStatus.archived);
  });
  test('catalog text bounds count codepoints and reject URL/embed fields', () {
    for (final title in [
      ' ',
      'x' * 161,
      'https://example.invalid',
      'WWW.example.invalid',
      '<iframe>secret</iframe>',
      'a\u0000',
    ]) {
      expect(
        MaterialDraft(
          kind: MaterialKind.file,
          title: title,
          payload: const EmptyMaterialPayload(),
        ).validate,
        throwsA(isA<MaterialFailure>()),
      );
    }
    expect(
      MaterialDraft(
        kind: MaterialKind.file,
        title: '😀' * 160,
        payload: const EmptyMaterialPayload(),
        summary: 'x' * 10000,
        position: maxMaterialPosition,
      ).validate,
      returnsNormally,
    );
    for (final draft in [
      MaterialDraft(
        kind: MaterialKind.file,
        title: 'T',
        payload: const EmptyMaterialPayload(),
        summary: 'x' * 10001,
      ),
      const MaterialDraft(
        kind: MaterialKind.file,
        title: 'T',
        payload: EmptyMaterialPayload(),
        position: -1,
      ),
      const MaterialDraft(
        kind: MaterialKind.file,
        title: 'T',
        payload: EmptyMaterialPayload(),
        position: maxMaterialPosition + 1,
      ),
    ]) {
      expect(draft.validate, throwsA(isA<MaterialFailure>()));
    }
  });
  test(
    'targets follow structural HTTPS contract without normalizing secrets',
    () {
      for (final url in [
        'https://example.invalid',
        privateTarget,
        'https://host:12345/a?q=x#y',
        'https://127.0.0.1/a',
      ]) {
        expect(isMaterialHttpsTarget(url), isTrue);
      }
      for (final url in [
        '',
        'http://example.invalid',
        'HTTPS://example.invalid',
        '//example.invalid',
        'https://user:pass@example.invalid',
        'https://x/a b',
        'https://x/a\n',
        'https://x/a\\b',
        'https://x/<tag>',
        'https://[::1]/',
        'https://x:123456/',
        'https://x/${'a' * 4096}',
      ]) {
        expect(isMaterialHttpsTarget(url), isFalse);
      }
    },
  );
  test(
    'payload kinds cannot be mixed; protected body and target bounds apply',
    () {
      for (final (kind, payload) in [
        (MaterialKind.assignment, const LinkMaterialPayload(privateTarget)),
        (MaterialKind.link, const AssignmentMaterialPayload(privateBody)),
        (MaterialKind.video, const AssignmentMaterialPayload(privateBody)),
        (MaterialKind.assignment, AssignmentMaterialPayload('x' * 10001)),
      ]) {
        expect(
          MaterialDraft(kind: kind, title: 'T', payload: payload).validate,
          throwsA(isA<MaterialFailure>()),
        );
      }
      expect(
        MaterialDraft(
          kind: MaterialKind.assignment,
          title: 'T',
          payload: AssignmentMaterialPayload('😀' * 10000),
        ).validate,
        returnsNormally,
      );
    },
  );
  test('publication readiness closes placeholders and unconfigured items', () {
    for (final kind in [
      MaterialKind.video,
      MaterialKind.pdf,
      MaterialKind.file,
    ]) {
      expect(
        materialDraft(kind: kind, status: ContentStatus.published).validate,
        throwsA(
          isA<MaterialFailure>().having(
            (e) => e.kind,
            'kind',
            MaterialFailureKind.notReady,
          ),
        ),
      );
    }
    for (final (kind, payload) in [
      (MaterialKind.link, const LinkMaterialPayload(null)),
      (MaterialKind.assignment, const AssignmentMaterialPayload('   ')),
    ]) {
      expect(
        MaterialDraft(
          kind: kind,
          title: 'T',
          payload: payload,
          status: ContentStatus.published,
        ).validate,
        throwsA(isA<MaterialFailure>()),
      );
    }
    expect(
      materialDraft(status: ContentStatus.published).validate,
      returnsNormally,
    );
    expect(
      materialDraft(
        kind: MaterialKind.link,
        status: ContentStatus.published,
      ).validate,
      returnsNormally,
    );
  });
  test('detail rejects mixed payloads, unknown keys and malformed protected values', () {
    for (final row in [
      {
        'descriptor': materialRow(kind: MaterialKind.file),
        'body_text': privateBody,
        'target_url': null,
      },
      {
        'descriptor': materialRow(),
        'body_text': privateBody,
        'target_url': privateTarget,
      },
      {
        'descriptor': materialRow(kind: MaterialKind.link),
        'body_text': privateBody,
        'target_url': privateTarget,
      },
      {'descriptor': materialRow(), 'body_text': null, 'target_url': null},
      {
        'descriptor': materialRow(),
        'body_text': privateBody,
        'target_url': null,
        'asset': 'secret',
      },
    ]) {
      expect(
        () => AdminMaterialDetail.fromJson(row),
        throwsA(isA<MaterialFailure>()),
      );
    }
  });
  test('secure generated operations have UUIDv4 version and variant bits', () {
    final ids = List.generate(100, (_) => newMaterialOperationId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(isMaterialUuid(id), isTrue);
      expect(
        id,
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
    }
  });
  test(
    'mutation snapshots always require refresh and failures are sanitized',
    () {
      expect(
        MaterialMutationResult(MaterialDescriptor.fromJson(materialRow()))
            .requiresRefresh,
        isTrue,
      );
      for (final kind in MaterialFailureKind.values) {
        expect(MaterialFailure(kind).toString(), isNot(contains('CANARY')));
      }
    },
  );
}
