import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_based_routing/data/windows_app_routing_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pure model and in-memory preferences only. Never initialize the app or core.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default leaves existing VPN behavior unchanged', () {
    const policy = WindowsAppRouting();
    expect(policy.enabled, isFalse);
    expect(policy.mode, AppProxyMode.exclude);
    expect(policy.processNames, isEmpty);
    expect(policy.processPaths, isEmpty);
  });

  test('round trip preserves both selectors and mode', () {
    const policy = WindowsAppRouting(
      enabled: true,
      mode: AppProxyMode.include,
      processNames: ['Browser.exe'],
      processPaths: [r'C:\Program Files\Приложение\client.exe'],
    );
    expect(WindowsAppRouting.decode(policy.encode()).toJson(), policy.toJson());
  });

  test('entries are trimmed and deduplicated without changing path casing', () {
    expect(WindowsAppRouting.parseEntries(' Browser.exe\r\nbrowser.EXE\n\n', paths: false), ['Browser.exe']);
    expect(WindowsAppRouting.parseEntries('C:\\Apps\\Tool.exe\nC:\\apps\\tool.EXE', paths: true), [
      r'C:\Apps\Tool.exe',
    ]);
    expect(WindowsAppRouting.parseEntries(r'\\server\share\Tool.exe', paths: true), [r'\\server\share\Tool.exe']);
  });

  test('rejects relative paths, patterns, shell expansion and non-executables', () {
    for (final value in [
      'C:tool.exe',
      r'\tool.exe',
      r'%APPDATA%\tool.exe',
      r'C:\..\tool.exe',
      r'C:\*\tool.exe',
      'file.dll',
    ]) {
      expect(() => WindowsAppRouting.parseEntries(value, paths: true), throwsFormatException, reason: value);
    }
    for (final value in [r'C:\tool.exe', '*.exe', 'tool.exe:stream', 'file.dll']) {
      expect(() => WindowsAppRouting.parseEntries(value, paths: false), throwsFormatException, reason: value);
    }
  });

  test('rejects path components and control characters rejected by the core', () {
    for (final value in [
      r'C:\Apps\\client.exe',
      r'C:\Apps \client.exe',
      r'C:\ Apps\client.exe',
      r'\\server\share\\client.exe',
      'C:\\Apps\\client\u007f.exe',
      'C:\\Apps\\client\u0085.exe',
    ]) {
      expect(() => WindowsAppRouting.parseEntries(value, paths: true), throwsFormatException, reason: value);
    }
    expect(() => WindowsAppRouting.parseEntries('client\u007f.exe', paths: false), throwsFormatException);
  });

  test('settings survive provider recreation and unrelated subscription writes', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ProviderContainer open() =>
        ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences))]);
    final first = open();
    await first.read(sharedPreferencesProvider.future);
    final policy = first
        .read(windowsAppRoutingProvider)
        .copyWith(enabled: true, mode: AppProxyMode.include, processPaths: [r'C:\Apps\client.exe']);
    await first.read(windowsAppRoutingProvider.notifier).update(policy);
    first.dispose();

    await preferences.setString('profile_override', '{"route-rule":{"rules":[]}}');
    final second = open();
    addTearDown(second.dispose);
    await second.read(sharedPreferencesProvider.future);
    expect(second.read(windowsAppRoutingProvider).toJson(), policy.toJson());
    await second.read(windowsAppRoutingProvider.notifier).update(policy.copyWith(enabled: false));
    expect(second.read(windowsAppRoutingProvider).processPaths, policy.processPaths);
  });
}
