import '../catalog/catalog_models.dart' show isCatalogUuid, trimCatalogSpaces;

const pendingOrderDefaultLimit = 20;
const pendingOrderMaxLimit = 50;
const pendingOrderMaxInteger = 2147483647;

enum PendingOrderKind { course, session }

/// An intent only: not a payment submission, approval, purchase or access grant.
enum PendingOrderState { pending }

final class PendingOrderModelFailure implements Exception {
  const PendingOrderModelFailure();
  String get message => 'The pending-order data could not be verified.';
  @override
  String toString() => message;
}

void _require(bool valid) {
  if (!valid) throw const PendingOrderModelFailure();
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _require(value is Map<String, dynamic>);
  final row = value as Map<String, dynamic>;
  _require(row.length == keys.length && row.keys.every(keys.contains));
  return row;
}

String _uuid(Object? value) {
  _require(value is String && isCatalogUuid(value));
  return (value as String).toLowerCase();
}

String _title(Object? value) {
  _require(value is String);
  final text = value as String;
  _require(
    text.runes.length <= 160 &&
        trimCatalogSpaces(text).isNotEmpty &&
        !text.contains('\u0000'),
  );
  return text;
}

void _utc(DateTime value) =>
    _require(value.isUtc && value.year >= 1 && value.year <= 9999);

/// Explicit ISO timezone required. Validate components before offset conversion:
/// DateTime.parse accepts calendar rollover and truncates fractional digits.
/// PostgreSQL's six fractional digits must survive cursor round-trips exactly.
DateTime _instant(Object? value) {
  _require(value is String);
  final text = value as String;
  final match = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,6}))?([Zz]|[+-][0-9]{2}:[0-9]{2})$',
  ).firstMatch(text);
  _require(match != null && match.end == text.length);
  final parts = List.generate(
    6,
    (index) => int.parse(match!.group(index + 1)!),
  );
  final year = parts[0], month = parts[1], day = parts[2];
  final hour = parts[3], minute = parts[4], second = parts[5];
  _require(
    year >= 1 &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= 31 &&
        hour <= 23 &&
        minute <= 59 &&
        second <= 59,
  );
  final fraction = int.parse((match!.group(7) ?? '').padRight(6, '0'));
  final wall = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    fraction ~/ 1000,
    fraction % 1000,
  );
  _require(wall.year == year && wall.month == month && wall.day == day);
  final zone = match.group(8)!;
  var offset = 0;
  if (zone.toUpperCase() != 'Z') {
    final hours = int.parse(zone.substring(1, 3)),
        minutes = int.parse(zone.substring(4, 6));
    _require(hours <= 23 && minutes <= 59);
    offset = (hours * 60 + minutes) * (zone.startsWith('-') ? -1 : 1);
  }
  final result = wall.subtract(Duration(minutes: offset));
  _utc(result);
  return result;
}

/// Safe immutable intent projection. It contains no buyer, receipt, protected
/// payload, delivery URL or expiry field, and cannot describe paid access.
final class PendingOrder {
  factory PendingOrder({
    required String id,
    required PendingOrderKind kind,
    required String courseId,
    required String? sessionId,
    required String courseTitleSnapshot,
    required String? sessionTitleSnapshot,
    required int pricePiasters,
    required DateTime createdAt,
  }) {
    final normalizedId = _uuid(id), normalizedCourseId = _uuid(courseId);
    _title(courseTitleSnapshot);
    _require(pricePiasters >= 0 && pricePiasters <= pendingOrderMaxInteger);
    _utc(createdAt);
    String? normalizedSessionId;
    if (kind == PendingOrderKind.course) {
      _require(sessionId == null && sessionTitleSnapshot == null);
    } else {
      normalizedSessionId = _uuid(sessionId);
      _title(sessionTitleSnapshot);
    }
    return PendingOrder._(
      normalizedId,
      kind,
      normalizedCourseId,
      normalizedSessionId,
      courseTitleSnapshot,
      sessionTitleSnapshot,
      pricePiasters,
      createdAt,
    );
  }

