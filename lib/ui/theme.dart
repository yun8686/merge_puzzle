import 'package:flutter/material.dart';

import '../game/party.dart';
import '../game/phase.dart';

/// 熱の相=暖色、冷の相=寒色。この2色がゲームの中心情報なので、
/// 背景は暗く沈めてマナとエフェクトを目立たせる。
///
/// 相は [Phase] で持つ。盤面に出る相は編成から決まるので、ここは3色ぶん
/// 用意しておいて、使うかどうかは一党の側に任せる。
class Palette {
  static const background = Color(0xFF07070F);

  /// 盤面の後ろに敷く放射グラデの色。真っ黒だと平坦に見えるので、
  /// 中央だけわずかに持ち上げて奥行きを出す。
  /// 青紫に寄せて、地下の広間に篝火が一つ灯っているように見せる。
  static const backgroundGlow = Color(0xFF1E1438);

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

  /// 雷の相。3つ目として足した色。
  ///
  /// 金や白金も試したが、暖色と混ざって濁り、盤面で見分けられなかった。
  /// 緑は冷の水色と隣り合うと紛れる。藤から濃紫なら、暖色とも寒色とも
  /// 離れていて、明るさもマナのマスとして足りる。
  static const boltA = Color(0xFFC9A6FF);
  static const boltB = Color(0xFF6D28D9);

  static const textPrimary = Color(0xFFF2F2F7);
  static const textMuted = Color(0xFF8C8CA6);
  static const textDim = Color(0xFF5A5A78);
  static const danger = Color(0xFFFF4E5E);
  static const gold = Color(0xFFFFD24E);

  /// 一党の体力。減るのは階層を落としたときだけなので、盤面の2色と
  /// ぶつからない緑に置いて「盤面の外の資源」だと分かるようにする。
  static const life = Color(0xFF6BE8A0);

  /// 魔導士の色。**持っている相の色をそのまま使う。**
  /// 誰を入れると盤面が何色になるかが、編成の画面で色だけで読める。
  static Color mageColor(MageKind kind) => baseFor(Mage.of(kind).phase);

  /// 敵を包む守りの色。金の封印として読ませる。
  static const ward = gold;

  /// 守りの厚さに応じた封印の色。守りの数字＝破るのに要る威力なので、
  /// そのまま格付けになっている。数字を読む前に「硬そうか」が色で分かる。
  static Color wardColorFor(int ward) {
    if (ward >= 8) return const Color(0xFFFFE14E);
    if (ward >= 7) return const Color(0xFFFFB03D);
    if (ward >= 6) return const Color(0xFFFF9A6B);
    if (ward >= 5) return const Color(0xFFBFA8FF);
    if (ward >= 4) return const Color(0xFF8CC4FF);
    return const Color(0xFF8CFFB0);
  }

  /// 相ごとの2色。マナのマスはこのグラデで塗る。
  static (Color, Color) pairFor(Phase phase) => switch (phase) {
    Phase.heat => (oddA, oddB),
    Phase.cold => (evenA, evenB),
    Phase.bolt => (boltA, boltB),
  };

  static LinearGradient gradientFor(Phase phase) {
    final (a, b) = pairFor(phase);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [a, b],
    );
  }

  /// 光らせるときの色。濃い側を使う相と薄い側を使う相があるのは、
  /// 暗い背景の上で同じくらいの明るさに見えるようにするため。
  static Color glowFor(Phase phase) => switch (phase) {
    Phase.heat => oddB,
    Phase.cold => evenA,
    Phase.bolt => boltA,
  };

  static Color baseFor(Phase phase) => pairFor(phase).$1;

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

/// 鎖の威力に応じた呪文の位階。継ぎ目が多いほど衝撃が積み上がるので、
/// 強いほど上位の名で呼ばれる。
class ChainRank {
  const ChainRank(this.label, this.color);

  final String label;
  final Color color;

  static ChainRank? of(int power) {
    if (power >= 12) return const ChainRank('RAGNAROK!!!', Color(0xFFFFE14E));
    if (power >= 10) return const ChainRank('CATACLYSM!!', Color(0xFFFFB03D));
    if (power >= 8) return const ChainRank('SHATTER!!', Color(0xFFFF7A4E));
    if (power >= 6) return const ChainRank('FRACTURE!', Color(0xFF6BE8FF));
    if (power >= 5) return const ChainRank('SPARK', Color(0xFF8CFFB0));
    return null;
  }
}
