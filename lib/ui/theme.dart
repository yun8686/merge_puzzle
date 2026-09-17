import 'package:flutter/material.dart';

/// 奇数=暖色、偶数=寒色。この2色がゲームの中心情報なので、
/// 背景は暗く沈めてタイルとエフェクトを目立たせる。
class Palette {
  static const background = Color(0xFF0E0E16);
  static const surface = Color(0xFF191926);
  static const boardBg = Color(0xFF14141F);

  static const oddA = Color(0xFFFF9A3D);
  static const oddB = Color(0xFFFF4E7A);
  static const evenA = Color(0xFF3DD6FF);
  static const evenB = Color(0xFF4E6BFF);

  static const textPrimary = Color(0xFFF2F2F7);
  static const textMuted = Color(0xFF8C8CA6);
  static const danger = Color(0xFFFF4E5E);

  static LinearGradient gradientFor(bool isOdd) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isOdd ? const [oddA, oddB] : const [evenA, evenB],
      );

  static Color glowFor(bool isOdd) => isOdd ? oddB : evenA;
  static Color baseFor(bool isOdd) => isOdd ? oddA : evenA;
}

/// チェインの長さに応じた煽り文句。長いほど派手に。
class ChainRank {
  const ChainRank(this.label, this.color);

  final String label;
  final Color color;

  static ChainRank? of(int length) {
    if (length >= 12) return const ChainRank('UNREAL!!!', Color(0xFFFFE14E));
    if (length >= 10) return const ChainRank('INCREDIBLE!!', Color(0xFFFFB03D));
    if (length >= 8) return const ChainRank('AMAZING!!', Color(0xFFFF7A4E));
    if (length >= 6) return const ChainRank('GREAT!', Color(0xFF6BE8FF));
    if (length >= 5) return const ChainRank('NICE', Color(0xFF8CFFB0));
    return null;
  }
}
