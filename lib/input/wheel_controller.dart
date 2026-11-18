import 'package:flutter/foundation.dart';

import '../actions/action_runner.dart';
import '../input/dial_input.dart';
import '../models/wheel_item.dart';

/// Holds the wheel state and turns dial events into selection and actions.
///
/// Flow: double press opens/closes. Turn to move the highlight. Press to
/// choose: runs-once items fire and close the wheel; continuous items take
/// over the dial until pressed again.
class WheelController extends ChangeNotifier {
  WheelController({required List<WheelItem> items, required this.runner})
      : _all = items;

  List<WheelItem> _all;
  ActionRunner runner;

  int selected = 0;
  bool open = false;
  bool engaged = false;

  List<WheelItem> get items => _all.where((e) => e.enabled).toList();

  void setItems(List<WheelItem> value) {
    _all = value;
    final n = items.length;
    selected = n == 0 ? 0 : selected.clamp(0, n - 1);
    notifyListeners();
  }

  void close() {
    runner.release();
    open = false;
    engaged = false;
    notifyListeners();
  }

  void handle(DialEvent e) {
    final list = items;
    switch (e.type) {
      case DialEventType.doublePress:
        runner.release();
        open = !open;
        engaged = false;
      case DialEventType.rotate:
        if (!open || list.isEmpty) return;
        if (engaged) {
          runner.rotate(list[selected], e.steps);
        } else {
          selected = ((selected + e.steps) % list.length + list.length) %
              list.length;
        }
      case DialEventType.press:
        if (!open || list.isEmpty) return;
        if (engaged) {
          runner.release();
          engaged = false;
          open = false;
        } else {
          final item = list[selected];
          if (item.mode == ItemMode.runsOnce) {
            runner.press(item);
            open = false;
          } else {
            engaged = true;
          }
        }
    }
    notifyListeners();
  }
}
