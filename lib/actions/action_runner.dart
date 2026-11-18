import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../models/wheel_item.dart';
import 'shortcut_parser.dart';

/// Carries out what a wheel item does. One implementation per platform.
abstract class ActionRunner {
  /// Dial turned while a continuous item is engaged.
  void rotate(WheelItem item, int steps);

  /// Item chosen (runs-once items) .
  void press(WheelItem item);

  /// The wheel closed or the item was left. Lets a runner let go of keys it
  /// is holding down (for example Alt while switching windows).
  void release() {}

  /// Short human-readable description, used by the preview runner.
  String describe(WheelItem item, {int steps = 0}) =>
      steps == 0 ? item.label : '${item.label} ${steps > 0 ? '+' : ''}$steps';
}

ActionRunner createActionRunner() =>
    Platform.isWindows ? WindowsActionRunner() : LoggingActionRunner();

/// Does nothing except report; used for the on-screen test and as the
/// placeholder for Android until its native actions are written.
class LoggingActionRunner extends ActionRunner {
  LoggingActionRunner({this.onAction});
  final void Function(String text)? onAction;

  @override
  void rotate(WheelItem item, int steps) {
    final t = describe(item, steps: steps);
    developer.log(t, name: 'dialwheel');
    onAction?.call(t);
  }

  @override
  void press(WheelItem item) {
    final t = item.kind == ActionKind.shortcut
        ? '${item.label} (${item.shortcut})'
        : describe(item);
    developer.log(t, name: 'dialwheel');
    onAction?.call(t);
  }
}

// Virtual-key codes used below.
const _vkShift = 0x10;
const _vkCtrl = 0x11;
const _vkAlt = 0x12;
const _vkWin = 0x5B;
const _vkTab = 0x09;
const _vkLeft = 0x25;
const _vkRight = 0x27;
const _vkMute = 0xAD;
const _vkVolDown = 0xAE;
const _vkVolUp = 0xAF;
const _vkNext = 0xB0;
const _vkPrev = 0xB1;
const _vkPlayPause = 0xB3;

const _extendedKeys = {
  0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2E, 0x5B, 0x5C, //
};

/// Sends real input on Windows through SendInput.
class WindowsActionRunner extends ActionRunner {
  @override
  void rotate(WheelItem item, int steps) {
    if (steps == 0) return;
    final fwd = steps > 0;
    final n = steps.abs();
    switch (item.kind) {
      case ActionKind.volume:
        for (var i = 0; i < n; i++) {
          _combo([fwd ? _vkVolUp : _vkVolDown]);
        }
      case ActionKind.switchWindow:
        // Alt stays held between steps, like holding Alt and tapping Tab,
        // so both directions walk through every open window.
        for (var i = 0; i < n; i++) {
          _windowStep(fwd);
        }
      case ActionKind.switchDesktop:
        for (var i = 0; i < n; i++) {
          _combo([_vkWin, _vkCtrl, fwd ? _vkRight : _vkLeft]);
        }
      case ActionKind.switchTab:
        for (var i = 0; i < n; i++) {
          _combo(fwd ? [_vkCtrl, _vkTab] : [_vkCtrl, _vkShift, _vkTab]);
        }
      case ActionKind.scroll:
        _wheel(fwd ? -120 * n : 120 * n);
      case ActionKind.zoom:
        _combo([_vkCtrl], hold: () => _wheel(fwd ? -120 * n : 120 * n));
      default:
        break;
    }
  }

  @override
  void press(WheelItem item) {
    switch (item.kind) {
      case ActionKind.mediaPlayPause:
        _combo([_vkPlayPause]);
      case ActionKind.mediaNext:
        _combo([_vkNext]);
      case ActionKind.mediaPrevious:
        _combo([_vkPrev]);
      case ActionKind.mute:
        _combo([_vkMute]);
      case ActionKind.shortcut:
        final keys = parseShortcut(item.shortcut);
        if (keys != null) _combo(keys);
      default:
        break;
    }
  }

  bool _altHeld = false;
  Timer? _altTimer;

  void _windowStep(bool forward) {
    if (!_altHeld) {
      _key(_vkAlt, up: false);
      _altHeld = true;
    }
    if (!forward) _key(_vkShift, up: false);
    _key(_vkTab, up: false);
    _key(_vkTab, up: true);
    if (!forward) _key(_vkShift, up: true);
    // If the dial stops, let go of Alt so the highlighted window opens.
    _altTimer?.cancel();
    _altTimer = Timer(const Duration(milliseconds: 1200), release);
  }

  @override
  void release() {
    _altTimer?.cancel();
    _altTimer = null;
    if (_altHeld) {
      _key(_vkAlt, up: true);
      _altHeld = false;
    }
  }

  void _key(int vk, {required bool up}) {
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.wVk = vk;
      input.ref.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      calloc.free(input);
    }
  }

  /// Presses [keys] in order, then releases them in reverse. If [hold] is
  /// given it runs while the keys are down (used for Ctrl + wheel).
  void _combo(List<int> keys, {void Function()? hold}) {
    final count = keys.length * 2;
    final inputs = calloc<INPUT>(count);
    try {
      var idx = 0;
      void add(int vk, bool up) {
        final ref = (inputs + idx).ref;
        ref.type = INPUT_KEYBOARD;
        ref.ki.wVk = vk;
        var flags = up ? KEYEVENTF_KEYUP : 0;
        if (_extendedKeys.contains(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
        ref.ki.dwFlags = flags;
        idx++;
      }

      for (final k in keys) {
        add(k, false);
      }
      if (hold != null) {
        SendInput(keys.length, inputs, sizeOf<INPUT>());
        hold();
        final ups = calloc<INPUT>(keys.length);
        try {
          for (var i = 0; i < keys.length; i++) {
            final ref = (ups + i).ref;
            ref.type = INPUT_KEYBOARD;
            ref.ki.wVk = keys[keys.length - 1 - i];
            ref.ki.dwFlags = KEYEVENTF_KEYUP;
          }
          SendInput(keys.length, ups, sizeOf<INPUT>());
        } finally {
          calloc.free(ups);
        }
        return;
      }
      for (final k in keys.reversed) {
        add(k, true);
      }
      SendInput(count, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }

  void _wheel(int delta) {
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_MOUSE;
      input.ref.mi.dwFlags = MOUSEEVENTF_WHEEL;
      input.ref.mi.mouseData = delta & 0xFFFFFFFF;
      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      calloc.free(input);
    }
  }
}
