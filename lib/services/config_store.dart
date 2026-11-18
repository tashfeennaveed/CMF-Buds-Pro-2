import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/wheel_item.dart';

/// Saves and loads the wheel configuration as a JSON file.
class ConfigStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}dialwheel_config.json');
  }

  Future<List<WheelItem>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return defaultItems();
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = (data['items'] as List)
          .map((e) => WheelItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return list.isEmpty ? defaultItems() : list;
    } catch (_) {
      // Corrupt or unreadable config: fall back to defaults.
      return defaultItems();
    }
  }

  Future<void> save(List<WheelItem> items) async {
    final f = await _file();
    final json = const JsonEncoder.withIndent('  ')
        .convert({'items': items.map((e) => e.toJson()).toList()});
    await f.writeAsString(json);
  }
}
