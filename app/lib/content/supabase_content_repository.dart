import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_repository.dart';

/// Uses the signed-in client; database RLS remains the authority for access.
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(this.client);
  final SupabaseClient client;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on ContentFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const ContentFailure(
          'That session number is already in use for this course.',
        );
      }
      throw const ContentFailure();
    } catch (_) {
      throw const ContentFailure();
    }
  }

  void _offset(int offset) {
    if (offset < 0 || offset > maxContentInteger - contentPageSize) {
      throw const ContentFailure('Invalid page.');
    }
  }

  void _id(String id) {
    if (!RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(id)) {
      throw const ContentFailure('Invalid content identifier.');
    }
  }

  @override
  Future<List<Course>> listCourses({
    int offset = 0,
    bool includeDeleted = false,
  }) => _request(() async {
    _offset(offset);
    var query = client.from('courses').select();
    if (!includeDeleted) query = query.isFilter('deleted_at', null);
    final rows = await query
        .order('position', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + contentPageSize - 1);
    return rows.map(Course.fromJson).toList(growable: false);
  });

  @override
  Future<Course> saveCourse(CourseDraft draft, {String? id}) =>
      _request(() async {
        final validation = draft.validationMessage;
        if (validation != null) throw ContentFailure(validation);
        if (id != null) _id(id);
        final row = id == null
            ? await client
                  .from('courses')
                  .insert(draft.toJson())
                  .select()
                  .single()
            : await client
                  .from('courses')
                  .update(draft.toJson())
                  .eq('id', id)
                  .isFilter('deleted_at', null)
                  .select()
                  .single();
        return Course.fromJson(row);
      });

  @override
  Future<Course> setCourseDeleted(String id, bool deleted) =>
      _request(() async {
        _id(id);
        final row = await client
            .from('courses')
            .update({
              'deleted_at': deleted
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
            })
            .eq('id', id)
            .select()
            .single();
        final course = Course.fromJson(row);
        if (course.id.toLowerCase() != id.toLowerCase()) {
          throw const ContentFailure();
        }
        _confirmDeleted(course.isDeleted, course.status, deleted);
        return course;
      });

  void _confirmDeleted(bool actualDeleted, ContentStatus status, bool deleted) {
    if (actualDeleted != deleted ||
        (!deleted && status != ContentStatus.draft)) {
      throw const ContentFailure(
        'The requested content change could not be confirmed. Refresh the list before trying again.',
      );
    }
  }

  @override
  Future<List<CourseSession>> listSessions(
    String courseId, {
    int offset = 0,
    bool includeDeleted = false,
  }) => _request(() async {
    _id(courseId);
    _offset(offset);
    var query = client
        .from('course_sessions')
        .select()
        .eq('course_id', courseId);
    if (!includeDeleted) query = query.isFilter('deleted_at', null);
    final rows = await query
        .order('position', ascending: true)
        .order('session_number', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + contentPageSize - 1);
    return rows.map(CourseSession.fromJson).toList(growable: false);
  });

  @override
  Future<CourseSession> saveSession(
    String courseId,
    SessionDraft draft, {
    String? id,
  }) => _request(() async {
    _id(courseId);
    if (id != null) _id(id);
    final validation = draft.validationMessage;
    if (validation != null) throw ContentFailure(validation);
    // course_id is insert-only and also constrains updates to the selected course.
    final row = id == null
        ? await client
              .from('course_sessions')
              .insert({...draft.toJson(), 'course_id': courseId})
              .select()
              .single()
        : await client
              .from('course_sessions')
              .update(draft.toJson())
              .eq('id', id)
              .eq('course_id', courseId)
              .isFilter('deleted_at', null)
              .select()
              .single();
    return CourseSession.fromJson(row);
  });

  @override
  Future<CourseSession> setSessionDeleted(
    String courseId,
    String id,
    bool deleted,
  ) => _request(() async {
    _id(courseId);
    _id(id);
    final row = await client
        .from('course_sessions')
        .update({
          'deleted_at': deleted
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        })
        .eq('id', id)
        .eq('course_id', courseId)
        .select()
        .single();
    final session = CourseSession.fromJson(row);
    if (session.id.toLowerCase() != id.toLowerCase() ||
        session.courseId.toLowerCase() != courseId.toLowerCase()) {
      throw const ContentFailure();
    }
    _confirmDeleted(session.isDeleted, session.status, deleted);
    return session;
  });
}
