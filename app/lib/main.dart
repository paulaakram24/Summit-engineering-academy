import 'package:flutter/material.dart';

void main() => runApp(const SummitApp());

class SummitApp extends StatefulWidget {
  const SummitApp({super.key});
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
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'We are preparing your learning space. Account access is coming next.',
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
