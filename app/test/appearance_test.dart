import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/appearance/theme_preferences.dart';
import 'package:summit_academy/main.dart';

class AppearanceStoreFake implements ThemePreferenceStore {
  String? value;
  Future<String?> Function()? onRead;
  Future<void> Function(String)? onWrite;
  int reads = 0;
  final writes = <String>[];

  @override
  Future<String?> read() async {
    reads++;
    return onRead == null ? value : await onRead!();
  }

  @override
  Future<void> write(String next) async {
    writes.add(next);
    if (onWrite != null) await onWrite!(next);
    value = next;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Appearance'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

ThemeMode selectedMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ThemeMode.values) {
    test('restores exact ${mode.name} preference', () async {
      final store = AppearanceStoreFake()..value = mode.name;
      final controller = ThemePreferenceController(store: store);
      addTearDown(controller.dispose);
      await flush();
      expect(controller.mode, mode);
      expect(store.reads, 1);
      expect(store.writes, isEmpty);
    });
  }

  for (final value in <String?>[null, '', 'DARK', ' dark ', 'invalid']) {
    test(
      'missing/invalid preference ${value ?? '(null)'} uses System',
      () async {
        final store = AppearanceStoreFake()..value = value;
        final controller = ThemePreferenceController(store: store);
        addTearDown(controller.dispose);
        await flush();
        expect(controller.mode, ThemeMode.system);
        expect(store.writes, isEmpty);
      },
    );
  }

  test('read failure falls back to System without leaking error', () async {
    final store = AppearanceStoreFake()
      ..onRead = () async => throw StateError('private storage diagnostic');
    final controller = ThemePreferenceController(store: store);
    addTearDown(controller.dispose);
    await flush();
    expect(controller.mode, ThemeMode.system);
    controller.select(ThemeMode.dark);
    await flush();
    expect(controller.mode, ThemeMode.dark);
    expect(store.value, 'dark');
  });

  for (final mode in [ThemeMode.dark, ThemeMode.system]) {
    test('late startup read cannot overwrite explicit ${mode.name}', () async {
      final read = Completer<String?>();
      final store = AppearanceStoreFake()..onRead = () => read.future;
      final controller = ThemePreferenceController(store: store);
      addTearDown(controller.dispose);
      controller.select(mode);
      read.complete('light');
      await flush();
      expect(controller.mode, mode);
      expect(store.writes, [mode.name]);
    });
  }

  test('writes serialize and coalesce waiting choices to latest', () async {
    final firstWrite = Completer<void>();
    final store = AppearanceStoreFake()
      ..onWrite = (value) =>
          value == 'dark' ? firstWrite.future : Future.value();
    final controller = ThemePreferenceController(store: store);
    addTearDown(controller.dispose);
    controller.select(ThemeMode.dark);
    controller.select(ThemeMode.light);
    controller.select(ThemeMode.system);
    await flush();
    expect(controller.mode, ThemeMode.system);
    expect(store.writes, ['dark']);
    firstWrite.complete();
    await flush();
    expect(store.writes, ['dark', 'system']);
    expect(store.value, 'system');
  });

  test(
    'failed write keeps memory choice and does not retry automatically',
    () async {
      final store = AppearanceStoreFake()
        ..onWrite = (_) async => throw StateError('private write diagnostic');
      final controller = ThemePreferenceController(store: store);
      addTearDown(controller.dispose);
      controller.select(ThemeMode.dark);
      await flush();
      await flush();
      expect(controller.mode, ThemeMode.dark);
      expect(store.writes, ['dark']);
      store.onWrite = null;
      controller.select(ThemeMode.light);
      await flush();
      expect(store.value, 'light');
    },
  );

  test(
    'queued latest choice persists even when preceding write fails',
    () async {
      final first = Completer<void>();
      final store = AppearanceStoreFake()
        ..onWrite = (value) => value == 'dark' ? first.future : Future.value();
      final controller = ThemePreferenceController(store: store);
      addTearDown(controller.dispose);
      controller.select(ThemeMode.dark);
      controller.select(ThemeMode.light);
      first.completeError(StateError('private write diagnostic'));
      await flush();
      expect(store.writes, ['dark', 'light']);
      expect(store.value, 'light');
    },
  );

  test('disposal ignores late read and new selections', () async {
    final read = Completer<String?>();
    final store = AppearanceStoreFake()..onRead = () => read.future;
    final controller = ThemePreferenceController(store: store);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();
    read.complete('dark');
    controller.select(ThemeMode.light);
    await flush();
    expect(controller.mode, ThemeMode.system);
    expect(notifications, 0);
    expect(store.writes, isEmpty);
  });

  test('accepted writes drain after disposal without notifications', () async {
    final first = Completer<void>();
    final store = AppearanceStoreFake()
      ..onWrite = (value) => value == 'dark' ? first.future : Future.value();
    final controller = ThemePreferenceController(store: store);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.select(ThemeMode.dark);
    controller.select(ThemeMode.light);
    expect(notifications, 2);
    controller.dispose();
    first.complete();
    await flush();
    expect(store.writes, ['dark', 'light']);
    expect(store.value, 'light');
    expect(notifications, 2);
  });

  test('in-memory controller needs no storage', () async {
    final controller = ThemePreferenceController();
    addTearDown(controller.dispose);
    controller.select(ThemeMode.light);
    await flush();
    expect(controller.mode, ThemeMode.light);
  });

