import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../actions/action_runner.dart';
import '../input/dial_input.dart';
import '../input/wheel_controller.dart';
import '../models/wheel_item.dart';
import '../theme.dart';
import '../widgets/wheel_view.dart';

/// Try the wheel with the keyboard before real dial hardware is connected.
/// Left/Right or mouse wheel = turn, Enter = press, Space = double press.
class WheelTestDialog extends StatefulWidget {
  const WheelTestDialog({super.key, required this.items});
  final List<WheelItem> items;

  @override
  State<WheelTestDialog> createState() => _WheelTestDialogState();
}

class _WheelTestDialogState extends State<WheelTestDialog> {
  late final WheelController _c;
  late final LoggingActionRunner _preview;
  final _real = createActionRunner();
  final _focus = FocusNode();
  String _last = '';
  bool _live = false;

  @override
  void initState() {
    super.initState();
    _preview = LoggingActionRunner(
      onAction: (t) => setState(() => _last = t),
    );
    _c = WheelController(items: widget.items, runner: _preview)..open = true;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(DialEvent e) {
    if (e.type == DialEventType.rotate && _c.engaged && _live) {
      final item = _c.items[_c.selected];
      setState(() => _last = _preview.describe(item, steps: e.steps));
    }
    _c.handle(e);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      _send(const DialEvent.rotate(1));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _send(const DialEvent.rotate(-1));
    } else if (k == LogicalKeyboardKey.enter) {
      _send(const DialEvent.press());
    } else if (k == LogicalKeyboardKey.space) {
      _send(const DialEvent.doublePress());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _toggleLive(bool v) {
    setState(() => _live = v);
    _c.runner = v ? _real : _preview;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: (s) {
            if (s is PointerScrollEvent) {
              _send(DialEvent.rotate(s.scrollDelta.dy > 0 ? 1 : -1));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SizedBox(
              width: 340,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_c.open)
                      WheelView(
                        items: _c.items,
                        selected: _c.selected,
                        engaged: _c.engaged,
                      )
                    else
                      const SizedBox(
                        height: 260,
                        child: Center(
                          child: Text(
                            'Wheel closed\nPress Space to open',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Palette.muted),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      'Left / Right or scroll: turn\nEnter: press   Space: double press',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Palette.muted),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _last.isEmpty ? ' ' : 'Last action: $_last',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Send real actions',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Switch(value: _live, onChanged: _toggleLive),
                      ],
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
