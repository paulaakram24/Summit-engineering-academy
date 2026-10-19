import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_models.dart';
import 'course_covers.dart';

/// Injectable UI boundary; binary validation and storage lifecycle stay in the
/// existing service. Removing a reference uses the same deployed CAS contract.
abstract class CourseCoverActions {
  Future<Uint8List?> download(Course course);
  Future<Course> replace(Course course, Uint8List png);
  Future<Course> remove(Course course);
  Future<CoverCleanupResult> cleanup(String courseId);
}

class SupabaseCourseCoverActions implements CourseCoverActions {
  SupabaseCourseCoverActions(this.client)
    : service = CourseCoverService(client);
  final SupabaseClient client;
  final CourseCoverService service;

  @override
  Future<Uint8List?> download(Course course) => service.downloadCover(course);
  @override
  Future<Course> replace(Course course, Uint8List png) =>
      service.replaceCover(course, png);
  @override
  Future<CoverCleanupResult> cleanup(String courseId) =>
      service.cleanupRetired(courseId);

  @override
  Future<Course> remove(Course course) async {
    try {
      if (course.isDeleted || course.coverPath == null) {
        throw const CourseCoverFailure();
      }
      final row = await client
          .rpc(
            'attach_course_cover',
            params: {
              'p_course_id': course.id,
              'p_path': null,
              'p_expected_previous_path': course.coverPath,
            },
          )
          .timeout(const Duration(seconds: 20));
      final result = Course.fromJson(row as Map<String, dynamic>);
      if (result.id != course.id ||
          result.isDeleted ||
          result.coverPath != null) {
        throw const CourseCoverFailure();
      }
      return result;
    } catch (_) {
      throw const CourseCoverFailure();
    }
  }
}
