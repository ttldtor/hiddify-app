import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';

/// Kept outside ConfigOptions.preferences so profile updates cannot replace it.
final windowsAppRoutingProvider = PreferencesNotifier.create<WindowsAppRouting, String>(
  'windows_app_routing',
  const WindowsAppRouting(),
  mapFrom: WindowsAppRouting.decode,
  mapTo: (value) => value.encode(),
);
