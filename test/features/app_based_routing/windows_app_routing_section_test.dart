import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_based_routing/data/windows_app_routing_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/windows_process_source.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';
import 'package:hiddify/features/app_based_routing/overview/windows_app_routing_section.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This fake has no platform channel, disk store, app bootstrap, or native core.
class _MemoryPreferences extends Fake implements SharedPreferences {
  final values = <String, Object>{};
  bool allowWrites = true;

  @override
  Object? get(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (!allowWrites) return false;
    values[key] = value;
    return true;
  }
}

void main() {
  final t = TranslationsEn().pages.settings.routing.windowsAppRouting;
  late Translations russian;

  setUpAll(() async {
    russian = await AppLocale.ru.build().timeout(const Duration(seconds: 30));
  });

  Future<(ProviderContainer, _MemoryPreferences)> open(
    WidgetTester tester, {
    WindowsAppRouting policy = const WindowsAppRouting(),
    String serviceMode = 'vpn',
    WindowsProcessLoader? processes,
    WindowsExecutableChooser? chooser,
    Translations? translations,
    TextDirection direction = TextDirection.ltr,
    VoidCallback? onAddRoute,
    ScrollController? scrollController,
  }) async {
    final preferences = _MemoryPreferences();
    preferences.values.addAll({'windows_app_routing': policy.encode(), 'service-mode': serviceMode});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        translationsProvider.overrideWith((ref) => translations ?? AppLocale.en.build()),
        windowsProcessLoaderProvider.overrideWithValue(
          processes ?? () async => throw StateError('Unexpected enumeration'),
        ),
        windowsExecutableChooserProvider.overrideWithValue(
          chooser ?? () async => throw StateError('Unexpected file dialog'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              appBar: onAddRoute == null ? null : AppBar(title: const Text('Routing')),
              body: onAddRoute == null
                  ? const SingleChildScrollView(child: WindowsAppRoutingSection())
                  // Match the routing page's header/FAB layout without its rule repository.
                  : ReorderableListView(
                      scrollController: scrollController,
                      padding: const EdgeInsets.only(bottom: 56 + 16 + 16),
                      buildDefaultDragHandles: false,
                      header: const WindowsAppRoutingSection(),
                      onReorder: (_, _) {},
                      children: [
                        for (var index = 0; index < 3; index++)
                          ListTile(key: ValueKey(index), title: Text('Route $index')),
                      ],
                    ),
              floatingActionButton: onAddRoute == null
                  ? null
                  : FloatingActionButton(onPressed: onAddRoute, child: const Icon(Icons.add_rounded)),
            ),
          ),
        ),
      ),
    );
    return (container, preferences);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  for (final scenario in [
    (width: 850.0, direction: TextDirection.ltr),
    (width: 1024.0, direction: TextDirection.ltr),
    (width: 420.0, direction: TextDirection.ltr),
    (width: 420.0, direction: TextDirection.rtl),
  ]) {
    testWidgets('Save stays clear of route FAB at ${scenario.width}x660 ${scenario.direction.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(scenario.width, 660);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var addRouteCalls = 0;
      var processCalls = 0;
      var chooserCalls = 0;
      const paths = [r'C:\Apps\first.exe', r'C:\Apps\second.exe'];
      final (container, preferences) = await open(
        tester,
        policy: const WindowsAppRouting(enabled: true, processPaths: paths),
        translations: russian,
        direction: scenario.direction,
        onAddRoute: () => addRouteCalls++,
        scrollController: scroll,
        processes: () async {
          processCalls++;
          return [];
        },
        chooser: () async {
          chooserCalls++;
          return null;
        },
      );
      await tester.enterText(find.byKey(const Key('windows-routing-names')), 'Browser.exe');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final saveButton = find.widgetWithText(FilledButton, russian.common.save);
      final fab = find.byType(FloatingActionButton);
      final targetOffset = (scroll.offset + tester.getRect(saveButton).center.dy - tester.getRect(fab).center.dy).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      );
      scroll.jumpTo(targetOffset);
      await tester.pumpAndSettle();
      final saveRect = tester.getRect(saveButton);
      final fabRect = tester.getRect(fab);
      expect(saveRect.top, lessThan(fabRect.bottom));
      expect(saveRect.bottom, greaterThan(fabRect.top));
      expect(saveRect.overlaps(fabRect), isFalse);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(container.read(windowsAppRoutingProvider).processNames, ['Browser.exe']);
      expect(container.read(windowsAppRoutingProvider).processPaths, paths);
      expect(WindowsAppRouting.decode(preferences.values['windows_app_routing']! as String).processNames, [
        'Browser.exe',
      ]);
      expect(addRouteCalls, 0);
      expect(processCalls, 0);
      expect(chooserCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('default is off and enabling remains a draft until save', (tester) async {
    final (container, _) = await open(tester);
    expect(find.byType(TextField), findsNothing);
    expect(container.read(windowsAppRoutingProvider).enabled, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text(t.unsaved), findsOneWidget);
    expect(container.read(windowsAppRoutingProvider).enabled, isFalse);
    await save(tester);
    expect(container.read(windowsAppRoutingProvider).enabled, isTrue);
    expect(find.text(t.saved), findsOneWidget);
  });

  testWidgets('path example renders literal Windows backslashes', (tester) async {
    await open(tester, policy: const WindowsAppRouting(enabled: true));
    expect(find.textContaining(r'C:\Apps\browser.exe'), findsOneWidget);
    expect(find.textContaining('\b'), findsNothing);
  });

  testWidgets('mode and exact selectors save together', (tester) async {
    final (container, _) = await open(tester, policy: const WindowsAppRouting(enabled: true));
    await tester.tap(find.widgetWithText(ChoiceChip, t.proxy));
    await tester.enterText(find.byKey(const Key('windows-routing-names')), 'Browser.exe\nbrowser.EXE');
    await tester.enterText(find.byKey(const Key('windows-routing-paths')), r'C:\Apps\helper.exe');
    await save(tester);
    final policy = container.read(windowsAppRoutingProvider);
    expect(policy.mode, AppProxyMode.include);
    expect(policy.processNames, ['Browser.exe']);
    expect(policy.processPaths, [r'C:\Apps\helper.exe']);
  });

  testWidgets('turning routing off retains selectors after saving', (tester) async {
    final (container, _) = await open(
      tester,
      policy: const WindowsAppRouting(enabled: true, processNames: ['Browser.exe']),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await save(tester);
    final policy = container.read(windowsAppRoutingProvider);
    expect(policy.enabled, isFalse);
    expect(policy.processNames, ['Browser.exe']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('outside TUN mode explains availability without discarding saved policy', (tester) async {
    final (container, _) = await open(
      tester,
      policy: const WindowsAppRouting(enabled: true, processNames: ['Browser.exe']),
      serviceMode: 'system-proxy',
    );
    expect(find.text(t.tunUnavailable), findsOneWidget);
    expect(container.read(windowsAppRoutingProvider).enabled, isTrue);
    expect(container.read(windowsAppRoutingProvider).processNames, ['Browser.exe']);
  });

  testWidgets('invalid entries preserve draft and do not write', (tester) async {
    final (container, _) = await open(tester, policy: const WindowsAppRouting(enabled: true));
    await tester.enterText(find.byKey(const Key('windows-routing-names')), '*.exe');
    await tester.enterText(find.byKey(const Key('windows-routing-paths')), 'relative.exe');
    await save(tester);
    expect(find.text(t.invalidNames), findsOneWidget);
    expect(find.text(t.invalidPaths), findsOneWidget);
    expect(container.read(windowsAppRoutingProvider).processNames, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('windows-routing-names'))).controller!.text, '*.exe');
  });

  testWidgets('failed persistence never acknowledges success and permits retry', (tester) async {
    final (container, preferences) = await open(tester, policy: const WindowsAppRouting(enabled: true));
    preferences.allowWrites = false;
    await tester.enterText(find.byKey(const Key('windows-routing-names')), 'Browser.exe');
    await save(tester);
    expect(find.text(t.saveFailed), findsOneWidget);
    expect(find.text(t.saved), findsNothing);
    expect(container.read(windowsAppRoutingProvider).processNames, isEmpty);
    preferences.allowWrites = true;
    await save(tester);
    expect(container.read(windowsAppRoutingProvider).processNames, ['Browser.exe']);
    expect(find.text(t.saved), findsOneWidget);
  });

  testWidgets('running app picker is lazy and adds the full executable path', (tester) async {
    var enumerations = 0;
    final (container, _) = await open(
      tester,
      policy: const WindowsAppRouting(enabled: true),
      processes: () async {
        enumerations++;
        return [r'C:\Program Files\Browser\browser.exe'];
      },
    );
    expect(enumerations, 0);
    await tester.ensureVisible(find.text(t.runningApps));
    await tester.tap(find.text(t.runningApps));
    // The picker remains busy until the dialog returns, so its progress indicator
    // intentionally keeps scheduling frames while the selection is pending.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.text(r'C:\Program Files\Browser\browser.exe'));
    await tester.pumpAndSettle();
    expect(enumerations, 1);
    expect(container.read(windowsAppRoutingProvider).processPaths, isEmpty);
    await save(tester);
    expect(container.read(windowsAppRoutingProvider).processPaths, [r'C:\Program Files\Browser\browser.exe']);
  });

  testWidgets('file selection cancel keeps selectors unchanged', (tester) async {
    final (container, _) = await open(
      tester,
      policy: const WindowsAppRouting(enabled: true),
      chooser: () async => null,
    );
    await tester.ensureVisible(find.text(t.chooseFile));
    await tester.tap(find.text(t.chooseFile));
    await tester.pumpAndSettle();
    expect(container.read(windowsAppRoutingProvider).processPaths, isEmpty);
    expect(find.text(t.unsaved), findsNothing);
  });

  testWidgets('file chooser adds an exact full path without saving until requested', (tester) async {
    final (container, _) = await open(
      tester,
      policy: const WindowsAppRouting(enabled: true),
      chooser: () async => r'C:\Apps\chosen.exe',
    );
    await tester.ensureVisible(find.text(t.chooseFile));
    await tester.tap(find.text(t.chooseFile));
    await tester.pumpAndSettle();
    expect(container.read(windowsAppRoutingProvider).processPaths, isEmpty);
    await save(tester);
    expect(container.read(windowsAppRoutingProvider).processPaths, [r'C:\Apps\chosen.exe']);
  });

  testWidgets('process enumeration failure offers file selection and keeps settings', (tester) async {
    await open(
      tester,
      policy: const WindowsAppRouting(enabled: true),
      processes: () async => throw StateError('Unavailable snapshot'),
    );
    await tester.ensureVisible(find.text(t.runningApps));
    await tester.tap(find.text(t.runningApps));
    await tester.pumpAndSettle();
    expect(find.text(t.pickFailed), findsOneWidget);
    final chooseFile = find.ancestor(
      of: find.text(t.chooseFile),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(tester.widget<TextButton>(chooseFile).onPressed, isNotNull);
  });
}
