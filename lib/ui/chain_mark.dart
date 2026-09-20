import 'package:flutter/material.dart';

import '../game/phase.dart';
import 'theme.dart';

/// 題の上で編まれる鎖。赤→青→紫→赤→青 と順に灯り、線で繋がっていく。
///
/// 盤面の決まりをそのまま小さく見せている。同じ相は続かない並びなので、
/// 「隣り合う2枚は違う色」が絵として読める。
class ChainMark extends StatefulWidget {
  const ChainMark({super.key, this.order = redBlueViolet});

  /// 既定の並び。盤面で実際に編める形（同じ相が続かない）にしてある。
  static const List<Phase> redBlueViolet = [
    Phase.red,
    Phase.blue,
    Phase.violet,
    Phase.red,
    Phase.blue,
  ];

  /// 灯る順。**同じ相を続けて入れないこと。** 盤面で編めない並びを見せると、
  /// 決まりを覚える前に嘘を覚えることになる。
  final List<Phase> order;

  @override
  State<ChainMark> createState() => _ChainMarkState();
}

class _ChainMarkState extends State<ChainMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// 1枚ぶんの大きさ。盤面のマス（実機で 40〜50px）に近づけてある。
  static const double _tile = 34;
  static const double _gap = 16;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      // 1枚ずつ灯って、全部繋がってから一拍置いて消える。
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [i] 枚目がどれだけ灯っているか（0〜1）。
  double _lit(double t, int i) {
    const step = 0.13;
    const hold = 0.30; // 全部灯ったまま止まる長さ
    final start = i * step;
    final end = start + step;
    if (t < start) return 0;
    if (t < end) return (t - start) / step;
    final all = widget.order.length * step;
    if (t < all + hold) return 1;
    // 最後はまとめて引く。1枚ずつ消すと編み直しに見えない。
    return (1 - (t - all - hold) / (1 - all - hold)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.order.length;
    final width = n * _tile + (n - 1) * _gap;
    return SizedBox(
      width: width,
      height: _tile,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LinkPainter(
                    order: widget.order,
                    lit: [for (var i = 0; i < n; i++) _lit(t, i)],
                    tile: _tile,
                    gap: _gap,
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: i * (_tile + _gap),
                  top: 0,
                  width: _tile,
                  height: _tile,
                  child: _MarkTile(
                    phase: widget.order[i],
                    lit: _lit(t, i),
                    size: _tile,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 鎖の1枚。灯っていないときは沈めておく。
class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.phase,
    required this.lit,
    required this.size,
  });

  final Phase phase;
  final double lit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final glow = Palette.glowFor(phase);
    return Opacity(
      // 消えていても形は残す。空の枠が並ぶより、盤面らしく見える。
      opacity: 0.30 + 0.70 * lit,
      child: Transform.scale(
        scale: 0.86 + 0.14 * lit,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: Palette.gradientFor(phase),
            // 盤面のマスと同じ丸み。
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              if (lit > 0)
                BoxShadow(
                  color: glow.withValues(alpha: 0.6 * lit),
                  blurRadius: size * 0.7 * lit,
                  spreadRadius: size * 0.06 * lit,
                ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: Palette.gloss,
              borderRadius: BorderRadius.circular(size * 0.28),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// マスとマスを繋ぐ線。灯った先まで伸びる。
class _LinkPainter extends CustomPainter {
  const _LinkPainter({
    required this.order,
    required this.lit,
    required this.tile,
    required this.gap,
  });

  final List<Phase> order;
  final List<double> lit;
  final double tile;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    for (var i = 0; i < lit.length - 1; i++) {
      // 次の1枚が灯り始めてから繋がる。線が先回りしない。
      final t = lit[i + 1];
      if (t <= 0) continue;
      final from = Offset(i * (tile + gap) + tile, y);
      final to = Offset(from.dx + gap, y);
      final b = Offset.lerp(from, to, t)!;
      final color = Color.lerp(
        Palette.glowFor(_phaseAt(i)),
        Palette.glowFor(_phaseAt(i + 1)),
        0.5,
      )!;
      canvas.drawLine(
        from,
        b,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 7
          ..color = color.withValues(alpha: 0.35 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawLine(
        from,
        b,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.6
          ..color = Colors.white.withValues(alpha: 0.85 * t),
      );
    }
  }

  Phase _phaseAt(int i) => order[i];

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}
