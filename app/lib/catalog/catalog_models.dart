const catalogDefaultLimit = 20;
const catalogMaxLimit = 50;
const catalogMaxInteger = 2147483647;

enum CatalogFailureKind {
  invalidInput,
  accessRequired,
  actorChanged,
  invalidResponse,
  timedOut,
  requestFailed,
}

final class CatalogFailure implements Exception {
  const CatalogFailure(this.kind);
  final CatalogFailureKind kind;
  String get message => switch (kind) {
    CatalogFailureKind.invalidInput =>
      'Check the catalog search, filters and page settings.',
    CatalogFailureKind.accessRequired =>
      'Sign in and verify account access before opening the catalog.',
    CatalogFailureKind.actorChanged =>
      'The signed-in account changed. Refresh the catalog before continuing.',
    CatalogFailureKind.invalidResponse =>
      'The catalog response could not be verified. Refresh before continuing.',
    CatalogFailureKind.timedOut =>
      'Loading the catalog timed out. Check your connection and retry.',
    CatalogFailureKind.requestFailed => 'Unable to load the catalog. Check your connection and access, then retry.',
  };
  @override
  String toString() => message;
}

void _response(bool valid) {
  if (!valid) throw const CatalogFailure(CatalogFailureKind.invalidResponse);
}

/// Match PostgreSQL trim(text): ordinary ASCII space only, not tabs/NBSP.
String trimCatalogSpaces(String value) {
  var start = 0, end = value.length;
  while (start < end && value.codeUnitAt(start) == 32) {
    start++;
  }
  while (end > start && value.codeUnitAt(end - 1) == 32) {
    end--;
  }
  return value.substring(start, end);
}

bool isCatalogUuid(String value) =>
    value.length == 36 &&
    RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(value);

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  _response(value is Map<String, dynamic>);
  final row = value as Map<String, dynamic>;
  _response(row.length == keys.length && row.keys.every(keys.contains));
  return row;
}

String _text(Object? value, int maximum, {bool required = false}) {
  _response(value is String);
  final text = value as String;
  _response(
    text.runes.length <= maximum &&
        !text.contains('\u0000') &&
        (!required || trimCatalogSpaces(text).isNotEmpty),
  );
  return text;
}

String _id(Object? value) {
  _response(value is String && isCatalogUuid(value));
  return value as String;
}

int _integer(Object? value, {int minimum = 0}) {
  _response(value is int && value >= minimum && value <= catalogMaxInteger);
  return value as int;
}

final class CatalogCursor {
  const CatalogCursor({required this.position, required this.id});
  final int position;
  final String id;
  bool get isValid =>
      position >= 0 && position <= catalogMaxInteger && isCatalogUuid(id);
  factory CatalogCursor.fromJson(Object? value) {
    final row = _object(value, {'position', 'id'});
    return CatalogCursor(
      position: _integer(row['position']),
      id: _id(row['id']),
    );
  }

  /// UUID hex ordering is byte ordering when canonical separators are fixed.
  int compareTo(CatalogCursor other) {
    final positions = position.compareTo(other.position);
    return positions != 0
        ? positions
        : id.toLowerCase().compareTo(other.id.toLowerCase());
  }
}

sealed class CatalogEntry {
  const CatalogEntry();
  String get id;
  int get position;
  CatalogCursor get cursor => CatalogCursor(position: position, id: id);
  void validate();
}

/// Published discovery projection only. No admin or protected-content fields.
final class CatalogCourse extends CatalogEntry {
  const CatalogCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.instructor,
    required this.category,
    required this.level,
    required this.pricePiasters,
    required this.position,
    required this.coverPath,
  });
  @override
  final String id;
  final String title, description, instructor, category, level;
  final int pricePiasters;
  @override
  final int position;
  final String? coverPath;

  @override
  void validate() {
    _id(id);
    _text(title, 160, required: true);
    _text(description, 10000);
    _text(instructor, 160, required: true);
    _text(category, 120, required: true);
    _text(level, 120, required: true);
    _integer(pricePiasters);
    _integer(position);
    if (coverPath != null) {
      final parts = coverPath!.split('/');
      _response(
        parts.length == 2 &&
            isCatalogUuid(parts.first) &&
            parts.first.toLowerCase() == id.toLowerCase() &&
            parts.last.endsWith('.png') &&
            parts.last.length == 40 &&
            isCatalogUuid(parts.last.substring(0, 36)),
      );
    }
  }

  factory CatalogCourse.fromJson(Object? value) {
    final row = _object(value, {
      'id',
      'title',
      'description',
      'instructor',
      'category',
      'level',
      'price_piasters',
      'position',
      'cover_path',
    });
    _response(row['cover_path'] == null || row['cover_path'] is String);
    final result = CatalogCourse(
      id: _id(row['id']),
      title: _text(row['title'], 160, required: true),
      description: _text(row['description'], 10000),
      instructor: _text(row['instructor'], 160, required: true),
      category: _text(row['category'], 120, required: true),
      level: _text(row['level'], 120, required: true),
      pricePiasters: _integer(row['price_piasters']),
      position: _integer(row['position']),
      coverPath: row['cover_path'] as String?,
    );
    result.validate();
    return result;
  }
}

