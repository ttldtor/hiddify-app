import 'dart:convert';

import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';

/// Local Windows policy, stored separately from subscription configuration.
class WindowsAppRouting {
  const WindowsAppRouting({
    this.enabled = false,
    this.mode = AppProxyMode.exclude,
    this.processNames = const [],
    this.processPaths = const [],
  });

  final bool enabled;
  final AppProxyMode mode;
  final List<String> processNames;
  final List<String> processPaths;

  WindowsAppRouting copyWith({
    bool? enabled,
    AppProxyMode? mode,
    List<String>? processNames,
    List<String>? processPaths,
  }) => WindowsAppRouting(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    processNames: List.unmodifiable(processNames ?? this.processNames),
    processPaths: List.unmodifiable(processPaths ?? this.processPaths),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'process-names': processNames,
    'process-paths': processPaths,
  };

  String encode() => jsonEncode(toJson());

  factory WindowsAppRouting.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return WindowsAppRouting(
      enabled: json['enabled'] as bool? ?? false,
      mode: AppProxyMode.values.byName(json['mode'] as String? ?? 'exclude'),
      processNames: List<String>.unmodifiable((json['process-names'] as List?)?.cast<String>() ?? []),
      processPaths: List<String>.unmodifiable((json['process-paths'] as List?)?.cast<String>() ?? []),
    );
  }

  /// Parses one exact executable name or absolute Windows path per line.
  /// Returns a deduplicated list; throws [FormatException] on invalid input.
  static List<String> parseEntries(String text, {required bool paths}) {
    final entries = <String>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final hasInvalidCharacter = RegExp(r'[<>"|?*\x00-\x1f\x7f-\x9f]').hasMatch(value);
      final valid =
          !hasInvalidCharacter &&
          value.toLowerCase().endsWith('.exe') &&
          (paths ? _validPath(value) : !RegExp(r'[:\\/]').hasMatch(value));
      if (!valid) throw FormatException(paths ? 'Expected an absolute .exe path' : 'Expected an .exe name');
      if (seen.add(value.toLowerCase())) entries.add(value);
    }
    return List.unmodifiable(entries);
  }

  static bool _validPath(String value) {
    final List<String> components;
    if (RegExp(r'^[a-zA-Z]:\\').hasMatch(value)) {
      components = value.substring(3).split('\\');
    } else if (value.startsWith(r'\\')) {
      components = value.substring(2).split('\\');
      if (components.length < 3) return false;
    } else {
      return false;
    }
    return components.every(
      (part) =>
          part.isNotEmpty && part.trim() == part && part != '.' && part != '..' && !RegExp('[:/]').hasMatch(part),
    );
  }
}
