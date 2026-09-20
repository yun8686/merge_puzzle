import 'package:flutter/material.dart';

import 'chain_mark.dart';
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
                  const ChainMark(),
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
