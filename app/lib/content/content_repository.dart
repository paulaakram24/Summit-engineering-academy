import 'content_models.dart';
export 'content_models.dart';

abstract class ContentRepository {
  Future<List<Course>> listCourses({
    int offset = 0,
    bool includeDeleted = false,
  });
  Future<Course> saveCourse(CourseDraft draft, {String? id});
  Future<Course> setCourseDeleted(String id, bool deleted);
  Future<List<CourseSession>> listSessions(
    String courseId, {
    int offset = 0,
    bool includeDeleted = false,
  });
  Future<CourseSession> saveSession(
    String courseId,
    SessionDraft draft, {
    String? id,
  });
  Future<CourseSession> setSessionDeleted(
    String courseId,
    String id,
    bool deleted,
  );
}
