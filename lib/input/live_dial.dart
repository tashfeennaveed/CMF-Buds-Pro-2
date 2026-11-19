import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wheel_item.dart';
import '../services/bridge_script.dart';
import 'dial_input.dart';
import 'wheel_controller.dart';

/// Connects the real CMF case dial (through a small PowerShell helper) to
/// the wheel.
///
/// How the dial maps to wheel events:
///  * turn            -> volume steps, read by the helper -> rotate
///  * press           -> play/pause flip, read by the helper
///  * double press    -> two flips within about a second (net music change
///                       is zero) -> opens the wheel
///  * press, wheel open -> "choose"; the flip is undone so music is unchanged
class LiveDial extends ChangeNotifier {
  LiveDial({required this.wheel}) {
    wheel.addListener(_syncOverlay);
  }

  final WheelController wheel;

  /// Whether the wheel is also drawn on screen, on top of other apps.
  bool showOverlay = true;
  String _sentItems = '';
  String _sentState = '';

  void setOverlay(bool value) {
    showOverlay = value;
    _syncOverlay();
    notifyListeners();
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]'), ' ');

  /// Tells the helper what the floating wheel should show. Only changes are
  /// sent, and these commands are kept out of the on-screen log.
  void _syncOverlay() {
    if (!running) return;
    final open = showOverlay && wheel.open;
    if (open) {
      final text =
          wheel.items.map((e) => '${e.iconKey}\t${_clean(e.label)}').join('\n');
      if (text != _sentItems) {
        _sentItems = text;
        _send('WITEMS ${base64Encode(utf8.encode(text))}', quiet: true);
      }
    }
    final state = open ? '1 ${wheel.selected} ${wheel.engaged ? 1 : 0}' : '0 0 0';
    if (state != _sentState) {
      _sentState = state;
      _send('WSTATE $state', quiet: true);
    }
  }

  Process? _proc;
  bool running = false;
  String status = 'Off';
  String lastEvent = '';

  /// Recent helper traffic ("<" from helper, ">" to helper), newest last.
  final List<String> log = [];

