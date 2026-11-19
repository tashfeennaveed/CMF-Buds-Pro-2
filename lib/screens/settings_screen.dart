import 'dart:io';

import 'package:flutter/material.dart';

import '../actions/shortcut_parser.dart';
import '../input/live_dial.dart';
import '../models/wheel_item.dart';
import '../services/config_store.dart';
import '../theme.dart';
import '../widgets/wheel_view.dart';
import 'wheel_test_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.initial,
    required this.onSaved,
    required this.live,
  });

  final LiveDial live;
  final ConfigStore store;
  final List<WheelItem> initial;
  final void Function(List<WheelItem> items) onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<WheelItem> _saved;
  late List<WheelItem> _draft;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.initial.map((e) => e.copy()).toList();
    _draft = widget.initial.map((e) => e.copy()).toList();
  }

  List<WheelItem> get _enabled => _draft.where((e) => e.enabled).toList();

  void _change(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
        widget.live.wheel.setItems(_draft);
      });

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _draft.length) return;
    _change(() {
      final item = _draft.removeAt(i);
      _draft.insert(j, item);
    });
  }

  Future<void> _save() async {
    await widget.store.save(_draft);
    _saved = _draft.map((e) => e.copy()).toList();
    widget.onSaved(_saved);
    if (mounted) setState(() => _dirty = false);
  }

  void _cancel() => setState(() {
        _draft = _saved.map((e) => e.copy()).toList();
        _dirty = false;
        widget.live.wheel.setItems(_draft);
      });

  void _reset() => _change(() => _draft = defaultItems());

  Future<void> _editShortcut({WheelItem? existing}) async {
    final label = TextEditingController(text: existing?.label ?? '');
    final keys = TextEditingController(text: existing?.shortcut ?? '');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add shortcut' : 'Edit shortcut'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keys,
                  decoration: InputDecoration(
                    labelText: 'Keys',
                    hintText: 'Ctrl+Shift+T',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (parseShortcut(keys.text) == null) {
                  setLocal(() => error = 'Unrecognised key combination');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final name = label.text.trim().isEmpty ? keys.text.trim() : label.text.trim();
    _change(() {
      if (existing != null) {
        existing
          ..label = name
          ..shortcut = keys.text.trim();
      } else {
        _draft.add(WheelItem(
          id: 'shortcut_${DateTime.now().microsecondsSinceEpoch}',
          label: name,
          iconKey: 'keyboard',
          kind: ActionKind.shortcut,
          mode: ItemMode.runsOnce,
          shortcut: keys.text.trim(),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _leftPanel(),
          const VerticalDivider(width: 1, color: Palette.line),
          Expanded(child: _rightPanel()),
        ],
      ),
    );
  }

  Widget _leftPanel() {
    return Container(
      width: 340,
      color: Palette.panel,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dialwheel',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your dial, your wheel.',
            style: TextStyle(color: Palette.muted),
          ),
          const Spacer(),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([widget.live, widget.live.wheel]),
              builder: (context, _) {
                final w = widget.live.wheel;
                final items = _enabled;
                final sel = (w.open && w.selected < items.length)
                    ? w.selected
                    : 0;
                return Opacity(
                  opacity: (widget.live.running && !w.open) ? 0.55 : 1,
                  child: WheelView(
                    items: items,
                    selected: sel,
                    engaged: w.engaged,
                    size: 250,
                  ),
                );
              },
            ),
          ),
          const Spacer(),
          const Center(
            child: Text(
              'Open it with a double press.\nTurn to pick, press to choose.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.muted, height: 1.5),
            ),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: widget.live,
              builder: (context, _) {
                final live = widget.live;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Use my dial',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Switch(
                          value: live.running,
                          onChanged: (v) => v ? live.start() : live.stop(),
                        ),
                      ],
                    ),
                    Text(
                      live.status,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          'Show wheel on screen',
                          style: TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        Switch(
                          value: live.showOverlay,
                          onChanged: live.setOverlay,
                        ),
                      ],
                    ),
                    if (live.log.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          live.log.join('\n'),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            fontFamily: 'Consolas',
                            color: Palette.muted,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset to default'),
                style: TextButton.styleFrom(foregroundColor: Palette.muted),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _enabled.isEmpty
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          builder: (_) => WheelTestDialog(items: _enabled),
                        ),
                child: const Text('Try it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rightPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wheel items',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Switch on what the wheel shows. The order runs clockwise from the top.',
            style: TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Palette.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.line),
              ),
              child: ListView.separated(
                itemCount: _draft.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Palette.line),
                itemBuilder: (_, i) => _row(i),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _editShortcut(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add keyboard shortcut'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _dirty ? _cancel : null,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _dirty ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final item = _draft[i];
    final isShortcut = item.kind == ActionKind.shortcut;
    final dim = item.enabled ? Palette.text : Palette.muted;
    final sub = isShortcut
        ? item.shortcut
        : (item.mode == ItemMode.runsOnce ? 'Runs once' : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: i == 0 ? null : () => _move(i, -1),
            icon: const Icon(Icons.keyboard_arrow_up),
            color: Palette.muted,
            tooltip: 'Move up',
          ),
          IconButton(
            onPressed: i == _draft.length - 1 ? null : () => _move(i, 1),
            icon: const Icon(Icons.keyboard_arrow_down),
            color: Palette.muted,
            tooltip: 'Move down',
          ),
          const SizedBox(width: 8),
          Icon(item.icon, color: dim, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: TextStyle(fontSize: 15, color: dim)),
                if (sub != null)
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
              ],
            ),
          ),
          if (isShortcut) ...[
            IconButton(
              onPressed: () => _editShortcut(existing: item),
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: Palette.muted,
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: () => _change(() => _draft.removeAt(i)),
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Palette.muted,
              tooltip: 'Remove',
            ),
          ],
          Text(
            item.enabled ? 'Yes' : 'No',
            style: const TextStyle(color: Palette.muted, fontSize: 13),
          ),
          const SizedBox(width: 10),
          Switch(
            value: item.enabled,
            onChanged: (v) => _change(() => item.enabled = v),
          ),
        ],
      ),
    );
  }
}
