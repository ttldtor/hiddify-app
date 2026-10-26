import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app_based_routing/data/windows_process_source.dart';

class _Processes implements WindowsProcessApi {
  const _Processes(this.paths);

  final Map<int, String?> paths;

  @override
  List<int> processIds() => paths.keys.toList();

  @override
  String? executablePath(int processId) => paths[processId];
}

void main() {
  test('skips inaccessible or vanished processes and stores full executable paths', () {
    const source = WindowsProcessSource(
      _Processes({
        11: r'C:\Apps\Browser.exe',
        12: null,
        13: r'C:\apps\browser.EXE',
        14: r'C:\Other\helper.exe',
        15: 'relative.exe',
        16: r'C:\Apps\library.dll',
      }),
    );
    expect(source.load(), [r'C:\Apps\Browser.exe', r'C:\Other\helper.exe']);
  });

  test('empty process snapshots stay empty', () {
    expect(const WindowsProcessSource(_Processes({})).load(), isEmpty);
  });
}
