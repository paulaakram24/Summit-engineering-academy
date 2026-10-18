import 'dart:async';

enum SessionEvent { signedIn, restored, refreshed, recovery, signedOut }

class AccountProfile {
  const AccountProfile({
    required this.name,
    required this.phone,
    required this.university,
  });
  final String name;
  final String phone;
  final String university;
  static String? validateName(String? value) =>
      (value ?? '').trim().isEmpty || (value ?? '').trim().length > 120
      ? 'Use 1–120 characters for your name.'
      : null;

  static String? validatePhone(String? value) {
    final phone = (value ?? '').trim();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return phone.length <= 32 &&
            RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) &&
            digits.length >= 7 &&
            digits.length <= 15
        ? null
        : 'Enter a valid phone number with 7–15 digits.';
  }

  static String? validateUniversity(String? value) =>
      (value ?? '').trim().isEmpty || (value ?? '').trim().length > 160
      ? 'Use 1–160 characters for your university.'
      : null;

  String? get validationMessage =>
      validateName(name) ??
      validatePhone(phone) ??
      validateUniversity(university);
  bool get complete => validationMessage == null;
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'university': university.trim(),
  };
  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    university: json['university'] as String? ?? '',
  );
}

class AccessContext {
  const AccessContext(this.role, this.deviceId);
  final String role;
  final String deviceId;
  factory AccessContext.fromJson(dynamic value) {
    if (value is! Map ||
        !['student', 'admin'].contains(value['role']) ||
        value['device_id'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(value['device_id'] as String)) {
      throw const AccountFailure('invalid_access');
    }
    return AccessContext(value['role'] as String, value['device_id'] as String);
  }
}

class AccountFailure implements Exception {
  const AccountFailure(this.code);
  final String code;
}

abstract class AuthRepository {
  Stream<SessionEvent> get events;
  bool get hasSession;
  String? get email;
  Future<bool> recoveryPending();
  Future<void> setRecoveryPending(bool value);
  Future<void> signUp(String email, String password, AccountProfile profile);
  Future<void> signIn(String email, String password);
  Future<void> googleSignIn();
  Future<void> resendVerification(String email);
  Future<void> verifyEmail(String email, String code);
  Future<void> sendRecovery(String email);
  Future<void> updatePassword(String password);
  Future<AccessContext> registerDevice();
  Future<AccessContext> getAccessContext();
  Future<AccountProfile> fetchProfile();
  Future<void> saveProfile(AccountProfile profile);
  Future<void> endSession();
  Future<void> signOut();
  Future<void> dispose();
}
