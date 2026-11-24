import 'package:flutter/material.dart';

/// 糖果色主题（与安卓版同风格：奶油底 + 品牌绿）
class AppTheme {
  static const brandGreen = Color(0xFF4CB878);
  static const greenDeep = Color(0xFF2E7D4F);
  static const warmGray = Color(0xFF9E9689);
  static const warmInk = Color(0xFF4A443D);
  static const sand = Color(0xFFF3EDE2);
  static const pinkContainer = Color(0xFFFDECF0);
  static const yellowContainer = Color(0xFFFFF6DC);
  static const windowBackground = Color(0xFFFFFBF2);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandGreen,
        primary: brandGreen,
        primaryContainer: const Color(0xFFDCF3E4),
        onPrimaryContainer: Color(0xFF1B5E38),
        surface: windowBackground,
      ),
      scaffoldBackgroundColor: windowBackground,
    );
    return base;
  }
}

/// 类目小图标
String subjectEmoji(String id) {
  switch (id) {
    case 'english':
      return '🔤';
    case 'math':
      return '🧮';
    case 'idiom':
      return '📖';
    default:
      return '🎬';
  }
}

String formatDuration(int ms) {
  final s = (ms / 1000).floor();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

String formatSeconds(int sec) {
  final m = sec ~/ 60;
  final r = sec % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}
