import 'package:flutter/material.dart';

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
import 'content/course_covers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AuthBuildConfig();
  if (config.absent) {
    runApp(const SummitApp());
    return;
  }
  try {
    final runtime = await initializeAuth(config)
        .timeout(const Duration(seconds: 30));
    final coverService = CourseCoverService(runtime.repository.client);
    runApp(
      SummitApp(
        authController: runtime.controller,
        contentRepository: SupabaseContentRepository(runtime.repository.client),
        materialRepository: SupabaseMaterialRepository(
          runtime.repository.client,
        ),
        catalogRepository: SupabaseCatalogRepository(runtime.repository.client),
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
    runApp(const SummitApp(initializationFailed: true));
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
    this.initializationFailed = false,
  });
  final AuthController? authController;
  final ContentRepository? contentRepository;
  final MaterialRepository? materialRepository;
  final CatalogRepository? catalogRepository;
  final CatalogCoverLoader? catalogCoverLoader;
  final bool initializationFailed;
  @override
  State<SummitApp> createState() => _SummitAppState();
}

class _SummitAppState extends State<SummitApp> {
  ThemeMode mode = ThemeMode.system;
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
    themeMode: mode,
    home: Builder(
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('SEA Academy'),
            actions: [
              PopupMenuButton<ThemeMode>(
                tooltip: 'Appearance',
                initialValue: mode,
                onSelected: (value) => setState(() => mode = value),
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
                        catalogRepository: widget.catalogRepository,
                        catalogCoverLoader: widget.catalogCoverLoader,
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
