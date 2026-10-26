import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:hiddify/features/app_based_routing/data/windows_process_api.dart';
import 'package:win32/win32.dart';

Future<List<String>> loadWindowsProcessPaths() =>
    Isolate.run(() => const WindowsProcessSource(Win32ProcessApi()).load());

/// Requests limited query access only; never enables privileges or inspects memory.
class Win32ProcessApi implements WindowsProcessApi {
  const Win32ProcessApi();

  static const _initialProcessCapacity = 1024;
  static const _maximumProcessCapacity = 1048576;
  static const _maximumPathCharacters = 32768;

  @override
  List<int> processIds() {
    if (!Platform.isWindows) throw UnsupportedError('Windows process enumeration is unavailable');
    final bytesReturned = calloc<Uint32>();
    try {
      for (var capacity = _initialProcessCapacity; capacity <= _maximumProcessCapacity; capacity *= 2) {
        final ids = calloc<Uint32>(capacity);
        try {
          final bytes = capacity * sizeOf<Uint32>();
          if (EnumProcesses(ids, bytes, bytesReturned) == 0) throw StateError('Cannot enumerate processes');
          if (bytesReturned.value < bytes) {
            return List.generate(bytesReturned.value ~/ sizeOf<Uint32>(), (index) => ids[index]);
          }
        } finally {
          calloc.free(ids);
        }
      }
      throw StateError('Process list exceeds the supported capacity');
    } finally {
      calloc.free(bytesReturned);
    }
  }

  @override
  String? executablePath(int processId) {
    if (!Platform.isWindows) throw UnsupportedError('Windows process enumeration is unavailable');
    final handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (handle == 0) return null;
    try {
      final buffer = calloc<Uint16>(_maximumPathCharacters);
      try {
        final length = calloc<Uint32>()..value = _maximumPathCharacters;
        try {
          if (QueryFullProcessImageName(handle, 0, buffer.cast<Utf16>(), length) == 0) return null;
          return buffer.cast<Utf16>().toDartString(length: length.value);
        } finally {
          calloc.free(length);
        }
      } finally {
        calloc.free(buffer);
      }
    } finally {
      CloseHandle(handle);
    }
  }
}
