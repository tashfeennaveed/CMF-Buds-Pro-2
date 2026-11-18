import 'package:flutter/material.dart';

/// What a wheel item does when it is chosen.
enum ActionKind {
  volume, // turning the dial adjusts volume while selected
  mediaPlayPause,
  mediaNext,
  mediaPrevious,
  mute,
  switchWindow, // Alt+Tab style
  switchDesktop, // Win+Ctrl+Left/Right
  switchTab, // Ctrl+Tab / Ctrl+Shift+Tab
  scroll,
  zoom,
  shortcut, // user-defined keyboard shortcut
}

/// Whether an item takes over the dial (continuous) or fires once and closes.
enum ItemMode { continuous, runsOnce }

/// Icons are stored by name and looked up from this const table, so Flutter
/// can still strip unused icons from release builds.
const Map<String, IconData> wheelIcons = {
  'volume': Icons.volume_up_outlined,
  'play': Icons.play_arrow_outlined,
  'windows': Icons.web_asset_outlined,
  'desktops': Icons.desktop_windows_outlined,
  'tabs': Icons.tab_outlined,
  'scroll': Icons.mouse_outlined,
  'zoom': Icons.zoom_in_outlined,
  'mute': Icons.volume_off_outlined,
  'next': Icons.skip_next_outlined,
  'previous': Icons.skip_previous_outlined,
  'keyboard': Icons.keyboard_outlined,
};

class WheelItem {
  WheelItem({
    required this.id,
    required this.label,
    required this.iconKey,
    required this.kind,
    required this.mode,
    this.enabled = true,
    this.shortcut = '',
  });

  final String id;
  String label;
  String iconKey;
  ActionKind kind;
  ItemMode mode;
  bool enabled;

  /// Used when [kind] is [ActionKind.shortcut], e.g. "Ctrl+Shift+T".
  String shortcut;

  IconData get icon => wheelIcons[iconKey] ?? Icons.keyboard_outlined;

  WheelItem copy() => WheelItem(
        id: id,
        label: label,
        iconKey: iconKey,
        kind: kind,
        mode: mode,
        enabled: enabled,
        shortcut: shortcut,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': iconKey,
        'kind': kind.name,
        'mode': mode.name,
        'enabled': enabled,
        'shortcut': shortcut,
      };

  factory WheelItem.fromJson(Map<String, dynamic> j) {
    final ic = j['icon'];
    return WheelItem(
      id: j['id'] as String,
      label: j['label'] as String,
      // Older saved configs stored a number here; fall back to a default.
      iconKey: ic is String ? ic : 'keyboard',
      kind: ActionKind.values.byName(j['kind'] as String),
      mode: ItemMode.values.byName(j['mode'] as String),
      enabled: j['enabled'] as bool? ?? true,
      shortcut: j['shortcut'] as String? ?? '',
    );
  }
}

/// The custom default set. Order runs clockwise from the top.
List<WheelItem> defaultItems() => [
      WheelItem(
        id: 'volume',
        label: 'Volume',
        iconKey: 'volume',
        kind: ActionKind.volume,
        mode: ItemMode.continuous,
      ),
      WheelItem(
        id: 'media',
        label: 'Play / Pause',
        iconKey: 'play',
        kind: ActionKind.mediaPlayPause,
        mode: ItemMode.runsOnce,
      ),
      WheelItem(
        id: 'windows',
        label: 'Windows',
        iconKey: 'windows',
        kind: ActionKind.switchWindow,
        mode: ItemMode.continuous,
      ),
      WheelItem(
        id: 'desktops',
        label: 'Desktops',
        iconKey: 'desktops',
        kind: ActionKind.switchDesktop,
        mode: ItemMode.continuous,
      ),
      WheelItem(
        id: 'tabs',
        label: 'Tabs',
        iconKey: 'tabs',
        kind: ActionKind.switchTab,
        mode: ItemMode.continuous,
      ),
      WheelItem(
        id: 'scroll',
        label: 'Scroll',
        iconKey: 'scroll',
        kind: ActionKind.scroll,
        mode: ItemMode.continuous,
      ),
      WheelItem(
        id: 'shortcut1',
        label: 'Undo',
        iconKey: 'keyboard',
        kind: ActionKind.shortcut,
        mode: ItemMode.runsOnce,
        shortcut: 'Ctrl+Z',
      ),
      WheelItem(
        id: 'shortcut2',
        label: 'Screenshot',
        iconKey: 'keyboard',
        kind: ActionKind.shortcut,
        mode: ItemMode.runsOnce,
        shortcut: 'Win+Shift+S',
      ),
    ];
