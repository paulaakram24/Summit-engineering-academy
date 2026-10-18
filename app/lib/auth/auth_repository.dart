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
  bool get complete =>
      name.trim().isNotEmpty &&
      name.trim().length <= 120 &&
      phone.trim().isNotEmpty &&
      phone.trim().length <= 32 &&
      university.trim().isNotEmpty &&
      university.trim().length <= 160;
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
