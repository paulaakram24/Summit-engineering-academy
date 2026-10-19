const contentPageSize = 20;
const maxContentInteger = 2147483647;

enum ContentStatus { draft, published, archived }

/// Parses decimal EGP without floating point arithmetic or rounding.
int? parsePricePiasters(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final result =
      int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return result <= maxContentInteger ? result : null;
}

String formatPricePiasters(int value) =>
    '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

String? validateContentText(
  String? value,
  String label,
  int max, {
  bool required = true,
}) {
  final text = (value ?? '').trim();
  if (required && text.isEmpty) return '$label is required.';
  if (text.runes.length > max) {
    return '$label must be $max characters or fewer.';
  }
  return null;
}

String? validateContentInteger(String? value, {bool positive = false}) {
  final text = (value ?? '').trim();
  final number = RegExp(r'^\d{1,10}$').hasMatch(text)
      ? int.tryParse(text)
      : null;
  return number == null ||
          number < (positive ? 1 : 0) ||
          number > maxContentInteger
      ? 'Enter a whole number from ${positive ? 1 : 0} to $maxContentInteger.'
      : null;
}

class ContentFailure implements Exception {
  const ContentFailure([
    this.message = 'Unable to load or save content. Check your connection and access, then try again.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class CourseDraft {
  const CourseDraft({
    required this.title,
    this.description = '',
    required this.instructor,
    required this.category,
    required this.level,
    required this.pricePiasters,
    this.position = 0,
    this.status = ContentStatus.draft,
  });
  final String title, description, instructor, category, level;
  final int pricePiasters, position;
  final ContentStatus status;

  String? get validationMessage =>
      validateContentText(title, 'Title', 160) ??
      validateContentText(description, 'Description', 10000, required: false) ??
      validateContentText(instructor, 'Instructor', 160) ??
      validateContentText(category, 'Category', 120) ??
      validateContentText(level, 'Level', 120) ??
      _validateNumbers(pricePiasters, position);

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'description': description.trim(),
    'instructor': instructor.trim(),
    'category': category.trim(),
    'level': level.trim(),
    'price_piasters': pricePiasters,
    'position': position,
    'status': status.name,
  };
}

class SessionDraft {
  const SessionDraft({
    required this.sessionNumber,
    required this.title,
    this.description = '',
    required this.pricePiasters,
    this.position = 0,
    this.status = ContentStatus.draft,
    this.isFreePreview = false,
  });
  final int sessionNumber, pricePiasters, position;
  final String title, description;
  final ContentStatus status;
  final bool isFreePreview;

  String? get validationMessage =>
      validateContentText(title, 'Title', 160) ??
      validateContentText(description, 'Description', 10000, required: false) ??
      (sessionNumber < 1 || sessionNumber > maxContentInteger
          ? 'Enter a valid positive session number.'
          : null) ??
      _validateNumbers(pricePiasters, position);

  Map<String, dynamic> toJson() => {
    'session_number': sessionNumber,
    'title': title.trim(),
    'description': description.trim(),
    'price_piasters': pricePiasters,
    'position': position,
    'status': status.name,
    'is_free_preview': isFreePreview,
  };
}

String? _validateNumbers(int price, int position) =>
    price < 0 ||
        price > maxContentInteger ||
        position < 0 ||
        position > maxContentInteger
    ? 'Price and position must be within the supported range.'
    : null;

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
ContentStatus _status(dynamic value) =>
    ContentStatus.values.byName(value as String);

class Course {
  const Course({
    required this.id,
    required this.title,
    this.description = '',
    required this.instructor,
    required this.category,
    required this.level,
    required this.pricePiasters,
    this.position = 0,
    this.status = ContentStatus.draft,
    this.deletedAt,
    this.coverPath,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });
  final String id, title, description, instructor, category, level;
  final int pricePiasters, position;
  final ContentStatus status;
  final String? coverPath, createdBy;
  final DateTime? deletedAt, createdAt, updatedAt;
  bool get isDeleted => deletedAt != null;
  CourseDraft toDraft() => CourseDraft(
    title: title,
    description: description,
    instructor: instructor,
    category: category,
    level: level,
    pricePiasters: pricePiasters,
    position: position,
    status: status,
  );
  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    instructor: json['instructor'] as String,
    category: json['category'] as String,
    level: json['level'] as String,
    pricePiasters: json['price_piasters'] as int,
    position: json['position'] as int,
    status: _status(json['status']),
    deletedAt: _date(json['deleted_at']),
    coverPath: json['cover_path'] as String?,
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
    createdBy: json['created_by'] as String?,
  );
}

class CourseSession {
  const CourseSession({
    required this.id,
    required this.courseId,
    required this.sessionNumber,
    required this.title,
    this.description = '',
    required this.pricePiasters,
    this.position = 0,
    this.status = ContentStatus.draft,
    this.deletedAt,
    this.isFreePreview = false,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });
  final String id, courseId, title, description;
  final int sessionNumber, pricePiasters, position;
  final ContentStatus status;
  final bool isFreePreview;
  final DateTime? deletedAt, createdAt, updatedAt;
  final String? createdBy;
  bool get isDeleted => deletedAt != null;
  SessionDraft toDraft() => SessionDraft(
    sessionNumber: sessionNumber,
    title: title,
    description: description,
    pricePiasters: pricePiasters,
    position: position,
    status: status,
    isFreePreview: isFreePreview,
  );
  factory CourseSession.fromJson(Map<String, dynamic> json) => CourseSession(
    id: json['id'] as String,
    courseId: json['course_id'] as String,
    sessionNumber: json['session_number'] as int,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    pricePiasters: json['price_piasters'] as int,
    position: json['position'] as int,
    status: _status(json['status']),
    deletedAt: _date(json['deleted_at']),
    isFreePreview: json['is_free_preview'] as bool? ?? false,
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
    createdBy: json['created_by'] as String?,
  );
}
