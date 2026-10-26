import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';

/// Read-only seam for testing races and inaccessible processes without native calls.
abstract interface class WindowsProcessApi {
  List<int> processIds();
  String? executablePath(int processId);
}

class WindowsProcessSource {
  const WindowsProcessSource(this.api);

  final WindowsProcessApi api;

  List<String> load() {
    final paths = <String>[];
    for (final id in api.processIds()) {
      try {
        final path = api.executablePath(id);
        if (path != null) paths.addAll(WindowsAppRouting.parseEntries(path, paths: true));
      } on FormatException {
        continue;
      }
    }
    final unique = WindowsAppRouting.parseEntries(paths.join('\n'), paths: true).toList();
    unique.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return unique;
  }
}
