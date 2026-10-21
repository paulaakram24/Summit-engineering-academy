import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog_repository.dart';
import 'bookmark_repository.dart';

/// Only the frozen bookmark RPCs. No local persistence, table fallback or
/// ownership/media capabilities. The caller must refresh uncertain mutations.
class SupabaseBookmarkRepository implements BookmarkRepository {
  SupabaseBookmarkRepository(
    this.client, {
    this.timeout = const Duration(seconds: 20),
  });
  final SupabaseClient client;
  final Duration timeout;
  @override
  String? get currentActorId {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Session _session() {
    try {
      final session = client.auth.currentSession;
      final actor = client.auth.currentUser?.id;
      if (session != null &&
          actor != null &&
          isCatalogUuid(actor) &&
          session.user.id.toLowerCase() == actor.toLowerCase() &&
          session.accessToken.isNotEmpty &&
          !session.isExpired) {
        return session;
      }
    } catch (_) {
      /* A custom token alone is not an admitted identity. */
    }
    throw const BookmarkFailure(BookmarkFailureKind.accessRequired);
  }

  void _actor(String actor, bool changed) {
    if (changed || _session().user.id.toLowerCase() != actor.toLowerCase()) {
      throw const BookmarkFailure(BookmarkFailureKind.actorChanged);
    }
  }

  void _input(bool valid) {
    if (!valid) throw const BookmarkFailure(BookmarkFailureKind.invalidInput);
  }

  Future<T> _call<T>(
    String rpc,
    Map<String, dynamic> params,
    T Function(Object?) decode, {
    String? expectedActor,
  }) async {
    final session = _session();
    final actor = session.user.id;
    if (expectedActor != null &&
        actor.toLowerCase() != expectedActor.toLowerCase()) {
      throw const BookmarkFailure(BookmarkFailureKind.actorChanged);
    }
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session?.user.id.toLowerCase() != actor.toLowerCase()) {
          changed = true;
        }
      },
      onError: (Object _) {
        changed = true;
      },
    );
    try {
      _actor(actor, changed);
      final result = await client
          .rpc(rpc, params: params)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(timeout);
      _actor(actor, changed);
      return decode(result);
    } on BookmarkFailure {
      rethrow;
    } on CatalogFailure {
      throw const BookmarkFailure(BookmarkFailureKind.invalidResponse);
    } on PostgrestException catch (error) {
      throw BookmarkFailure(switch ((error.code, error.message)) {
        ('42501', 'bookmark_access_required') =>
          BookmarkFailureKind.accessRequired,
        ('42501', 'bookmark_course_unavailable') =>
          BookmarkFailureKind.courseUnavailable,
        ('42501', 'bookmark_state_conflict') =>
          BookmarkFailureKind.stateConflict,
        ('22023', 'invalid_bookmark_input') => BookmarkFailureKind.invalidInput,
        _ => BookmarkFailureKind.requestFailed,
      });
    } on TimeoutException {
      throw const BookmarkFailure(BookmarkFailureKind.timedOut);
    } on FormatException {
      throw const BookmarkFailure(BookmarkFailureKind.invalidResponse);
    } catch (_) {
      throw const BookmarkFailure(BookmarkFailureKind.requestFailed);
    } finally {
      await subscription.cancel();
      _actor(actor, changed);
    }
  }

  @override
  Future<CourseBookmark?> getBookmark(String courseId) async {
    _input(isCatalogUuid(courseId));
    return _call(
      'get_course_bookmark',
      {'p_course_id': courseId},
      (value) => value == null
          ? null
          : CourseBookmark.fromJson(value, expectedCourseId: courseId),
    );
  }

  @override
  Future<CourseBookmark> setBookmark(SetCourseBookmarkRequest request) async {
    _input(
      isCatalogUuid(request.actorId) &&
          isCatalogUuid(request.courseId) &&
          request.expectedRevision >= 0 &&
          request.expectedRevision < catalogMaxInteger,
    );
    return _call(
      'set_course_bookmark',
      {
        'p_course_id': request.courseId,
        'p_saved': request.saved,
        'p_expected_revision': request.expectedRevision,
      },
      (value) {
        final state = CourseBookmark.fromJson(
          value,
          expectedCourseId: request.courseId,
        );
        if (state.saved != request.saved ||
            state.revision != request.expectedRevision + 1) {
          throw const BookmarkFailure(BookmarkFailureKind.invalidResponse);
        }
        return state;
      },
      expectedActor: request.actorId,
    );
  }

  @override
  Future<CatalogPage<CatalogCourse>> listSavedCourses({
    CatalogCursor? after,
    int limit = 20,
  }) async {
    _input(
      limit >= 1 &&
          limit <= catalogMaxLimit &&
          (after == null || after.isValid),
    );
    return _call(
      'list_saved_courses',
      {
        'p_after_position': after?.position,
        'p_after_id': after?.id,
        'p_limit': limit,
      },
      (value) => CatalogPage<CatalogCourse>.fromJson(
        value,
        CatalogCourse.fromJson,
        limit: limit,
        after: after,
      ),
    );
  }
}
