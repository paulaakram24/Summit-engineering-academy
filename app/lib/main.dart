import 'package:flutter/material.dart';

import 'appearance/theme_preferences.dart';
import 'auth/auth_bootstrap.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_panel.dart';
import 'content/content_repository.dart';
import 'content/supabase_content_repository.dart';
import 'content/material_repository.dart';
import 'content/supabase_material_repository.dart';
import 'catalog/catalog_repository.dart';
import 'catalog/supabase_catalog_repository.dart';
import 'catalog/catalog_screen.dart';
import 'bookmarks/bookmark_repository.dart';
import 'bookmarks/supabase_bookmark_repository.dart';
import 'content/course_covers.dart';
import 'content/material_file_upload_repository.dart';
import 'content/supabase_material_file_upload_repository.dart';
import 'commerce/instructor_payment_repository.dart';
import 'commerce/supabase_instructor_payment_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AuthBuildConfig();
  if (config.absent) {
    runApp(const SummitApp(themePreferenceStore: SecureThemePreferenceStore()));
    return;
  }
  try {
    final runtime = await initializeAuth(config)
        .timeout(const Duration(seconds: 30));
    final coverService = CourseCoverService(runtime.repository.client);
    runApp(
      SummitApp(
        themePreferenceStore: const SecureThemePreferenceStore(),
        authController: runtime.controller,
        instructorPaymentRepository: SupabaseInstructorPaymentRepository(
          runtime.repository.client,
        ),
        contentRepository: SupabaseContentRepository(runtime.repository.client),
        materialRepository: SupabaseMaterialRepository(
          runtime.repository.client,
        ),
        materialFileUploadRepository: SupabaseMaterialFileUploadRepository(
          runtime.repository.client,
        ),
        catalogRepository: SupabaseCatalogRepository(runtime.repository.client),
        bookmarkRepository: SupabaseBookmarkRepository(
          runtime.repository.client,
        ),
        catalogCoverLoader: (course) => coverService.downloadCover(
          Course(
            id: course.id,
            title: course.title,
            description: course.description,
            instructor: course.instructor,
            category: course.category,
            level: course.level,
            pricePiasters: course.pricePiasters,
            position: course.position,
            status: ContentStatus.published,
            coverPath: course.coverPath,
          ),
        ),
      ),
    );
  } catch (_) {
    runApp(
      const SummitApp(
        initializationFailed: true,
        themePreferenceStore: SecureThemePreferenceStore(),
      ),
    );
  }
}

class SummitApp extends StatefulWidget {
  const SummitApp({
    super.key,
    this.authController,
    this.contentRepository,
    this.materialRepository,
    this.catalogRepository,
    this.catalogCoverLoader,
    this.bookmarkRepository,
    this.instructorPaymentRepository,
    this.materialFileUploadRepository,
    this.initializationFailed = false,
    this.themePreferenceStore,
  });
  final AuthController? authController;
  final ContentRepository? contentRepository;
  final MaterialRepository? materialRepository;
  final CatalogRepository? catalogRepository;
  final CatalogCoverLoader? catalogCoverLoader;
  // Optional until the bookmark backend has been verified and activated.
  final BookmarkRepository? bookmarkRepository;
  final InstructorPaymentRepository? instructorPaymentRepository;
  // Optional for embedded/test instances; configured main uses the verified backend.
  final MaterialFileUploadRepository? materialFileUploadRepository;
  final bool initializationFailed;
  // Null keeps embedded/test instances in-memory; main supplies device storage.
  final ThemePreferenceStore? themePreferenceStore;
  @override
  State<SummitApp> createState() => _SummitAppState();
}

class _SummitAppState extends State<SummitApp> {
  late ThemePreferenceController _appearance;

  @override
  void initState() {
    super.initState();
    _attachAppearance();
  }

  void _attachAppearance() {
    _appearance = ThemePreferenceController(store: widget.themePreferenceStore)
      ..addListener(_appearanceChanged);
  }

  void _appearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SummitApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.themePreferenceStore,
      widget.themePreferenceStore,
    )) {
      _appearance.removeListener(_appearanceChanged);
      _appearance.dispose();
      _attachAppearance();
    }
  }

  @override
  void dispose() {
    _appearance.removeListener(_appearanceChanged);
    _appearance.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff218593),
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Summit Engineering Academy',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: _appearance.mode,
    home: Builder(
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('SEA Academy'),
            actions: [
              PopupMenuButton<ThemeMode>(
                tooltip: 'Appearance',
                initialValue: _appearance.mode,
                onSelected: _appearance.select,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: ThemeMode.system, child: Text('System')),
                  PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
                  PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                icon: const Icon(Icons.brightness_6),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AspectRatio(
                        aspectRatio: 1.5,
                        child: Image.asset(
                          'assets/sea-logo.png',
                          semanticLabel: 'SEA Academy logo',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Reach your next summit.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your engineering courses, sessions and assignments — together in one place.',
                    ),
                    const SizedBox(height: 24),
                    if (widget.authController != null)
                      AuthPanel(
                        controller: widget.authController!,
                        contentRepository: widget.contentRepository,
                        materialRepository: widget.materialRepository,
                        materialFileUploadRepository:
                            widget.materialFileUploadRepository,
                        catalogRepository: widget.catalogRepository,
                        catalogCoverLoader: widget.catalogCoverLoader,
                        bookmarkRepository: widget.bookmarkRepository,
                        instructorPaymentRepository:
                            widget.instructorPaymentRepository,
                      )
                    else
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            widget.initializationFailed
                                ? 'Account access could not start securely. Check app configuration and restart.'
                                : 'We are preparing your learning space. Account access is coming next.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
