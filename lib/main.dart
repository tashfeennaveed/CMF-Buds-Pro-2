import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'actions/action_runner.dart';
import 'input/live_dial.dart';
import 'input/wheel_controller.dart';
import 'models/wheel_item.dart';
import 'screens/settings_screen.dart';
import 'services/config_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 720),
        minimumSize: Size(900, 640),
        title: 'Dialwheel settings',
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final store = ConfigStore();
  final items = await store.load();
  final wheel = WheelController(items: items, runner: createActionRunner());
  final live = LiveDial(wheel: wheel);
  runApp(DialwheelApp(store: store, items: items, live: live));
}

class DialwheelApp extends StatelessWidget {
  const DialwheelApp({
    super.key,
    required this.store,
    required this.items,
    required this.live,
  });

  final ConfigStore store;
  final List<WheelItem> items;
  final LiveDial live;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dialwheel',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: SettingsScreen(
        store: store,
        initial: items,
        live: live,
        onSaved: (_) {},
      ),
    );
  }
}
