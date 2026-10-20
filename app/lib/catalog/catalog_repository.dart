import 'catalog_models.dart';
export 'catalog_models.dart';

abstract class CatalogRepository {
  String? get currentActorId;
  Future<CatalogPage<CatalogCourse>> listCourses({
    String? search = '',
    String? category,
    String? level,
    CatalogCursor? after,
    int limit = catalogDefaultLimit,
  });
  Future<CatalogCourse?> getCourse(String courseId);
  Future<CatalogPage<CatalogSession>> listSessions(
    String courseId, {
    CatalogCursor? after,
    int limit = catalogDefaultLimit,
  });
  Future<CatalogFilters> getFilters();
}
