import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_repository.dart';

/// Only the four published/admission-scoped RPCs. No table/admin fallbacks,
/// cached account data, storage reads, writes, signing or media capabilities.
class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(
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
      /* Custom token clients have no authenticated GoTrue identity. */
    }
    throw const CatalogFailure(CatalogFailureKind.accessRequired);
  }

  void _actor(String captured, bool changed) {
    final session = _session();
    if (changed || session.user.id.toLowerCase() != captured.toLowerCase()) {
      throw const CatalogFailure(CatalogFailureKind.actorChanged);
    }
  }

  Future<T> _read<T>(
    String function,
    Map<String, dynamic> parameters,
    T Function(Object?) decode,
  ) async {
    final session = _session();
    final actor = session.user.id;
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
      final response = await client
          .rpc(function, params: parameters)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(timeout);
      _actor(actor, changed);
      return decode(response);
    } on CatalogFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw CatalogFailure(switch ((error.code, error.message)) {
        ('42501', 'catalog_access_required') =>
          CatalogFailureKind.accessRequired,
        ('22023', 'invalid_catalog_input') => CatalogFailureKind.invalidInput,
        _ => CatalogFailureKind.requestFailed,
      });
    } on TimeoutException {
      throw const CatalogFailure(CatalogFailureKind.timedOut);
    } on FormatException {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    } catch (_) {
      throw const CatalogFailure(CatalogFailureKind.requestFailed);
    } finally {
      await subscription.cancel();
      _actor(actor, changed);
    }
  }

  void _input(bool valid) {
    if (!valid) throw const CatalogFailure(CatalogFailureKind.invalidInput);
  }

  void _pageInput(int limit, CatalogCursor? after) => _input(
    limit >= 1 && limit <= catalogMaxLimit && (after == null || after.isValid),
  );
  String? _filter(String? value) {
    if (value == null) return null;
    final text = trimCatalogSpaces(value);
    _input(text.runes.length <= 120 && !text.contains('\u0000'));
    return text.isEmpty ? null : text;
  }

  @override
  Future<CatalogPage<CatalogCourse>> listCourses({
    String? search = '',
    String? category,
    String? level,
    CatalogCursor? after,
    int limit = catalogDefaultLimit,
  }) async {
    _pageInput(limit, after);
    _input(search != null);
    final query = trimCatalogSpaces(search!);
    _input(query.runes.length <= 100 && !query.contains('\u0000'));
    final categoryFilter = _filter(category), levelFilter = _filter(level);
    return _read(
      'list_catalog_courses',
      {
        'p_search': query,
        'p_category': categoryFilter,
        'p_level': levelFilter,
        'p_after_position': after?.position,
        'p_after_id': after?.id,
        'p_limit': limit,
      },
      (value) {
        final page = CatalogPage<CatalogCourse>.fromJson(
          value,
          CatalogCourse.fromJson,
          limit: limit,
          after: after,
        );
        if (page.items.any(
          (row) =>
              (categoryFilter != null &&
                  trimCatalogSpaces(row.category) != categoryFilter) ||
              (levelFilter != null &&
                  trimCatalogSpaces(row.level) != levelFilter),
        )) {
          throw const CatalogFailure(CatalogFailureKind.invalidResponse);
        }
        return page;
      },
    );
  }

  @override
  Future<CatalogCourse?> getCourse(String courseId) async {
    _input(isCatalogUuid(courseId));
    return _read('get_catalog_course', {'p_course_id': courseId}, (value) {
      if (value == null) return null;
      final course = CatalogCourse.fromJson(value);
      if (course.id.toLowerCase() != courseId.toLowerCase()) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      return course;
    });
  }

  @override
  Future<CatalogPage<CatalogSession>> listSessions(
    String courseId, {
    CatalogCursor? after,
    int limit = catalogDefaultLimit,
  }) async {
    _input(isCatalogUuid(courseId));
    _pageInput(limit, after);
    return _read(
      'list_catalog_sessions',
      {
        'p_course_id': courseId,
        'p_after_position': after?.position,
        'p_after_id': after?.id,
        'p_limit': limit,
      },
      (value) {
        final page = CatalogPage<CatalogSession>.fromJson(
          value,
          CatalogSession.fromJson,
          limit: limit,
          after: after,
        );
        if (page.items.any(
          (row) => row.courseId.toLowerCase() != courseId.toLowerCase(),
        )) {
          throw const CatalogFailure(CatalogFailureKind.invalidResponse);
        }
        return page;
      },
    );
  }

  @override
  Future<CatalogFilters> getFilters() =>
      _read('get_catalog_filters', {}, CatalogFilters.fromJson);
}
