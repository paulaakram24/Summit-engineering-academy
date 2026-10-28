import '../catalog/catalog_models.dart' show isCatalogUuid, trimCatalogSpaces;

const paymentInstructorDefaultLimit = 20;
const paymentInstructorMaxLimit = 50;
const instructorPaymentMaxRevision = 2147483647;

final class InstructorPaymentModelFailure implements Exception {
  const InstructorPaymentModelFailure();
  String get message =>
      'The instructor payment setup data could not be verified.';
  @override
  String toString() => message;
}

void _require(bool valid) {
  if (!valid) throw const InstructorPaymentModelFailure();
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _require(value is Map<String, dynamic>);
  final row = value as Map<String, dynamic>;
  _require(row.length == keys.length && row.keys.every(keys.contains));
  return row;
}

String _id(Object? value) {
  _require(value is String && isCatalogUuid(value));
  return (value as String).toLowerCase();
}

String _name(Object? value) {
  _require(value is String);
  final text = trimCatalogSpaces(value as String);
  _require(
    text.isNotEmpty &&
        text.runes.length <= 160 &&
        !text.codeUnits.any((unit) => unit <= 31 || unit == 127),
  );
  return text;
}

String _phone(Object? value) {
  _require(value is String);
  final text = value as String;
  final match = RegExp(r'^\+?[0-9]{7,15}$').firstMatch(text);
  _require(match != null && match.end == text.length);
  return text;
}

// public.profiles.name permits controls other than PostgreSQL's forbidden NUL.
// Directory display text must not inherit the stricter recipient-name policy.
String _displayName(Object? value) {
  _require(value is String);
  final text = trimCatalogSpaces(value as String);
  _require(
    text.isNotEmpty && text.runes.length <= 120 && !text.contains('\u0000'),
  );
  return text;
}

int _revision(Object? value) {
  _require(value is int && value >= 1 && value <= instructorPaymentMaxRevision);
  return value as int;
}

enum InstructorPaymentMethodConfiguration {
  instapayOnly('instapay_only'),
  instapayAndVodafoneCash('instapay_and_vodafone_cash');

  const InstructorPaymentMethodConfiguration(this.wireValue);
  final String wireValue;

  static InstructorPaymentMethodConfiguration fromJson(Object? value) =>
      switch (value) {
        'instapay_only' => instapayOnly,
        'instapay_and_vodafone_cash' => instapayAndVodafoneCash,
        _ => throw const InstructorPaymentModelFailure(),
      };
}

/// Receiving setup only, not verified routing, an instruction or authorization.
/// Both enabled methods use this one syntactically canonical phone number.
final class InstructorPaymentProfile {
  factory InstructorPaymentProfile({
    required String instructorId,
    required String recipientName,
    required String phoneNumber,
    required InstructorPaymentMethodConfiguration methodConfiguration,
    required int revision,
  }) => InstructorPaymentProfile._(
    _id(instructorId),
    _name(recipientName),
    _phone(phoneNumber),
    methodConfiguration,
    _revision(revision),
  );

  const InstructorPaymentProfile._(
    this.instructorId,
    this.recipientName,
    this.phoneNumber,
    this.methodConfiguration,
    this.revision,
  );
  final String instructorId, recipientName, phoneNumber;
  final InstructorPaymentMethodConfiguration methodConfiguration;
  final int revision;

  factory InstructorPaymentProfile.fromJson(Object? value) {
    final row = _object(value, {
      'instructor_id',
      'recipient_name',
      'phone_number',
      'method_configuration',
      'revision',
    });
    return InstructorPaymentProfile._(
      _id(row['instructor_id']),
      _name(row['recipient_name']),
      _phone(row['phone_number']),
      InstructorPaymentMethodConfiguration.fromJson(
        row['method_configuration'],
      ),
      _revision(row['revision']),
    );
  }
}

/// Explicit course assignment; never inferred from display text or creator.
/// Session inheritance and same-course bundle enforcement are server concerns.
final class CoursePaymentInstructor {
  factory CoursePaymentInstructor({
    required String courseId,
    required String instructorId,
    required int revision,
  }) => CoursePaymentInstructor._(
    _id(courseId),
    _id(instructorId),
    _revision(revision),
  );

