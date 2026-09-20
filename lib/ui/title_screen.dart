import 'package:flutter/material.dart';

import '../game/phase.dart';
import 'theme.dart';

/// 最初に出る画面。
///
/// 遊び方は書かない。**鎖が編まれるところを見せる**ほうが速い。題の上で
/// 熱→冷→雷とマスが順に灯って線で繋がるので、「色を継いで繋げる遊びだ」が
/// 押す前に伝わる。
///
/// 記録は読まない。押されたら拠点（`HomeScreen`）に渡して、そこで読ませる。
/// ここが保存の都合を持つと、タイトルを出すのに読み込みを待つことになる。
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      // **画面いっぱいに広げる。** 既定の loose のままだと、Stack の大きさが
      // 位置を決めていない子――ここでは題とボタンの Column――に合わせて
      // 決まる。Column の幅は一番広い子の幅なので、Stack が画面の中ほどの
      // 細い帯になり、Positioned.fill の地もその幅しか塗らない。
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 盤面の画面と同じ放射グラデ。地下の広間に篝火が一つ、という地。
          const Positioned.fill(
            key: ValueKey('title-backdrop'),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.25),
                  radius: 1.0,
                  colors: [Palette.backgroundGlow, Palette.background],
                  stops: [0, 0.85],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  const _ChainMark(),
                  const SizedBox(height: 34),
                  const _Title(),
                  const SizedBox(height: 18),
                  Text(
                    '相を継いで鎖を編み、守りを破って討ち取る',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12.5,
                      height: 1.7,
                    ),
                  ),
                  const Spacer(flex: 3),
                  _StartButton(onTap: onStart),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 題。日本語なので既定の書体で組み、色だけ相のグラデで塗る。
///
/// 見出しの書体（Baloo2）には日本語が入っていないので、ここでは使えない。
/// 代わりに下のラテン字に回して、二段で「らしさ」を出している。
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            // 熱から冷へ。題そのものが盤面の2色を名乗っている。
            colors: [Palette.oddA, Palette.oddB, Palette.evenA],
            stops: [0, 0.5, 1],
          ).createShader(rect),
          child: const Text(
            '氷炎の鎖',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              height: 1.1,
              shadows: [Shadow(color: Color(0xCC000000), blurRadius: 14)],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('FROSTFIRE CHAIN', style: AppFont.label(11)),
      ],
    );
  }
}

/// 題の上で編まれる鎖。熱→冷→雷→熱→冷 と順に灯り、線で繋がっていく。
///
/// 盤面の決まりをそのまま小さく見せている。同じ相は続かない並びなので、
/// 「隣り合う2枚は違う色」が絵として読める。
class _ChainMark extends StatefulWidget {
  const _ChainMark();

  /// 灯る順。盤面で実際に編める並びにしてある。
  static const List<Phase> order = [
    Phase.heat,
    Phase.cold,
    Phase.bolt,
    Phase.heat,
    Phase.cold,
  ];

  @override
  State<_ChainMark> createState() => _ChainMarkState();
}

class _ChainMarkState extends State<_ChainMark>
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
    final all = _ChainMark.order.length * step;
    if (t < all + hold) return 1;
    // 最後はまとめて引く。1枚ずつ消すと編み直しに見えない。
    return (1 - (t - all - hold) / (1 - all - hold)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final n = _ChainMark.order.length;
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
                    phase: _ChainMark.order[i],
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
    required this.lit,
    required this.tile,
    required this.gap,
  });

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

  Phase _phaseAt(int i) => _ChainMark.order[i];

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}

/// 押して始める。脈打たせて、ここが押せることを言葉なしに示す。
class _StartButton extends StatefulWidget {
  const _StartButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Palette.evenB.withValues(alpha: 0.35 + 0.35 * t),
                blurRadius: 22 + 16 * t,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Palette.evenA, Palette.evenB],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 56,
                vertical: 17,
              ),
              child: Text(
                'はじめる',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white,
                  shadows: AppFont.number(17).shadows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