  test(
    'Android adapter isolates container and disables destructive recovery',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'read' ? 'dark' : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const store = SecureThemePreferenceStore();
      expect(await store.read(), 'dark');
      await store.write('light');
      expect(calls.map((call) => call.method), ['read', 'write']);
      for (final call in calls) {
        final args = call.arguments as Map;
        expect(args['key'], 'sea.appearance.theme_mode.v1');
        expect(
          args['options'],
          const AndroidOptions(
            storageNamespace: 'sea_appearance_v1',
            resetOnError: false,
            migrateOnAlgorithmChange: false,
            migrateWithBackup: false,
          ).toMap(),
        );
        expect(
          args.keys,
          unorderedEquals(
            call.method == 'read'
                ? ['key', 'options']
                : ['key', 'value', 'options'],
          ),
        );
      }
      expect((calls.last.arguments as Map)['value'], 'light');
    },
  );

  for (final failingOperation in ['read', 'write']) {
    test(
      'appearance $failingOperation failure preserves mocked default-container auth sentinels',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        final containers = <String, Map<String, String>>{};
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments as Map;
          final options = args['options'] as Map;
          final namespace = options['storageNamespace'] as String;
          final entries = containers.putIfAbsent(namespace, () => {});
          if (namespace == 'sea_appearance_v1' &&
              call.method == failingOperation) {
            expect(options['resetOnError'], 'false');
            expect(options['migrateOnAlgorithmChange'], 'false');
            expect(options['migrateWithBackup'], 'false');
            throw PlatformException(code: 'test_storage_failure');
          }
          switch (call.method) {
            case 'read':
              return entries[args['key']];
            case 'write':
              entries[args['key'] as String] = args['value'] as String;
              return null;
            default:
              fail('Preference path must never delete or reset storage');
          }
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        // Channel simulation only: this does not execute Android KeyStore recovery.
        // Default options match the existing auth adapter, which is not changed.
        const defaultStorage = FlutterSecureStorage();
        final sentinels = {
          'test.auth.session': 'session sentinel',
          'test.auth.pkce': 'pkce sentinel',
          'test.auth.installation': 'installation sentinel',
        };
        for (final entry in sentinels.entries) {
          await defaultStorage.write(key: entry.key, value: entry.value);
        }
        final controller = ThemePreferenceController(
          store: const SecureThemePreferenceStore(),
        );
        addTearDown(controller.dispose);
        await flush();
        controller.select(ThemeMode.dark);
        await flush();
        expect(controller.mode, ThemeMode.dark);
        expect(containers[''], sentinels);
        for (final entry in sentinels.entries) {
          expect(await defaultStorage.read(key: entry.key), entry.value);
        }
        expect(
          calls.every(
            (call) => call.method == 'read' || call.method == 'write',
          ),
          isTrue,
        );
        for (final call in calls) {
          final args = call.arguments as Map;
          final options = args['options'] as Map;
          if (options['storageNamespace'] == '') {
            expect(options, const AndroidOptions().toMap());
            expect(sentinels.containsKey(args['key']), isTrue);
          } else {
            expect(options['storageNamespace'], 'sea_appearance_v1');
            expect(args['key'], 'sea.appearance.theme_mode.v1');
          }
        }
      },
    );
  }

  testWidgets('pending read never blocks first frame or selector', (
    tester,
  ) async {
    final read = Completer<String?>();
    final store = AppearanceStoreFake()..onRead = () => read.future;
    await tester.pumpWidget(SummitApp(themePreferenceStore: store));
    expect(find.text('SEA Academy'), findsOneWidget);
    expect(selectedMode(tester), ThemeMode.system);
    await choose(tester, 'Dark');
    read.complete('light');
    await tester.pumpAndSettle();
    expect(selectedMode(tester), ThemeMode.dark);
    expect(store.value, 'dark');
  });

  testWidgets('fresh app restores previous selection including System', (
    tester,
  ) async {
    final store = AppearanceStoreFake();
    for (final label in ['Dark', 'Light', 'System']) {
      await tester.pumpWidget(SummitApp(themePreferenceStore: store));
      await tester.pumpAndSettle();
      await choose(tester, label);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(SummitApp(themePreferenceStore: store));
      await tester.pumpAndSettle();
      expect(selectedMode(tester).name, label.toLowerCase());
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('System follows platform brightness; explicit mode does not', (
    tester,
  ) async {
    final store = AppearanceStoreFake()..value = 'system';
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(SummitApp(themePreferenceStore: store));
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    expect(brightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await choose(tester, 'Light');
    expect(brightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await choose(tester, 'System');
    expect(brightness(), Brightness.dark);
  });

  testWidgets('write failure does not break selector or show saved claim', (
    tester,
  ) async {
    final store = AppearanceStoreFake()
      ..onWrite = (_) async => throw StateError('private diagnostic');
    await tester.pumpWidget(SummitApp(themePreferenceStore: store));
    await choose(tester, 'Dark');
    expect(selectedMode(tester), ThemeMode.dark);
    await choose(tester, 'Light');
    expect(selectedMode(tester), ThemeMode.light);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(find.textContaining('saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late read after unmount cannot update disposed widget', (
    tester,
  ) async {
    final read = Completer<String?>();
    final store = AppearanceStoreFake()..onRead = () => read.future;
    await tester.pumpWidget(SummitApp(themePreferenceStore: store));
    await tester.pumpWidget(const SizedBox());
    read.complete('dark');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing injected store ignores old late read', (tester) async {
    final read = Completer<String?>();
    final oldStore = AppearanceStoreFake()..onRead = () => read.future;
    final newStore = AppearanceStoreFake()..value = 'light';
    await tester.pumpWidget(SummitApp(themePreferenceStore: oldStore));
    await tester.pumpWidget(SummitApp(themePreferenceStore: newStore));
    await tester.pumpAndSettle();
    read.complete('dark');
    await tester.pumpAndSettle();
    expect(selectedMode(tester), ThemeMode.light);
    expect(tester.takeException(), isNull);
  });
}