final class CatalogSession extends CatalogEntry {
  const CatalogSession({
    required this.id,
    required this.courseId,
    required this.sessionNumber,
    required this.title,
    required this.description,
    required this.pricePiasters,
    required this.position,
    required this.isFreePreview,
  });
  @override
  final String id;
  final String courseId, title, description;
  final int sessionNumber, pricePiasters;
  @override
  final int position;
  final bool isFreePreview;
  @override
  void validate() {
    _id(id);
    _id(courseId);
    _integer(sessionNumber, minimum: 1);
    _text(title, 160, required: true);
    _text(description, 10000);
    _integer(pricePiasters);
    _integer(position);
  }

  factory CatalogSession.fromJson(Object? value) {
    final row = _object(value, {
      'id',
      'course_id',
      'session_number',
      'title',
      'description',
      'price_piasters',
      'position',
      'is_free_preview',
    });
    _response(row['is_free_preview'] is bool);
    return CatalogSession(
      id: _id(row['id']),
      courseId: _id(row['course_id']),
      sessionNumber: _integer(row['session_number'], minimum: 1),
      title: _text(row['title'], 160, required: true),
      description: _text(row['description'], 10000),
      pricePiasters: _integer(row['price_piasters']),
      position: _integer(row['position']),
      isFreePreview: row['is_free_preview'] as bool,
    );
  }
}

/// Keyset pages are not snapshots across concurrent position edits. Callers
/// appending multiple pages must also reject IDs already present in their list.
final class CatalogPage<T extends CatalogEntry> {
  CatalogPage({
    required List<T> items,
    required this.hasMore,
    required this.nextCursor,
    int limit = catalogDefaultLimit,
    CatalogCursor? after,
  }) : items = List.unmodifiable(items) {
    _response(
      limit >= 1 &&
          limit <= catalogMaxLimit &&
          this.items.length <= limit &&
          (after == null || after.isValid),
    );
    final ids = <String>{};
    var previous = after;
    for (final item in this.items) {
      item.validate();
      _response(
        ids.add(item.id.toLowerCase()) &&
            (after == null ||
                item.id.toLowerCase() != after.id.toLowerCase()) &&
            (previous == null || item.cursor.compareTo(previous) > 0),
      );
      previous = item.cursor;
    }
    if (hasMore) {
      _response(
        this.items.isNotEmpty &&
            this.items.length == limit &&
            nextCursor != null &&
            nextCursor!.isValid &&
            nextCursor!.compareTo(this.items.last.cursor) == 0,
      );
    } else {
      _response(nextCursor == null);
    }
  }
  final List<T> items;
  final bool hasMore;
  final CatalogCursor? nextCursor;
  factory CatalogPage.fromJson(
    Object? value,
    T Function(Object?) decode, {
    int limit = catalogDefaultLimit,
    CatalogCursor? after,
  }) {
    final row = _object(value, {'items', 'has_more', 'next_cursor'});
    _response(row['items'] is List && row['has_more'] is bool);
    final items = row['items'] as List;
    _response(items.length <= limit);
    return CatalogPage(
      items: items.map(decode).toList(growable: false),
      hasMore: row['has_more'] as bool,
      nextCursor: row['next_cursor'] == null
          ? null
          : CatalogCursor.fromJson(row['next_cursor']),
      limit: limit,
      after: after,
    );
  }
}

// PostgreSQL COLLATE "C" compares UTF-8 bytes. Unicode scalar lexical ordering
// agrees with that ordering, including supplementary characters (unlike UTF-16).
int _compareFilterText(String a, String b) {
  final left = a.runes.iterator, right = b.runes.iterator;
  while (true) {
    final hasLeft = left.moveNext(), hasRight = right.moveNext();
    if (!hasLeft || !hasRight) {
      return hasLeft
          ? 1
          : hasRight
          ? -1
          : 0;
    }
    final difference = left.current.compareTo(right.current);
    if (difference != 0) return difference;
  }
}

final class CatalogFilters {
  CatalogFilters({
    required List<String> categories,
    required List<String> levels,
  }) : categories = List.unmodifiable(categories),
       levels = List.unmodifiable(levels) {
    for (final values in [this.categories, this.levels]) {
      String? previous;
      for (final value in values) {
        _text(value, 120, required: true);
        _response(previous == null || _compareFilterText(previous, value) < 0);
        previous = value;
      }
    }
  }
  final List<String> categories, levels;
  factory CatalogFilters.fromJson(Object? value) {
    final row = _object(value, {'categories', 'levels'});
    _response(row['categories'] is List && row['levels'] is List);
    List<String> parse(Object? list) => (list as List)
        .map((value) => _text(value, 120, required: true))
        .toList(growable: false);
    return CatalogFilters(
      categories: parse(row['categories']),
      levels: parse(row['levels']),
    );
  }
}
