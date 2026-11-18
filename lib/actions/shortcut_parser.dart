/// Parses strings like "Ctrl+Shift+T" into Windows virtual-key codes.
/// Pure Dart, so the Android version can reuse it for display and validation.
const _named = <String, int>{
  'ctrl': 0x11,
  'control': 0x11,
  'shift': 0x10,
  'alt': 0x12,
  'win': 0x5B,
  'meta': 0x5B,
  'tab': 0x09,
  'enter': 0x0D,
  'esc': 0x1B,
  'escape': 0x1B,
  'space': 0x20,
  'backspace': 0x08,
  'delete': 0x2E,
  'del': 0x2E,
  'home': 0x24,
  'end': 0x23,
  'pageup': 0x21,
  'pagedown': 0x22,
  'left': 0x25,
  'up': 0x26,
  'right': 0x27,
  'down': 0x28,
};

/// Returns the key codes in press order (modifiers first), or null if any
/// part of the shortcut is not recognised.
List<int>? parseShortcut(String text) {
  final parts = text
      .split('+')
      .map((p) => p.trim().toLowerCase())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  final codes = <int>[];
  for (final p in parts) {
    int? code = _named[p];
    if (code == null && p.length == 1) {
      final c = p.codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7A) code = c - 0x20; // a-z -> A-Z
      if (c >= 0x30 && c <= 0x39) code = c; // 0-9
    }
    if (code == null && p.startsWith('f')) {
      final n = int.tryParse(p.substring(1));
      if (n != null && n >= 1 && n <= 12) code = 0x70 + n - 1;
    }
    if (code == null) return null;
    codes.add(code);
  }

  const modifiers = {0x10, 0x11, 0x12, 0x5B};
  final mods = codes.where(modifiers.contains).toList();
  final keys = codes.where((c) => !modifiers.contains(c)).toList();
  return [...mods, ...keys];
}
