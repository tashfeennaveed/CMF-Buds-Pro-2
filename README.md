# Dialwheel

A radial wheel menu with a minimal settings window, built to be driven by the
dial on the CMF Buds Pro 2 case. Flutter, so the same code can become the
Android app later.

## Run it (Windows)

1. Install Flutter (3.27 or newer) and Visual Studio with "Desktop development with C++".
2. In this folder run:

   ```
   flutter create --platforms=windows,android .
   flutter pub get
   flutter run -d windows
   ```

   `flutter create .` only adds the missing platform folders; it keeps `lib/` and `pubspec.yaml`.

   For a release build, use `flutter build windows`.

## What works now

- Settings window: toggle items, move them up/down, add/edit/remove keyboard shortcuts, Save / Cancel / Reset. Config is saved as JSON in the app support folder.
- Live wheel preview that follows your enabled items.
- "Try it" dialog to test the wheel with the keyboard:
  Left/Right or mouse wheel = turn, Enter = press, Space = double press.
  Actions are only shown on screen unless you switch on "Send real actions".
- Windows actions: volume, play/pause, next/previous, mute, window switch,
  virtual desktop switch, tab switch, scroll, zoom, and custom shortcuts
  such as `Ctrl+Shift+T` or `Win+Shift+S`.

## Not done yet

- The wheel as a floating overlay on top of other apps (currently it lives in the "Try it" dialog).
- Real dial input. See below.
- Android actions (`LoggingActionRunner` is the placeholder).

## Dial input

All hardware goes through `lib/input/dial_input.dart`: anything that can produce
rotate, press and double press events can drive the wheel. The CMF dial is the
open question, because the case dial is normally handled by the Nothing X
app and I don't know yet what it exposes to a PC. Quick test:

1. Pair the buds with the PC, open the case lid, turn the dial.
2. If Windows volume changes, the dial sends media keys. A global key hook can read those.
3. If nothing happens, it needs its Bluetooth protocol read directly. Send me
   what Windows shows under Bluetooth devices and Device Manager (Human Interface Devices) and we'll work from there.

## Floating wheel

When the wheel opens with your dial, a round wheel is drawn in the middle of the
screen on top of other apps. It never takes focus and ignores mouse clicks, so
shortcuts still go to the app you are working in. Turn it off with "Show wheel
on screen" under "Use my dial".

It is drawn by the PowerShell helper. If it does not appear, look for a line
starting with `ERR wheel overlay:` in the left-panel log, or run
`powershell -ExecutionPolicy Bypass -File dial_bridge.ps1` in a normal PowerShell
window and read the first lines it prints.
