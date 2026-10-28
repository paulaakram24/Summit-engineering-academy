import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'instructor_payment_models.dart';
export 'instructor_payment_models.dart';

enum InstructorPaymentFailureKind {
  invalidInput,
  accessRequired,
  actorChanged,
  targetUnavailable,
  stateConflict,
  invalidResponse,
  timedOut,
  requestFailed,
}

final class InstructorPaymentFailure implements Exception {
  const InstructorPaymentFailure(this.kind);
  final InstructorPaymentFailureKind kind;
  String get message => switch (kind) {
    InstructorPaymentFailureKind.invalidInput =>
      'Check the receiving details and selection.',
    InstructorPaymentFailureKind.accessRequired =>
      'Verify administrator access before opening payment setup.',
    InstructorPaymentFailureKind.actorChanged =>
      'The signed-in account changed. Reopen payment setup.',
    InstructorPaymentFailureKind.targetUnavailable =>
      'This course or instructor is unavailable. Refresh before continuing.',
    InstructorPaymentFailureKind.stateConflict =>
      'Payment setup changed elsewhere. Refresh before continuing.',
    InstructorPaymentFailureKind.invalidResponse => 'The payment setup response could not be verified. Refresh before continuing.',
    InstructorPaymentFailureKind.timedOut =>
      'Payment setup timed out. Refresh to check the current state.',
    InstructorPaymentFailureKind.requestFailed =>
      'Unable to verify payment setup. Refresh before continuing.',
  };
  @override
  String toString() => message;
}

void _input(bool valid) {
  if (!valid) {
    throw const InstructorPaymentFailure(
      InstructorPaymentFailureKind.invalidInput,
    );
  }
}

final class SaveInstructorPaymentProfileRequest {
  factory SaveInstructorPaymentProfileRequest({
    required String actorId,
    required String recipientName,
    required String phoneNumber,
    required InstructorPaymentMethodConfiguration methodConfiguration,
    required int expectedRevision,
  }) {
    _input(
      expectedRevision >= 0 && expectedRevision < instructorPaymentMaxRevision,
    );
    try {
      final validated = InstructorPaymentProfile(
        instructorId: actorId,
        recipientName: recipientName,
        phoneNumber: phoneNumber,
        methodConfiguration: methodConfiguration,
        revision: expectedRevision + 1,
      );
      return SaveInstructorPaymentProfileRequest._(
        validated.instructorId,
        validated.recipientName,
        validated.phoneNumber,
        validated.methodConfiguration,
        expectedRevision,
      );
    } on InstructorPaymentModelFailure {
      throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.invalidInput,
      );
    }
  }
  const SaveInstructorPaymentProfileRequest._(
    this.actorId,
    this.recipientName,
    this.phoneNumber,
    this.methodConfiguration,
    this.expectedRevision,
  );
  final String actorId, recipientName, phoneNumber;
  final InstructorPaymentMethodConfiguration methodConfiguration;
  final int expectedRevision;
}

final class SetCoursePaymentInstructorRequest {
  factory SetCoursePaymentInstructorRequest({
    required String actorId,
    required String courseId,
    required String instructorId,
    required int expectedRevision,
  }) {
    _input(
      isCatalogUuid(actorId) &&
          expectedRevision >= 0 &&
          expectedRevision < instructorPaymentMaxRevision,
    );
    try {
      final validated = CoursePaymentInstructor(
        courseId: courseId,
        instructorId: instructorId,
        revision: expectedRevision + 1,
      );
      return SetCoursePaymentInstructorRequest._(
        actorId.toLowerCase(),
        validated.courseId,
        validated.instructorId,
        expectedRevision,
      );
    } on InstructorPaymentModelFailure {
      throw const InstructorPaymentFailure(
        InstructorPaymentFailureKind.invalidInput,
      );
    }
  }
  const SetCoursePaymentInstructorRequest._(
    this.actorId,
    this.courseId,
    this.instructorId,
    this.expectedRevision,
  );
  final String actorId, courseId, instructorId;
  final int expectedRevision;
}

/// Admin setup only. Actor is a local guard, never server ownership input.
/// Mutations are not automatically retried; callers refetch uncertain results.
abstract class InstructorPaymentRepository {
  String? get currentActorId;
  Future<InstructorPaymentProfile?> getMyProfile({required String actorId});
  Future<InstructorPaymentProfile> saveMyProfile(
    SaveInstructorPaymentProfileRequest request,
  );
  Future<CoursePaymentInstructor?> getCourseInstructor({
    required String actorId,
    required String courseId,
  });
  Future<CoursePaymentInstructor> setCourseInstructor(
    SetCoursePaymentInstructorRequest request,
  );
  Future<PaymentInstructorPage> listInstructors({
    required String actorId,
    PaymentInstructorCursor? after,
    int limit = paymentInstructorDefaultLimit,
  });
}
