/// The three things a dial can do. Any hardware source (keyboard simulator,
/// a Bluetooth/HID adapter for the CMF case dial, an Android service) only
/// has to turn its raw input into these events.
enum DialEventType { rotate, press, doublePress }

class DialEvent {
  const DialEvent.rotate(this.steps) : type = DialEventType.rotate;
  const DialEvent.press()
      : type = DialEventType.press,
        steps = 0;
  const DialEvent.doublePress()
      : type = DialEventType.doublePress,
        steps = 0;

  final DialEventType type;

  /// Positive = clockwise, negative = counter-clockwise.
  final int steps;
}