  const PendingOrder._(
    this.id,
    this.kind,
    this.courseId,
    this.sessionId,
    this.courseTitleSnapshot,
    this.sessionTitleSnapshot,
    this.pricePiasters,
    this.createdAt,
  );
  final String id, courseId;
  final PendingOrderKind kind;
  final String? sessionId;
  final String courseTitleSnapshot;
  final String? sessionTitleSnapshot;
  final int pricePiasters;
  final DateTime createdAt;
  String get currency => 'EGP';
  PendingOrderState get state => PendingOrderState.pending;
  PendingOrderCursor get cursor =>
      PendingOrderCursor(createdAt: createdAt, id: id);

  factory PendingOrder.fromJson(Object? value) {
    final row = _object(value, {
      'id',
      'kind',
      'course_id',
      'session_id',
      'course_title_snapshot',
      'session_title_snapshot',
      'price_piasters',
      'currency',
      'state',
      'created_at',
    });
    _require(
      row['currency'] == 'EGP' &&
          row['state'] == 'pending' &&
          row['price_piasters'] is int,
    );
    final kind = switch (row['kind']) {
      'course' => PendingOrderKind.course,
      'session' => PendingOrderKind.session,
      _ => throw const PendingOrderModelFailure(),
    };
    _require(row['session_id'] == null || row['session_id'] is String);
    _require(
      row['session_title_snapshot'] == null ||
          row['session_title_snapshot'] is String,
    );
    return PendingOrder(
      id: _uuid(row['id']),
      kind: kind,
      courseId: _uuid(row['course_id']),
      sessionId: row['session_id'] as String?,
      courseTitleSnapshot: _title(row['course_title_snapshot']),
      sessionTitleSnapshot: row['session_title_snapshot'] as String?,
      pricePiasters: row['price_piasters'] as int,
      createdAt: _instant(row['created_at']),
    );
  }
}

/// Descending created_at, then descending UUID, matching the proposed keyset.
/// compareTo is negative for a newer entry; after-boundary entries are positive.
final class PendingOrderCursor implements Comparable<PendingOrderCursor> {
  factory PendingOrderCursor({
    required DateTime createdAt,
    required String id,
  }) {
    _utc(createdAt);
    return PendingOrderCursor._(createdAt, _uuid(id));
  }
  const PendingOrderCursor._(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;
  factory PendingOrderCursor.fromJson(Object? value) {
    final row = _object(value, {'created_at', 'id'});
    return PendingOrderCursor(
      createdAt: _instant(row['created_at']),
      id: _uuid(row['id']),
    );
  }
  Map<String, dynamic> toJson() => {
    'created_at': createdAt.toIso8601String(),
    'id': id,
  };
  @override
  int compareTo(PendingOrderCursor other) {
    final timestamps = other.createdAt.compareTo(createdAt);
    return timestamps != 0 ? timestamps : other.id.compareTo(id);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingOrderCursor &&
      createdAt == other.createdAt &&
      id == other.id;
  @override
  int get hashCode => Object.hash(createdAt, id);
}

/// One verified page, not a cross-request snapshot. A future list consumer must
/// also reject IDs already accumulated across earlier pages; no runtime uses
/// this model until its server contract is verified.
final class PendingOrderPage {
  PendingOrderPage({
    required List<PendingOrder> items,
    required this.hasMore,
    required this.nextCursor,
    int limit = pendingOrderDefaultLimit,
    PendingOrderCursor? after,
  }) : items = List.unmodifiable(items) {
    _require(
      limit >= 1 && limit <= pendingOrderMaxLimit && this.items.length <= limit,
    );
    final ids = <String>{};
    var previous = after;
    for (final item in this.items) {
      _require(
        ids.add(item.id) &&
            item.id != after?.id &&
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
  final List<PendingOrder> items;
  final bool hasMore;
  final PendingOrderCursor? nextCursor;
  factory PendingOrderPage.fromJson(
    Object? value, {
    int limit = pendingOrderDefaultLimit,
    PendingOrderCursor? after,
  }) {
    final row = _object(value, {'items', 'has_more', 'next_cursor'});
    _require(
      limit >= 1 &&
          limit <= pendingOrderMaxLimit &&
          row['items'] is List &&
          row['has_more'] is bool,
    );
    final rows = row['items'] as List;
    _require(rows.length <= limit);
    return PendingOrderPage(
      items: rows.map(PendingOrder.fromJson).toList(growable: false),
      hasMore: row['has_more'] as bool,
      nextCursor: row['next_cursor'] == null
          ? null
          : PendingOrderCursor.fromJson(row['next_cursor']),
      limit: limit,
      after: after,
    );
  }
}
