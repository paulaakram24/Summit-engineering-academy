import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'instructor_payment_repository.dart';

/// Setup only: no order creation, table fallback, cache or mutation retries.
class SupabaseInstructorPaymentRepository
    implements InstructorPaymentRepository {
  SupabaseInstructorPaymentRepository(
    this.client, {
    this.timeout = const Duration(seconds: 20),
  });
  final SupabaseClient client;
  final Duration timeout;

  @override
  String? get currentActorId => client.auth.currentUser?.id;

  Never _fail(InstructorPaymentFailureKind kind) =>
      throw InstructorPaymentFailure(kind);

  void _input(bool valid) {
    if (!valid) _fail(InstructorPaymentFailureKind.invalidInput);
  }

  Session _session() {
    try {
      final session = client.auth.currentSession;
      final user = client.auth.currentUser;
      if (session != null &&
          user != null &&
          isCatalogUuid(user.id) &&
          session.user.id.toLowerCase() == user.id.toLowerCase() &&
          session.accessToken.isNotEmpty &&
          !session.isExpired) {
        return session;
      }
    } catch (_) {
      // A custom token is not an authenticated GoTrue identity.
    }
    return _fail(InstructorPaymentFailureKind.accessRequired);
  }

  void _actor(String actor, bool changed) {
    if (changed || _session().user.id.toLowerCase() != actor.toLowerCase()) {
      _fail(InstructorPaymentFailureKind.actorChanged);
    }
  }

  Future<T> _call<T>(
    String actorId,
    String rpc,
    Map<String, dynamic> params,
    T Function(Object?) decode,
  ) async {
    _input(isCatalogUuid(actorId));
    final session = _session();
    final actor = session.user.id.toLowerCase();
    if (actor != actorId.toLowerCase()) {
      _fail(InstructorPaymentFailureKind.actorChanged);
    }
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session?.user.id.toLowerCase() != actor) changed = true;
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
    } on InstructorPaymentFailure {
      rethrow;
    } on InstructorPaymentModelFailure {
      return _fail(InstructorPaymentFailureKind.invalidResponse);
    } on PostgrestException catch (error) {
      return _fail(switch ((error.code, error.message)) {
        ('42501', 'payment_setup_access_required') =>
          InstructorPaymentFailureKind.accessRequired,
        ('42501', 'payment_setup_target_unavailable') =>
          InstructorPaymentFailureKind.targetUnavailable,
        ('42501', 'payment_setup_state_conflict') =>
          InstructorPaymentFailureKind.stateConflict,
        ('22023', 'invalid_payment_setup_input') =>
          InstructorPaymentFailureKind.invalidInput,
        _ => InstructorPaymentFailureKind.requestFailed,
      });
    } on TimeoutException {
      return _fail(InstructorPaymentFailureKind.timedOut);
    } on FormatException {
      return _fail(InstructorPaymentFailureKind.invalidResponse);
    } catch (_) {
      return _fail(InstructorPaymentFailureKind.requestFailed);
    } finally {
      await subscription.cancel();
      _actor(actor, changed);
    }
  }

  @override
  Future<InstructorPaymentProfile?> getMyProfile({required String actorId}) =>
      _call(actorId, 'get_my_instructor_payment_profile', {}, (value) {
        if (value == null) return null;
        final profile = InstructorPaymentProfile.fromJson(value);
        if (profile.instructorId != actorId.toLowerCase()) {
          _fail(InstructorPaymentFailureKind.invalidResponse);
        }
        return profile;
      });

  @override
  Future<InstructorPaymentProfile> saveMyProfile(
    SaveInstructorPaymentProfileRequest request,
  ) => _call(
    request.actorId,
    'save_my_instructor_payment_profile',
    {
      'p_recipient_name': request.recipientName,
      'p_phone_number': request.phoneNumber,
      'p_method_configuration': request.methodConfiguration.wireValue,
      'p_expected_revision': request.expectedRevision,
    },
    (value) {
      final profile = InstructorPaymentProfile.fromJson(value);
      if (profile.instructorId != request.actorId ||
          profile.recipientName != request.recipientName ||
          profile.phoneNumber != request.phoneNumber ||
          profile.methodConfiguration != request.methodConfiguration ||
          profile.revision != request.expectedRevision + 1) {
        _fail(InstructorPaymentFailureKind.invalidResponse);
      }
      return profile;
    },
  );

  @override
  Future<CoursePaymentInstructor?> getCourseInstructor({
    required String actorId,
    required String courseId,
  }) async {
    _input(isCatalogUuid(courseId));
    return _call(
      actorId,
      'get_course_payment_instructor',
      {'p_course_id': courseId.toLowerCase()},
      (value) {
        if (value == null) return null;
        final binding = CoursePaymentInstructor.fromJson(value);
        if (binding.courseId != courseId.toLowerCase()) {
          _fail(InstructorPaymentFailureKind.invalidResponse);
        }
        return binding;
      },
    );
  }

  @override
  Future<CoursePaymentInstructor> setCourseInstructor(
    SetCoursePaymentInstructorRequest request,
  ) => _call(
    request.actorId,
    'set_course_payment_instructor',
    {
      'p_course_id': request.courseId,
      'p_instructor_id': request.instructorId,
      'p_expected_revision': request.expectedRevision,
    },
    (value) {
      final binding = CoursePaymentInstructor.fromJson(value);
      if (binding.courseId != request.courseId ||
          binding.instructorId != request.instructorId ||
          binding.revision != request.expectedRevision + 1) {
        _fail(InstructorPaymentFailureKind.invalidResponse);
      }
      return binding;
    },
  );

  @override
  Future<PaymentInstructorPage> listInstructors({
    required String actorId,
    PaymentInstructorCursor? after,
    int limit = paymentInstructorDefaultLimit,
  }) async {
    _input(limit >= 1 && limit <= paymentInstructorMaxLimit);
    return _call(
      actorId,
      'list_payment_instructors',
      {'p_after_id': after?.instructorId, 'p_limit': limit},
      (value) =>
          PaymentInstructorPage.fromJson(value, limit: limit, after: after),
    );
  }
}
