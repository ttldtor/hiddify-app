import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_based_routing/data/windows_app_routing_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryRules extends RulesNotifier {
  @override
  List<Rule> build() => [];
}

// No app bootstrap, directories, native core, subscriptions, or network access.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences)),
        rulesNotifierProvider.overrideWith(_InMemoryRules.new),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
  });
  tearDown(() => container.dispose());

  Map<String, dynamic> withProfile(Map<String, dynamic> override) {
    final repository = ConfigOptionRepository(
      preferences: preferences,
      getConfigOptions: () => container.read(ConfigOptions.singboxConfigOptions),
    );
    return repository
        .fullOptionsOverrided(jsonEncode(override))
        .match((failure) => throw StateError('$failure'), (options) => options.toJson());
  }

  test('disabled policy leaves the serialized options unchanged', () {
    expect(container.read(ConfigOptions.singboxConfigOptions).toJson(), isNot(contains('windows-app-routing')));
  });

  test('profile cannot introduce a local application policy', () {
    final result = withProfile({
      'windows-app-routing': {'enabled': true, 'mode': 'include'},
    });
    expect(result, isNot(contains('windows-app-routing')));
  });

  test('local policy reaches core and survives conflicting subscription overrides', () async {
    const policy = WindowsAppRouting(
      enabled: true,
      mode: AppProxyMode.include,
      processNames: ['Browser.exe'],
      processPaths: [r'C:\Program Files\Client\client.exe'],
    );
    await container.read(ConfigOptions.serviceMode.notifier).update(ServiceMode.tun);
    await container.read(windowsAppRoutingProvider.notifier).update(policy);
    expect(container.read(ConfigOptions.singboxConfigOptions).toJson()['windows-app-routing'], policy.toJson());
    final result = withProfile({
      'windows-app-routing': {
        'enabled': false,
        'mode': 'exclude',
        'process-paths': [r'C:\Other.exe'],
      },
      'enable-tun': false,
      'execute-config-as-is': true,
      'remote-dns-address': 'tcp://192.0.2.53',
    });
    expect(result['windows-app-routing'], policy.toJson());
    expect(result['enable-tun'], isTrue);
    expect(result['execute-config-as-is'], isFalse);
    expect(result['remote-dns-address'], 'tcp://192.0.2.53');
    expect(container.read(windowsAppRoutingProvider).toJson(), policy.toJson());
  }, skip: !Platform.isWindows);
}
