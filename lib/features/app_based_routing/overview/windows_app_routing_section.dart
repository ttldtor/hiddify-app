import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/app_based_routing/data/windows_app_routing_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/windows_process_source.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/windows_app_routing.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class WindowsAppRoutingSection extends ConsumerStatefulWidget {
  const WindowsAppRoutingSection({super.key});

  @override
  ConsumerState<WindowsAppRoutingSection> createState() => _WindowsAppRoutingSectionState();
}

class _WindowsAppRoutingSectionState extends ConsumerState<WindowsAppRoutingSection> {
  late WindowsAppRouting _draft;
  late final TextEditingController _names;
  late final TextEditingController _paths;
  bool _dirty = false;
  bool _saving = false;
  bool _picking = false;
  bool _invalidNames = false;
  bool _invalidPaths = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(windowsAppRoutingProvider);
    _names = TextEditingController(text: _draft.processNames.join('\n'));
    _paths = TextEditingController(text: _draft.processPaths.join('\n'));
  }

  @override
  void dispose() {
    _names.dispose();
    _paths.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _status = null;
  });

  Future<void> _save() async {
    final t = ref.read(translationsProvider).requireValue.pages.settings.routing.windowsAppRouting;
    List<String>? names;
    List<String>? paths;
    try {
      names = WindowsAppRouting.parseEntries(_names.text, paths: false);
    } on FormatException {
      // Keep the draft so the invalid entry can be corrected.
    }
    try {
      paths = WindowsAppRouting.parseEntries(_paths.text, paths: true);
    } on FormatException {
      // Keep the draft so the invalid entry can be corrected.
    }
    setState(() {
      _invalidNames = names == null;
      _invalidPaths = paths == null;
    });
    if (names == null || paths == null) return;
    final policy = _draft.copyWith(processNames: names, processPaths: paths);
    setState(() => _saving = true);
    var saved = false;
    try {
      await ref.read(windowsAppRoutingProvider.notifier).update(policy);
      // update returns void even when persistence fails; acknowledge only readback.
      saved = ref.read(windowsAppRoutingProvider).encode() == policy.encode();
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = !saved;
      _status = saved ? t.saved : t.saveFailed;
      if (saved) _draft = policy;
    });
  }

  Future<void> _pick({required bool running}) async {
    final t = ref.read(translationsProvider).requireValue.pages.settings.routing.windowsAppRouting;
    setState(() => _picking = true);
    try {
      String? path;
      if (running) {
        final paths = await ref.read(windowsProcessLoaderProvider)();
        if (!mounted) return;
        path = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(t.runningApps),
            children: [
              if (paths.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t.noProcesses)),
              for (final path in paths)
                SimpleDialogOption(onPressed: () => Navigator.pop(context, path), child: Text(path)),
              SimpleDialogOption(onPressed: () => Navigator.pop(context), child: Text(t.close)),
            ],
          ),
        );
      } else {
        path = await ref.read(windowsExecutableChooserProvider)();
      }
      if (!mounted || path == null) return;
      final selected = WindowsAppRouting.parseEntries(path, paths: true);
      _paths.text = [_paths.text, ...selected].where((entry) => entry.trim().isNotEmpty).join('\n');
      _changed();
    } catch (_) {
      if (mounted) setState(() => _status = t.pickFailed);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider).requireValue;
    final t = translations.pages.settings.routing.windowsAppRouting;
    final available = ref.watch(ConfigOptions.serviceMode) == ServiceMode.tun;
    final busy = _saving || _picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          title: Text(t.title),
          subtitle: Text(available ? t.tunOnly : t.tunUnavailable),
          value: _draft.enabled,
          onChanged: busy
              ? null
              : (value) {
                  _draft = _draft.copyWith(enabled: value);
                  _changed();
                },
        ),
        if (_draft.enabled || _dirty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in [AppProxyMode.exclude, AppProxyMode.include])
                      ChoiceChip(
                        label: Text(mode == AppProxyMode.exclude ? t.bypass : t.proxy),
                        selected: _draft.mode == mode,
                        onSelected: busy
                            ? null
                            : (_) {
                                _draft = _draft.copyWith(mode: mode);
                                _changed();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_draft.mode == AppProxyMode.exclude ? t.bypassDescription : t.proxyDescription),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('windows-routing-names'),
                  controller: _names,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: t.names,
                    helperText: t.namesHelp,
                    helperMaxLines: 3,
                    errorText: _invalidNames ? t.invalidNames : null,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _changed(),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('windows-routing-paths'),
                  controller: _paths,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: t.paths,
                    helperText: t.pathsHelp(path: r'C:\Apps\browser.exe'),
                    helperMaxLines: 3,
                    errorText: _invalidPaths ? t.invalidPaths : null,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _changed(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: busy ? null : () => _pick(running: false),
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(t.chooseFile),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : () => _pick(running: true),
                      icon: const Icon(Icons.apps_rounded),
                      label: Text(t.runningApps),
                    ),
                  ],
                ),
                if (_picking) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(t.childrenNotice),
                const SizedBox(height: 8),
                Text(t.dnsNotice),
                const SizedBox(height: 8),
                Text(t.unknownNotice),
              ],
            ),
          ),
        if (_dirty || _status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(liveRegion: true, child: Text(_status ?? t.unsaved)),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: busy || !_dirty ? null : _save,
                    child: Text(_saving ? t.saving : translations.common.save),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 3, thickness: 3),
      ],
    );
  }
}
