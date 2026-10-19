import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_models.dart';

const maxCoverInputBytes = 5 * 1024 * 1024;
const maxCoverPngBytes = 3 * 1024 * 1024;
const _maxDimension = 4096;
const _maxPixels = 16000000;
const _bucket = 'course-covers';
const _timeout = Duration(seconds: 20);
const _uuid = r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}';

class CourseCoverFailure implements Exception {
  const CourseCoverFailure();
  String get message =>
      'Unable to process the course cover. Refresh before retrying. Some cleanup may remain pending.';
  @override
  String toString() => message;
}

/// A single bounded cleanup pass; callers can explicitly request another pass.
class CoverCleanupResult {
  const CoverCleanupResult({
    required this.attempted,
    required this.cleaned,
    required this.failed,
    required this.mayHaveMore,
  });
  final int attempted, cleaned, failed;
  final bool mayHaveMore;
}

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

bool _png(Uint8List bytes) =>
    _startsWith(bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
bool _supported(Uint8List bytes) =>
    _png(bytes) ||
    _startsWith(bytes, [255, 216, 255]) ||
    (bytes.length >= 12 &&
        _startsWith(bytes, [82, 73, 70, 70]) &&
        bytes[8] == 87 &&
        bytes[9] == 69 &&
        bytes[10] == 66 &&
        bytes[11] == 80);

/// Accepts one-frame PNG/JPEG/WebP, bounds dimensions before codec allocation,
/// and exports pixel data as PNG, dropping the source's metadata.
Future<Uint8List> sanitizeCoverImage(Uint8List raw) async {
  try {
    if (raw.isEmpty || raw.length > maxCoverInputBytes || !_supported(raw)) {
      throw const CourseCoverFailure();
    }
    return await _decode(Uint8List.fromList(raw), reencode: true);
  } catch (_) {
    throw const CourseCoverFailure();
  }
}

Future<Uint8List> _decode(Uint8List bytes, {required bool reencode}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 1 ||
        descriptor.height < 1 ||
        descriptor.width > _maxDimension ||
        descriptor.height > _maxDimension ||
        descriptor.width * descriptor.height > _maxPixels) {
      throw const CourseCoverFailure();
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) throw const CourseCoverFailure();
    image = (await codec.getNextFrame()).image;
    if (!reencode) return bytes;
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null || encoded.lengthInBytes > maxCoverPngBytes) {
      throw const CourseCoverFailure();
    }
    return Uint8List.fromList(
      encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes),
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Private JWT-authenticated storage only. Backend ledger/RLS must prevent
/// attaching retired objects and deleting referenced or uploading objects.
class CourseCoverService {
  CourseCoverService(this.client);
  final SupabaseClient client;

  void _id(String id) {
    if (!RegExp('^$_uuid\$').hasMatch(id)) throw const CourseCoverFailure();
  }

  String _path(String courseId, Object? value) {
    _id(courseId);
    if (value is! String ||
        !RegExp('^$_uuid/$_uuid\\.png\$').hasMatch(value) ||
        value.split('/').first.toLowerCase() != courseId.toLowerCase()) {
      throw const CourseCoverFailure();
    }
    return value;
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) =>
      client.rpc(name, params: params).timeout(_timeout);

  /// A failed or timed-out attach may already have committed. Abandon is an
  /// idempotent no-op for attached objects; only subsequent retirement listing
  /// permits removal. If the listing is uncertain or omits the path, leave it.
  /// A cleanup failure never masks the original failure, and may require a later
  /// explicit cleanupRetired call. Never removes the previous cover here.
  Future<Course> replaceCover(Course course, Uint8List sanitizedPng) async {
    String? preparedPath;
    try {
      _id(course.id);
      if (course.isDeleted) throw const CourseCoverFailure();
      if (course.coverPath != null) _path(course.id, course.coverPath);
      if (sanitizedPng.isEmpty ||
          sanitizedPng.length > maxCoverPngBytes ||
          !_png(sanitizedPng)) {
        throw const CourseCoverFailure();
      }
      final png = await _decode(
        Uint8List.fromList(sanitizedPng),
        reencode: false,
      );
      final prepared = await _rpc('prepare_course_cover', {
        'p_course_id': course.id,
      });
      if (prepared is! Map) throw const CourseCoverFailure();
      final path = _path(course.id, prepared['path']);
      // A reservation must never reuse the currently referenced cover path.
      if (path.toLowerCase() == course.coverPath?.toLowerCase()) {
        throw const CourseCoverFailure();
      }
      preparedPath = path;
      await client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            png,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
              cacheControl: '0',
            ),
            retryAttempts: 0,
          )
          .timeout(_timeout);
      final attached = await _rpc('attach_course_cover', {
        'p_course_id': course.id,
        'p_path': path,
        'p_expected_previous_path': course.coverPath,
      });
      if (attached is! Map<String, dynamic>) throw const CourseCoverFailure();
      final result = Course.fromJson(attached);
      if (result.id.toLowerCase() != course.id.toLowerCase() ||
          result.coverPath != path ||
          result.isDeleted) {
        throw const CourseCoverFailure();
      }
      return result;
    } catch (_) {
      if (preparedPath != null) await _abandon(course.id, preparedPath);
      throw const CourseCoverFailure();
    }
  }

  Future<void> _abandon(String courseId, String path) async {
    try {
      await _rpc('abandon_course_cover', {
        'p_course_id': courseId,
        'p_path': path,
      });
      final retired = await _rpc('list_retired_course_covers', {
        'p_course_id': courseId,
      });
      if (retired is! List) return;
      final paths = retired
          .take(20)
          .map((value) => _path(courseId, value))
          .toSet();
      if (paths.contains(path)) await _removeRetired(courseId, path);
    } catch (_) {
      // A lost response, refusal, or omitted path must never authorize removal.
    }
  }

  Future<void> _removeRetired(String courseId, String path) async {
    await client.storage.from(_bucket).remove([path]).timeout(_timeout);
    // Backend checks that the object is actually gone, including empty remove results.
    await _rpc('finish_course_cover_cleanup', {
      'p_course_id': courseId,
      'p_path': path,
    });
  }

  Future<CoverCleanupResult> cleanupRetired(String courseId) async {
    try {
      _id(courseId);
      final result = await _rpc('list_retired_course_covers', {
        'p_course_id': courseId,
      });
      if (result is! List) throw const CourseCoverFailure();
      // Validate the whole bounded batch before any removal.
      final paths = result
          .take(20)
          .map((value) => _path(courseId, value))
          .toSet();
      var cleaned = 0;
      for (final path in paths) {
        try {
          await _removeRetired(courseId, path);
          cleaned++;
        } catch (_) {
          // Continue this one batch; backend policies reject referenced paths.
        }
      }
      final failed = paths.length - cleaned;
      return CoverCleanupResult(
        attempted: paths.length,
        cleaned: cleaned,
        failed: failed,
        mayHaveMore: result.length >= 20 || failed > 0,
      );
    } catch (_) {
      throw const CourseCoverFailure();
    }
  }

  Future<Uint8List?> downloadCover(Course course) async {
    try {
      _id(course.id);
      if (course.coverPath == null) return null;
      final path = _path(course.id, course.coverPath);
      final bytes = await client.storage
          .from(_bucket)
          .download(path)
          .timeout(_timeout);
      if (bytes.isEmpty || bytes.length > maxCoverPngBytes || !_png(bytes)) {
        throw const CourseCoverFailure();
      }
      return await _decode(bytes, reencode: false);
    } catch (_) {
      throw const CourseCoverFailure();
    }
  }
}
