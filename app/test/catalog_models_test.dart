import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';

const catalogActor = '11111111-1111-4111-8111-111111111111';
const catalogOtherActor = '22222222-2222-4222-8222-222222222222';
const catalogCourseId = '33333333-3333-4333-8333-333333333333';
const catalogSessionId = '44444444-4444-4444-8444-444444444444';
const catalogOtherId = '55555555-5555-4555-8555-555555555555';
const catalogImageId = '66666666-6666-4666-8666-666666666666';

Map<String, dynamic> catalogCourseRow({
  String id = catalogCourseId,
  int position = 0,
}) => {
  'id': id,
  'title': 'Course',
  'description': 'Course description',
  'instructor': 'Teacher',
  'category': 'Civil',
  'level': 'Beginner',
  'price_piasters': 10001,
  'position': position,
  'cover_path': '$id/$catalogImageId.png',
};
Map<String, dynamic> catalogSessionRow({
  String id = catalogSessionId,
  int position = 0,
}) => {
  'id': id,
  'course_id': catalogCourseId,
  'session_number': 1,
  'title': 'Session',
  'description': 'Session description',
  'price_piasters': 101,
  'position': position,
  'is_free_preview': false,
};
Map<String, dynamic> catalogEnvelope(
  List<Map<String, dynamic>> items, {
  bool more = false,
}) => {
  'items': items,
  'has_more': more,
  'next_cursor': more && items.isNotEmpty
      ? {'position': items.last['position'], 'id': items.last['id']}
      : null,
};

