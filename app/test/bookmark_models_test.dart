import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/bookmarks/bookmark_repository.dart';
import 'package:summit_academy/catalog/catalog_repository.dart'
    show CatalogFailure;

import 'catalog_models_test.dart' show catalogCourseId, catalogOtherId;

void main() {
  final invalid = throwsA(
    isA<BookmarkFailure>().having(
      (e) => e.kind,
      'kind',
      BookmarkFailureKind.invalidResponse,
    ),
  );
  test('bookmark is only same-course UUID and strictly boolean state', () {
    for (final saved in [true, false]) {
      final state = CourseBookmark.fromJson({
        'course_id': catalogCourseId,
        'saved': saved,
        'revision': 0,
      }, expectedCourseId: catalogCourseId);
      expect(state.courseId, catalogCourseId);
      expect(state.saved, saved);
    }
  });
  for (final value in [
    null,
    [],
    'PRIVATE_CANARY',
    {},
    {'course_id': catalogCourseId, 'revision': 0},
    {'saved': true, 'revision': 0},
    {'course_id': catalogOtherId, 'saved': true, 'revision': 0},
    {'course_id': 'bad', 'saved': true, 'revision': 0},
    {'course_id': catalogCourseId, 'saved': 1, 'revision': 0},
    {'course_id': catalogCourseId, 'saved': null, 'revision': 0},
    {
      'course_id': catalogCourseId,
      'saved': true,
      'revision': 0,
      'owner_id': 'PRIVATE_CANARY',
    },
    {
      'course_id': catalogCourseId,
      'saved': false,
      'revision': 0,
      'body_text': 'PRIVATE_CANARY',
    },
  ]) {
    test('malformed or overbroad state rejected $value', () {
      expect(
        () => CourseBookmark.fromJson(value, expectedCourseId: catalogCourseId),
        invalid,
      );
    });
  }
  test('immutable intent retains exact actor, course and desired state', () {
    const intent = SetCourseBookmarkRequest(
      actorId: catalogOtherId,
      courseId: catalogCourseId,
      saved: false,
      expectedRevision: 3,
    );
    expect(intent.actorId, catalogOtherId);
    expect(intent.courseId, catalogCourseId);
    expect(intent.saved, isFalse);
    expect(intent.expectedRevision, 3);
  });
  test(
    'revision requires integer int32 range with no coercion or missing field',
    () {
      for (final revision in [-1, 2147483648, 1.0, '1', null, true]) {
        expect(
          () => CourseBookmark.fromJson({
            'course_id': catalogCourseId,
            'saved': true,
            'revision': revision,
          }, expectedCourseId: catalogCourseId),
          invalid,
        );
      }
      for (final revision in [0, 2147483647]) {
        expect(
          CourseBookmark.fromJson({
            'course_id': catalogCourseId,
            'saved': false,
            'revision': revision,
          }, expectedCourseId: catalogCourseId).revision,
          revision,
        );
      }
      expect(
        () => CourseBookmark.fromJson({
          'course_id': catalogCourseId,
          'saved': false,
        }, expectedCourseId: catalogCourseId),
        invalid,
      );
    },
  );
  test('extra fields rejected even with valid revision', () {
    expect(
      () => CourseBookmark.fromJson({
        'course_id': catalogCourseId,
        'saved': true,
        'revision': 3,
        'owner': 'PRIVATE_CANARY',
      }, expectedCourseId: catalogCourseId),
      invalid,
    );
  });
  test('failures have static sanitized text, not catalog exceptions', () {
    for (final kind in BookmarkFailureKind.values) {
      expect(BookmarkFailure(kind), isNot(isA<CatalogFailure>()));
      expect(
        BookmarkFailure(kind).toString(),
        isNot(contains('PRIVATE_CANARY')),
      );
      expect(BookmarkFailure(kind).message, isNotEmpty);
    }
  });
}
