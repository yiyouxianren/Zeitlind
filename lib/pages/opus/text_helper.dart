import 'package:flutter/material.dart';
import 'package:pilipala/models/read/opus.dart';

class TextHelper {
  static Color _parseColor(String? value, BuildContext context) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return Theme.of(context).colorScheme.onBackground;

    final normalized = raw.startsWith('#') ? raw.substring(1) : raw;
    if (normalized.length != 6 && normalized.length != 8) {
      return Theme.of(context).colorScheme.onBackground;
    }

    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return Theme.of(context).colorScheme.onBackground;
    return normalized.length == 6 ? Color(parsed | 0xFF000000) : Color(parsed);
  }

  static Alignment getAlignment(int? align) {
    switch (align) {
      case 1:
        return Alignment.center;
      case 0:
        return Alignment.centerLeft;
      case 2:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  static TextSpan buildTextSpan(
      ModuleParagraphTextNode node, int? align, BuildContext context) {
    // 获取node的所有key
    if (node.nodeType != null) {
      return TextSpan(
        text: node.word?.words ?? '',
        style: TextStyle(
          fontSize:
              node.word?.fontSize != null ? node.word!.fontSize! * 0.95 : 14,
          fontWeight: node.word?.style?.bold != null
              ? FontWeight.bold
              : FontWeight.normal,
          height: align == 1 ? 2 : 1.5,
          color: _parseColor(node.word?.color, context),
        ),
      );
    } else {
      switch (node.type) {
        case 'TEXT_NODE_TYPE_WORD':
          return TextSpan(
            text: node.word?.words ?? '',
            style: TextStyle(
              fontSize: node.word?.fontSize != null
                  ? node.word!.fontSize! * 0.95
                  : 14,
              fontWeight: node.word?.style?.bold != null
                  ? FontWeight.bold
                  : FontWeight.normal,
              height: align == 1 ? 2 : 1.5,
              color: _parseColor(node.word?.color, context),
            ),
          );
        default:
          return const TextSpan(text: '');
      }
    }
  }
}