void main() {
  final invalid = throwsA(
    isA<CatalogFailure>().having(
      (e) => e.kind,
      'kind',
      CatalogFailureKind.invalidResponse,
    ),
  );
  test('course is a dedicated discovery projection and price stays integer piasters', () {
    final course = CatalogCourse.fromJson(catalogCourseRow());
    expect(course.id, catalogCourseId);
    expect(course.pricePiasters, 10001);
    expect(course.description, 'Course description');
    expect(course.instructor, 'Teacher');
    expect(course.category, 'Civil');
    expect(course.level, 'Beginner');
    expect(course.cursor.id, catalogCourseId);
    expect(course.cursor.position, 0);
    expect(
      CatalogCourse.fromJson({...catalogCourseRow(), 'cover_path': null})
          .coverPath,
      isNull,
    );
  });
  test('session projection has an explicit boolean preview flag, not an entitlement', () {
    final session = CatalogSession.fromJson(catalogSessionRow());
    expect(session.id, catalogSessionId);
    expect(session.courseId, catalogCourseId);
    expect(session.sessionNumber, 1);
    expect(session.pricePiasters, 101);
    expect(session.isFreePreview, isFalse);
    expect(
      CatalogSession.fromJson({...catalogSessionRow(), 'is_free_preview': true})
          .isFreePreview,
      isTrue,
    );
  });
  for (final field in [
    'status',
    'created_by',
    'created_at',
    'updated_at',
    'deleted_at',
    'body_text',
    'target_url',
    'asset_path',
  ]) {
    test('course and session reject forbidden extra $field', () {
      expect(
        () => CatalogCourse.fromJson({
          ...catalogCourseRow(),
          field: 'PRIVATE_CANARY',
        }),
        invalid,
      );
      expect(
        () => CatalogSession.fromJson({
          ...catalogSessionRow(),
          field: 'PRIVATE_CANARY',
        }),
        invalid,
      );
    });
  }
  test(
    'every declared course/session field is required, including nullable cover',
    () {
      for (final field in catalogCourseRow().keys) {
        expect(
          () => CatalogCourse.fromJson({...catalogCourseRow()}..remove(field)),
          invalid,
          reason: field,
        );
      }
      for (final field in catalogSessionRow().keys) {
        expect(
          () =>
              CatalogSession.fromJson({...catalogSessionRow()}..remove(field)),
          invalid,
          reason: field,
        );
      }
      for (final value in [null, [], 1, 'PRIVATE_CANARY']) {
        expect(() => CatalogCourse.fromJson(value), invalid);
        expect(() => CatalogSession.fromJson(value), invalid);
      }
    },
  );
  for (final field in ['price_piasters', 'position']) {
    test('$field requires bounded int32 values with no decimal coercion', () {
      for (final value in [-1, catalogMaxInteger + 1, 1.0, '1', true, null]) {
        expect(
          () => CatalogCourse.fromJson({...catalogCourseRow(), field: value}),
          invalid,
        );
        expect(
          () => CatalogSession.fromJson({...catalogSessionRow(), field: value}),
          invalid,
        );
      }
      for (final value in [0, catalogMaxInteger]) {
        expect(
          () => CatalogCourse.fromJson({...catalogCourseRow(), field: value}),
          returnsNormally,
        );
        expect(
          () => CatalogSession.fromJson({...catalogSessionRow(), field: value}),
          returnsNormally,
        );
      }
    });
  }
  test('session numbers are positive int32, IDs are UUIDs, preview is strictly boolean', () {
    for (final value in [0, -1, catalogMaxInteger + 1, 1.0, '1', null]) {
      expect(
        () => CatalogSession.fromJson({
          ...catalogSessionRow(),
          'session_number': value,
        }),
        invalid,
      );
    }
    expect(
      () => CatalogSession.fromJson({
        ...catalogSessionRow(),
        'session_number': catalogMaxInteger,
      }),
      returnsNormally,
    );
    for (final value in ['bad', '$catalogCourseId\n', '', null]) {
      expect(
        () => CatalogCourse.fromJson({...catalogCourseRow(), 'id': value}),
        invalid,
      );
      expect(
        () => CatalogSession.fromJson({
          ...catalogSessionRow(),
          'course_id': value,
        }),
        invalid,
      );
    }
    for (final value in [1, 'false', null]) {
      expect(
        () => CatalogSession.fromJson({
          ...catalogSessionRow(),
          'is_free_preview': value,
        }),
        invalid,
      );
    }
  });
  test('catalog text uses codepoint bounds and required text rules', () {
    final maximums = {
      'title': 160,
      'description': 10000,
      'instructor': 160,
      'category': 120,
      'level': 120,
    };
    for (final entry in maximums.entries) {
      expect(
        () => CatalogCourse.fromJson({
          ...catalogCourseRow(),
          entry.key: '😀' * entry.value,
        }),
        returnsNormally,
      );
      expect(
        () => CatalogCourse.fromJson({
          ...catalogCourseRow(),
          entry.key: 'x' * (entry.value + 1),
        }),
        invalid,
      );
      expect(
        () => CatalogCourse.fromJson({...catalogCourseRow(), entry.key: null}),
        invalid,
      );
    }
    expect(
      () => CatalogCourse.fromJson({...catalogCourseRow(), 'title': '   '}),
      invalid,
    );
    expect(
      () => CatalogCourse.fromJson({...catalogCourseRow(), 'description': ''}),
      returnsNormally,
    );
    expect(
      () => CatalogSession.fromJson({
        ...catalogSessionRow(),
        'description': 'x' * 10001,
      }),
      invalid,
    );
  });
  test('cover paths are course-scoped UUID PNG identifiers, never URL capabilities', () {
    for (final path in [
      'https://example.invalid/image.png',
      '$catalogOtherId/$catalogImageId.png',
      '$catalogCourseId/../$catalogImageId.png',
      '$catalogCourseId/$catalogImageId.jpg',
      '$catalogCourseId/$catalogImageId.png?token=PRIVATE_CANARY',
      '$catalogCourseId/$catalogImageId.PNG',
      '$catalogCourseId/$catalogImageId.png/extra',
      123,
      '',
    ]) {
      expect(
        () =>
            CatalogCourse.fromJson({...catalogCourseRow(), 'cover_path': path}),
        invalid,
      );
    }
  });
  test(
    'cursor validates exact paired fields, bounds and canonical UUID tie order',
    () {
      for (final row in [
        {},
        {'position': 0},
        {'id': catalogCourseId},
        {'position': -1, 'id': catalogCourseId},
        {'position': 0, 'id': 'bad'},
        {'position': 0, 'id': catalogCourseId, 'extra': true},
      ]) {
        expect(() => CatalogCursor.fromJson(row), invalid);
      }
      final first = CatalogCursor.fromJson({
        'position': 0,
        'id': catalogCourseId.toUpperCase(),
      });
      expect(
        first.compareTo(const CatalogCursor(position: 0, id: catalogCourseId)),
        0,
      );
      expect(
        first.compareTo(const CatalogCursor(position: 0, id: catalogOtherId)),
        lessThan(0),
      );
      expect(
        first.compareTo(const CatalogCursor(position: 1, id: catalogActor)),
        lessThan(0),
      );
    },
  );
  test('valid bounded page uses last returned row only when more exists', () {
    final rows = [catalogCourseRow(), catalogCourseRow(id: catalogOtherId)];
    final page = CatalogPage<CatalogCourse>.fromJson(
      catalogEnvelope(rows, more: true),
      CatalogCourse.fromJson,
      limit: 2,
    );
    expect(page.items, hasLength(2));
    expect(page.hasMore, isTrue);
    expect(page.nextCursor!.id, catalogOtherId);
    expect(() => page.items.clear(), throwsUnsupportedError);
    final last = CatalogPage<CatalogCourse>.fromJson(
      catalogEnvelope(rows),
      CatalogCourse.fromJson,
      limit: 2,
    );
    expect(last.hasMore, isFalse);
    expect(last.nextCursor, isNull);
    final empty = CatalogPage<CatalogCourse>.fromJson(
      catalogEnvelope([]),
      CatalogCourse.fromJson,
    );
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);
    expect(empty.nextCursor, isNull);
  });
  for (final scenario in [
    'duplicate',
    'reverse',
    'nonadvancing',
    'moved-cursor-id',
    'overlimit',
    'short-more',
    'empty-more',
    'wrong-cursor',
    'cursor-on-last',
    'extra',
    'bad-bool',
    'missing-cursor',
  ]) {
    test('page rejects $scenario', () {
      var envelope = catalogEnvelope([catalogCourseRow()], more: true);
      CatalogCursor? after;
      var limit = 1;
      switch (scenario) {
        case 'duplicate':
          envelope = catalogEnvelope([catalogCourseRow(), catalogCourseRow()]);
          limit = 2;
        case 'reverse':
          envelope = catalogEnvelope([
            catalogCourseRow(id: catalogOtherId),
            catalogCourseRow(),
          ]);
          limit = 2;
        case 'nonadvancing':
          after = const CatalogCursor(position: 0, id: catalogCourseId);
        case 'moved-cursor-id':
          after = const CatalogCursor(position: 0, id: catalogCourseId);
          envelope = catalogEnvelope([
            catalogCourseRow(position: 1),
          ], more: true);
        case 'overlimit':
          envelope = catalogEnvelope([
            catalogCourseRow(),
            catalogCourseRow(id: catalogOtherId),
          ]);
        case 'short-more':
          limit = 2;
        case 'empty-more':
          envelope = {'items': [], 'has_more': true, 'next_cursor': null};
        case 'wrong-cursor':
          envelope['next_cursor'] = {'position': 0, 'id': catalogOtherId};
        case 'cursor-on-last':
          envelope['has_more'] = false;
        case 'extra':
          envelope['private_payload'] = 'PRIVATE_CANARY';
        case 'bad-bool':
          envelope['has_more'] = 1;
        case 'missing-cursor':
          envelope.remove('next_cursor');
      }
      expect(
        () => CatalogPage<CatalogCourse>.fromJson(
          envelope,
          CatalogCourse.fromJson,
          limit: limit,
          after: after,
        ),
        invalid,
      );
    });
  }
  test('strictly advancing keyset accepts next page without claiming a concurrent snapshot', () {
    const after = CatalogCursor(position: 0, id: catalogCourseId);
    final page = CatalogPage<CatalogCourse>.fromJson(
      catalogEnvelope([catalogCourseRow(id: catalogOtherId)]),
      CatalogCourse.fromJson,
      after: after,
    );
    expect(page.items.single.id, catalogOtherId);
  });
  test('filter options are unique immutable full-catalog labels in C/codepoint order', () {
    final filters = CatalogFilters.fromJson({
      'categories': ['A', 'Z', 'a', 'é', '\uE000', '😀'],
      'levels': ['Beginner', 'Intermediate'],
    });
    expect(filters.categories, hasLength(6));
    expect(() => filters.categories.add('secret'), throwsUnsupportedError);
    expect(() => filters.levels.clear(), throwsUnsupportedError);
    // In UTF-16 String.compareTo puts this surrogate pair before U+E000; C does not.
    expect(
      () => CatalogFilters(categories: ['😀', '\uE000'], levels: []),
      invalid,
    );
    expect(
      () => CatalogFilters(categories: ['😀' * 120], levels: []),
      returnsNormally,
    );
  });
  test('filters reject extra keys, malformed, duplicated, reversed and oversized text', () {
    for (final row in [
      {
        'categories': ['A', 'A'],
        'levels': [],
      },
      {
        'categories': ['B', 'A'],
        'levels': [],
      },
      {
        'categories': ['A'],
        'levels': ['x' * 121],
      },
      {
        'categories': [null],
        'levels': [],
      },
      {
        'categories': ['   '],
        'levels': [],
      },
      {'categories': [], 'levels': [], 'status': 'published'},
      {'categories': [], 'levels': null},
      {'categories': []},
    ]) {
      expect(() => CatalogFilters.fromJson(row), invalid);
    }
  });
  test('ASCII space normalization preserves tabs, NBSP, Unicode and literal search symbols', () {
    expect(trimCatalogSpaces('  %_\\Civil  '), '%_\\Civil');
    expect(trimCatalogSpaces('  \t\u00a0😀\t  '), '\t\u00a0😀\t');
    expect(trimCatalogSpaces('   '), '');
  });
  test('all failures render static sanitized messages', () {
    for (final kind in CatalogFailureKind.values) {
      expect(CatalogFailure(kind).message, isNotEmpty);
      expect(
        CatalogFailure(kind).toString(),
        isNot(contains('PRIVATE_CANARY')),
      );
    }
  });
}
