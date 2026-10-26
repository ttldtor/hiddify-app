import 'package:file_picker/file_picker.dart';
import 'package:hiddify/features/app_based_routing/data/windows_process_api_native.dart'
    if (dart.library.js_interop) 'package:hiddify/features/app_based_routing/data/windows_process_api_stub.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'windows_process_api.dart';

typedef WindowsProcessLoader = Future<List<String>> Function();
typedef WindowsExecutableChooser = Future<String?> Function();

// Lazy callbacks: constructing a settings page never enumerates host processes.
final windowsProcessLoaderProvider = Provider<WindowsProcessLoader>((ref) => loadWindowsProcessPaths);

final windowsExecutableChooserProvider = Provider<WindowsExecutableChooser>(
  (ref) => () async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['exe']);
    return result?.files.single.path;
  },
);