  const CoursePaymentInstructor._(
    this.courseId,
    this.instructorId,
    this.revision,
  );
  final String courseId, instructorId;
  final int revision;

  factory CoursePaymentInstructor.fromJson(Object? value) {
    final row = _object(value, {'course_id', 'instructor_id', 'revision'});
    return CoursePaymentInstructor._(
      _id(row['course_id']),
      _id(row['instructor_id']),
      _revision(row['revision']),
    );
  }
}

/// Safe selection projection only: no receiving profile or role claims.
final class PaymentInstructorDirectoryEntry {
  factory PaymentInstructorDirectoryEntry({
    required String instructorId,
    required String displayName,
  }) => PaymentInstructorDirectoryEntry._(
    _id(instructorId),
    _displayName(displayName),
  );

  const PaymentInstructorDirectoryEntry._(this.instructorId, this.displayName);
  final String instructorId, displayName;
  PaymentInstructorCursor get cursor =>
      PaymentInstructorCursor(instructorId: instructorId);

  factory PaymentInstructorDirectoryEntry.fromJson(Object? value) {
    final row = _object(value, {'instructor_id', 'display_name'});
    return PaymentInstructorDirectoryEntry._(
      _id(row['instructor_id']),
      _displayName(row['display_name']),
    );
  }
}

final class PaymentInstructorCursor
    implements Comparable<PaymentInstructorCursor> {
  factory PaymentInstructorCursor({required String instructorId}) =>
      PaymentInstructorCursor._(_id(instructorId));
  const PaymentInstructorCursor._(this.instructorId);
  final String instructorId;

  factory PaymentInstructorCursor.fromJson(Object? value) {
    final row = _object(value, {'instructor_id'});
    return PaymentInstructorCursor._(_id(row['instructor_id']));
  }

  Map<String, dynamic> toJson() => {'instructor_id': instructorId};

  @override
  int compareTo(PaymentInstructorCursor other) =>
      instructorId.compareTo(other.instructorId);

  @override
  bool operator ==(Object other) =>
      other is PaymentInstructorCursor && instructorId == other.instructorId;
  @override
  int get hashCode => instructorId.hashCode;
}

/// Strict ascending UUID keyset page, not a snapshot of directory membership.
/// Consumers appending pages must also reject IDs already accumulated.
final class PaymentInstructorPage {
  PaymentInstructorPage({
    required List<PaymentInstructorDirectoryEntry> items,
    required this.hasMore,
    required this.nextCursor,
    int limit = paymentInstructorDefaultLimit,
    PaymentInstructorCursor? after,
  }) : items = List.unmodifiable(items) {
    _require(limit >= 1 && limit <= paymentInstructorMaxLimit);
    _require(this.items.length <= limit);
    final ids = <String>{};
    var previous = after;
    for (final item in this.items) {
      _require(
        ids.add(item.instructorId) &&
            (previous == null || item.cursor.compareTo(previous) > 0),
      );
      previous = item.cursor;
    }
    if (hasMore) {
      _require(
        this.items.isNotEmpty &&
            this.items.length == limit &&
            nextCursor == this.items.last.cursor,
      );
    } else {
      _require(nextCursor == null);
    }
  }

  final List<PaymentInstructorDirectoryEntry> items;
  final bool hasMore;
  final PaymentInstructorCursor? nextCursor;

  factory PaymentInstructorPage.fromJson(
    Object? value, {
    int limit = paymentInstructorDefaultLimit,
    PaymentInstructorCursor? after,
  }) {
    _require(limit >= 1 && limit <= paymentInstructorMaxLimit);
    final row = _object(value, {'items', 'has_more', 'next_cursor'});
    _require(row['items'] is List && row['has_more'] is bool);
    final rows = row['items'] as List;
    _require(rows.length <= limit);
    return PaymentInstructorPage(
      items: rows.map(PaymentInstructorDirectoryEntry.fromJson).toList(),
      hasMore: row['has_more'] as bool,
      nextCursor: row['next_cursor'] == null
          ? null
          : PaymentInstructorCursor.fromJson(row['next_cursor']),
      limit: limit,
      after: after,
    );
  }
}
