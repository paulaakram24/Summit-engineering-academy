import '../catalog/catalog_repository.dart';
export '../catalog/catalog_repository.dart'
    show CatalogCourse, CatalogPage, CatalogCursor;

const bookmarkDisclaimer = 'Saved for later—not purchased or enrolled.';

enum BookmarkFailureKind {
  invalidInput,
  accessRequired,
  actorChanged,
  courseUnavailable,
  stateConflict,
  invalidResponse,
  timedOut,
  requestFailed,
}

final class BookmarkFailure implements Exception {
  const BookmarkFailure(this.kind);
  final BookmarkFailureKind kind;
  String get message => switch (kind) {
    BookmarkFailureKind.invalidInput =>
      'Check the saved course and page settings.',
    BookmarkFailureKind.accessRequired =>
      'Verify account access before opening saved courses.',
    BookmarkFailureKind.actorChanged =>
      'The signed-in account changed. Reopen saved courses.',
    BookmarkFailureKind.courseUnavailable =>
      'This course is unavailable. Refresh the course list.',
    BookmarkFailureKind.stateConflict =>
      'Saved-course state changed. Refresh before another change.',
    BookmarkFailureKind.invalidResponse => 'The saved-course response could not be verified. Refresh before continuing.',
    BookmarkFailureKind.timedOut =>
      'Loading saved courses timed out. Refresh before continuing.',
    BookmarkFailureKind.requestFailed =>
      'Unable to verify saved courses. Check your connection and refresh.',
  };
  @override
  String toString() => message;
}

final class CourseBookmark {
  const CourseBookmark({
    required this.courseId,
    required this.saved,
    required this.revision,
  });
  final String courseId;
  final bool saved;
  final int revision;
  factory CourseBookmark.fromJson(
    Object? value, {
    required String expectedCourseId,
  }) {
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        !value.containsKey('course_id') ||
        !value.containsKey('saved') ||
        value['course_id'] is! String ||
        !isCatalogUuid(value['course_id'] as String) ||
        (value['course_id'] as String).toLowerCase() !=
            expectedCourseId.toLowerCase() ||
        value['saved'] is! bool ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        (value['revision'] as int) > catalogMaxInteger) {
      throw const BookmarkFailure(BookmarkFailureKind.invalidResponse);
    }
    return CourseBookmark(
      courseId: value['course_id'] as String,
      saved: value['saved'] as bool,
      revision: value['revision'] as int,
    );
  }
}

/// Capture the live actor exactly when the user chooses an explicit state.
/// Retaining this request never authorizes replay under another account.
final class SetCourseBookmarkRequest {
  const SetCourseBookmarkRequest({
    required this.actorId,
    required this.courseId,
    required this.saved,
    required this.expectedRevision,
  });
  final String actorId, courseId;
  final bool saved;
  final int expectedRevision;
}

abstract class BookmarkRepository {
  String? get currentActorId;
  Future<CourseBookmark?> getBookmark(String courseId);
  Future<CourseBookmark> setBookmark(SetCourseBookmarkRequest request);

  /// Capture actorId before confirmation; it is a client guard, not an RPC
  /// parameter. Only the current actor's unavailable references are removed.
  Future<int> clearUnavailableBookmarks({required String actorId});
  Future<CatalogPage<CatalogCourse>> listSavedCourses({
    CatalogCursor? after,
    int limit = 20,
  });
}