  void _log(String text) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    log.add('$t $text');
    if (log.length > 6) log.removeAt(0);
  }

  bool _parked = false;
  DateTime? _pendingFlip;
  DateTime _ignoreFlipsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _idle;

  // The buds swallow a fast double click, so "double press" here means two
  // separate presses within this window (about one second apart works best).
  static const _doublePressWindow = Duration(milliseconds: 2200);
  static const _idleClose = Duration(seconds: 8);

  // Minimum time between two item changes while picking. Raise it if the
  // wheel still skips an item; lower it if fast turns feel sluggish.
  static const _pickDebounce = Duration(milliseconds: 150);

  // Same idea while stepping through tabs, windows or desktops.
  static const _stepDebounce = Duration(milliseconds: 150);
  DateTime _lastPick = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (running || !Platform.isWindows) return;
    status = 'Starting...';
    notifyListeners();
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}dial_bridge.ps1');
      await file.writeAsString(bridgeScript);

      // Second command channel, in case stdin is not delivered to the helper.
      final cmd = File('${dir.path}${Platform.pathSeparator}dial_cmd.txt');
      try {
        if (await cmd.exists()) await cmd.delete();
      } catch (_) {}
      _cmdFile = cmd;
      _seq = 0;
      _sentItems = '';
      _sentState = '';
      log.clear();

      final p = await Process.start('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        file.path,
        '-CmdFile',
        cmd.path,
        '-ParentPid',
        '$pid',
      ]);
      _proc = p;
      running = true;

      p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      p.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) {
        if (l.trim().isEmpty) return;
        lastEvent = 'Helper error: ${l.trim()}';
        _log('! ${l.trim()}');
        notifyListeners();
      });
      p.exitCode.then((code) {
        if (_proc != p) return;
        _proc = null;
        running = false;
        _parked = false;
        status = 'Stopped (code $code)';
        wheel.close();
        notifyListeners();
      });
    } catch (e) {
      running = false;
      _proc = null;
      status = 'Could not start: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    _idle?.cancel();
    _send('RESTORE');
    _send('QUIT');
    _proc = null;
    running = false;
    _parked = false;
    status = 'Off';
    wheel.close();
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 800), p.kill);
  }

  File? _cmdFile;
  int _seq = 0;

  /// Sends "<seq> <COMMAND>" to the helper on stdin and through a file.
  /// The helper ignores a sequence number it has already seen.
  void _send(String cmd, {bool quiet = false}) {
    final line = '${++_seq} $cmd';
    if (!quiet) _log('> $line');
    try {
      _proc?.stdin.writeln(line);
    } catch (_) {
      // Helper already gone; nothing to do.
    }
    try {
      // One line per command, appended, so back-to-back commands all arrive.
      _cmdFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      _log('! could not write command: $e');
    }
  }

  void _onLine(String line) {
    final l = line.trim();
    final noise = l.startsWith('STATE') ||
        l.startsWith('TRACK') ||
        (l.startsWith('CMD') && (l.endsWith('WSTATE') || l.endsWith('WITEMS')));
    if (!noise) _log('< $l');
    if (l == 'READY') {
      status = 'Connected. Press the dial, then press again about a second later, to open the wheel.';
    } else if (l.startsWith('ROT ')) {
      var n = int.tryParse(l.substring(4).split(' ').first) ?? 0;
      if (n != 0 && wheel.open) {
        final items = wheel.items;
        final kind = (wheel.engaged && wheel.selected < items.length)
            ? items[wheel.selected].kind
            : null;
        final oneAtATime = !wheel.engaged ||
            kind == ActionKind.switchTab ||
            kind == ActionKind.switchWindow ||
            kind == ActionKind.switchDesktop;
        if (oneAtATime) {
          // Picking an item, or stepping through tabs, windows or desktops:
          // move exactly one place per turn, and ignore a second step that
          // follows within a very short time.
          final now = DateTime.now();
          final gap = wheel.engaged ? _stepDebounce : _pickDebounce;
          if (now.difference(_lastPick) < gap) {
            notifyListeners();
            return;
          }
          _lastPick = now;
          n = n > 0 ? 1 : -1;
        }
        lastEvent = 'Turn ${n > 0 ? '+' : ''}$n';
        wheel.handle(DialEvent.rotate(n));
        _afterWheelChange();
      }
    } else if (l.startsWith('FLIP')) {
      _onFlip();
    } else if (l.startsWith('VOL') || l.startsWith('PARK')) {
      // Diagnostics from the helper, shown in the "Last:" line.
      lastEvent = l;
    }
    notifyListeners();
  }

  void _onFlip() {
    final now = DateTime.now();

    if (wheel.open) {
      _ignoreFlipsUntil = now.add(const Duration(milliseconds: 1500));
      final items = wheel.items;
      final item = wheel.selected < items.length ? items[wheel.selected] : null;
      final keepToggle =
          !wheel.engaged && item?.kind == ActionKind.mediaPlayPause;
      if (keepToggle) {
        // The press already toggled the music, which is exactly what this
        // item does. Keep it and just close the wheel.
        lastEvent = 'Play / Pause';
        wheel.close();
      } else {
        // Undo the music change this press caused, then treat it as "choose".
        _send('UNDOFLIP');
        lastEvent = 'Press';
        wheel.handle(const DialEvent.press());
      }
      _afterWheelChange();
      return;
    }

    if (now.isBefore(_ignoreFlipsUntil)) {
      _pendingFlip = null;
      return;
    }

    final first = _pendingFlip;
    if (first != null && now.difference(first) <= _doublePressWindow) {
      _pendingFlip = null;
      lastEvent = 'Double press';
      wheel.handle(const DialEvent.doublePress());
      _afterWheelChange();
    } else {
      _pendingFlip = now;
      lastEvent = 'Press (music toggled)';
    }
  }

  /// Keeps the helper's volume parking in step with the wheel state.
  /// While the Volume item is engaged the dial is left alone so it changes
  /// the real volume.
  void _afterWheelChange() {
    final items = wheel.items;
    final volumeEngaged = wheel.engaged &&
        items.isNotEmpty &&
        items[wheel.selected].kind == ActionKind.volume;
    final wantParked = wheel.open && !volumeEngaged;
    if (wantParked != _parked) {
      _send(wantParked ? 'PARK' : 'RESTORE');
      _parked = wantParked;
    }

    _idle?.cancel();
    if (wheel.open) {
      _idle = Timer(_idleClose, () {
        wheel.close();
        _afterWheelChange();
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    wheel.removeListener(_syncOverlay);
    _idle?.cancel();
    final p = _proc;
    if (p != null) {
      _send('RESTORE');
      _send('QUIT');
      Future.delayed(const Duration(milliseconds: 800), p.kill);
    }
    super.dispose();
  }
}
