import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/wheel_item.dart';
import '../theme.dart';

/// The radial wheel. Items run clockwise from the top.
class WheelView extends StatelessWidget {
  const WheelView({
    super.key,
    required this.items,
    required this.selected,
    this.engaged = false,
    this.size = 260,
  });

  final List<WheelItem> items;
  final int selected;
  final bool engaged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final r = size / 2;
    final ring = r - 36;
    const node = 44.0;

    final sel = (n > 0 && selected < n) ? items[selected] : null;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.panel,
              border: Border.all(color: Palette.line),
            ),
          ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: r + ring * math.cos(-math.pi / 2 + 2 * math.pi * i / n) -
                  node / 2,
              top: r + ring * math.sin(-math.pi / 2 + 2 * math.pi * i / n) -
                  node / 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: node,
                height: node,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == selected ? Palette.accent : Colors.transparent,
                  border: Border.all(
                    color: i == selected && engaged
                        ? Palette.text
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  items[i].icon,
                  size: 22,
                  color: i == selected ? Palette.onAccent : Palette.muted,
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sel?.label ?? 'No items',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                engaged ? 'Turn to adjust' : '$n items',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
