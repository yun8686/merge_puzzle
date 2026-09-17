import 'package:flutter/material.dart';

/// 奇数=暖色、偶数=寒色。この2色がゲームの中心情報なので、
/// 背景は暗く沈めてタイルとエフェクトを目立たせる。
class Palette {
  static const background = Color(0xFF07070F);

  /// 盤面の後ろに敷く放射グラデの色。真っ黒だと平坦に見えるので、
  /// 中央だけわずかに持ち上げて奥行きを出す。
  static const backgroundGlow = Color(0xFF1B1B3C);

  static const surface = Color(0xFF191926);

  /// スコアなどを載せるパネル。背景から1段浮かせる。
  static const panel = Color(0xFF141424);
  static const panelBorder = Color(0xFF2A2A48);

  static const boardBg = Color(0xFF0F0F1C);

  /// 盤面の空きマスのくぼみ。タイルが乗る「受け皿」に見せる。
  static const boardWell = Color(0xFF1A1A2E);

  static const oddA = Color(0xFFFFA83D);
  static const oddB = Color(0xFFFF3E70);
  static const evenA = Color(0xFF45DBFF);
  static const evenB = Color(0xFF4458FF);

  static const textPrimary = Color(0xFFF2F2F7);
  static const textMuted = Color(0xFF8C8CA6);
  static const textDim = Color(0xFF5A5A78);
  static const danger = Color(0xFFFF4E5E);
  static const gold = Color(0xFFFFD24E);

  static LinearGradient gradientFor(bool isOdd) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isOdd ? const [oddA, oddB] : const [evenA, evenB],
  );

  static Color glowFor(bool isOdd) => isOdd ? oddB : evenA;
  static Color baseFor(bool isOdd) => isOdd ? oddA : evenA;

  /// タイル上面のツヤ。白を薄く重ねるだけで、平面がふくらんで見える。
  static const gloss = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59FFFFFF), Color(0x0DFFFFFF), Color(0x1A000000)],
    stops: [0, 0.45, 1],
  );
}

/// 数字とスコアの書体。丸くて太く、桁が揃うのでゲームの表示に向く。
/// 日本語は含まれないので、本文は既定フォントのままにしてある。
class AppFont {
  static const display = 'Baloo2';

  /// 見出しやスコアなど、大きく出す数字。
  static TextStyle number(double size, {Color color = Palette.textPrimary}) =>
      TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: 1.0,
        color: color,
        // 太い字は暗い背景に溶けるので、必ず影で縁を作る。
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
      );

  /// SCORE / BEST のような小さい見出しラベル。
  static TextStyle label(double size, {Color color = Palette.textDim}) =>
      TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 1.0,
        letterSpacing: 2.2,
        color: color,
      );
}

/// 1段浮かせたパネルの装飾。ヘッダーやフッターで使い回す。
BoxDecoration panelDecoration({
  Color color = Palette.panel,
  Color border = Palette.panelBorder,
  double radius = 18,
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: border),
  boxShadow: const [
    BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
  ],
);

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
