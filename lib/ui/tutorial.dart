import 'package:flutter/material.dart';

import '../game/party.dart';
import '../game/phase.dart';
import 'chain_mark.dart';
import 'foe_art.dart';
import 'mage_art.dart';
import 'theme.dart';

/// 初回だけ出る遊び方。拠点の上に覆いかぶせて、通し終えたら記録に印を付ける。
///
/// **文で説明しない。絵で見せて、文は一言添えるだけ。** 決まりを字で並べても
/// 読まれないし、読んでも盤面の前で思い出せない。盤面と同じ色・同じ形・同じ
/// 演出で見せておけば、初めて潜ったときに「さっきの絵だ」で繋がる。
///
/// 記録は読み書きしない。通し終えたことを [onDone] で知らせるだけで、印を
/// 付けて保存するのは拠点の仕事。
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final PageController _pages = PageController();
  int _at = 0;

  static const List<_Page> _slides = [
    _Page(
      title: '鎖を編む',
      body: '隣り合うマスを指でなぞって継ぐ。\n'
          '**隣り合う2枚は違う相**でなければ繋がらない。\n'
          '3枚つながれば鎖になる。',
      art: _ChainArt(),
    ),
    _Page(
      title: '長いほど強い',
      body: '継いだ枚数が、そのまま鎖の**威力**になる。\n'
          '遠回りしてでも長く編むほど強い。',
      art: _PowerArt(),
    ),
    _Page(
      title: '守りを破る',
      body: 'マスに書かれた数字は敵の**守り**。\n'
          '威力が守りに届けば1、上回るごとに1ずつ傷がつく。\n'
          '体力を削り切れば討ち取れる。',
      art: _WardArt(),
    ),
    _Page(
      title: '敵は毎ターン殴ってくる',
      body: '1手ごとに、生きている敵のぶんだけ体力が減る。\n'
          '**早く討つほど、後が楽になる。**',
      art: _StrikeArt(),
    ),
    _Page(
      title: '編成が盤面を決める',
      body: '連れていった魔導士の**相**だけが盤面に出る。\n'
          '相は2種類以上でなければ、鎖が1枚も編めない。',
      art: _PartyArt(),
    ),
  ];

  bool get _isLast => _at == _slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // 拠点を透かすと、どちらを読めばよいのか分からなくなる。完全に覆う。
      color: Palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 12, 0),
                  child: Row(
                    children: [
                      Text('あそびかた', style: AppFont.label(10)),
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onDone,
                        child: Text(
                          'とばす',
                          style: AppFont.label(10, color: Palette.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _at = i),
                    itemBuilder: (context, i) => _slides[i],
                  ),
                ),
                _Dots(count: _slides.length, at: _at),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
                  child: _NextButton(
                    label: _isLast ? 'はじめる' : 'つぎへ',
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 1枚ぶん。上に絵、下に一言。
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.art});

  final String title;
  final String body;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 絵の高さを揃える。枚をめくったときに文が上下に跳ねない。
          SizedBox(height: 150, child: Center(child: art)),
          const SizedBox(height: 30),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _Body(body),
        ],
      ),
    );
  }
}

/// 一言。`**` で挟んだところだけ明るくする。
///
/// 覚えてほしいのは各枚に1つだけ。そこだけ色を変えておけば、読み飛ばしても
/// 目が止まる。
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      color: Palette.textMuted,
      fontSize: 13,
      height: 1.85,
    );
    final parts = text.split('**');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isEven
                  ? base
                  : base.copyWith(
                      color: Palette.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}

/// いま何枚目か。
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at});

  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == at ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == at ? Palette.evenA : Palette.panelBorder,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Palette.evenA, Palette.evenB]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Palette.evenB.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white,
                  shadows: AppFont.number(16).shadows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- 絵 ---------------------------------------------------------------
//
// どれも盤面と同じ色・同じ形で描く。初めて潜ったときに「さっきの絵だ」で
// 繋がるようにするため、ここだけの飾りは作らない。

/// 鎖が編まれるところ。タイトルと同じものを使う。
class _ChainArt extends StatelessWidget {
  const _ChainArt();

  @override
  Widget build(BuildContext context) => const ChainMark();
}

/// 短い鎖と長い鎖。枚数がそのまま威力になることを、並べて見せる。
class _PowerArt extends StatelessWidget {
  const _PowerArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Row(phases: [Phase.heat, Phase.cold, Phase.heat], power: 3),
        const SizedBox(height: 18),
        const _Row(
          phases: [
            Phase.heat,
            Phase.cold,
            Phase.heat,
            Phase.cold,
            Phase.heat,
            Phase.cold,
          ],
          power: 6,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.phases, required this.power});

  final List<Phase> phases;
  final int power;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final phase in phases)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: PhaseSwatch(phase: phase, size: 22),
          ),
        const SizedBox(width: 10),
        Text('威力', style: AppFont.label(9)),
        const SizedBox(width: 6),
        Text('$power', style: AppFont.number(20, color: Palette.gold)),
      ],
    );
  }
}

/// 守りの数字と、通るダメージ。敵はマスに出るのと同じ姿・同じ封印の色で。
class _WardArt extends StatelessWidget {
  const _WardArt();

  static const int _ward = 5;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.boardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Palette.wardColorFor(_ward).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FoePortrait(ward: _ward, size: 44),
                const SizedBox(height: 4),
                Text(
                  '$_ward',
                  style: AppFont.number(
                    16,
                    color: Palette.wardColorFor(_ward),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (power, damage) in const [(5, 1), (6, 2), (8, 4)]) ...[
              Text('威力$power', style: AppFont.label(9)),
              const SizedBox(width: 5),
              Text(
                '→ $damage',
                style: AppFont.number(13, color: Palette.gold),
              ),
              const SizedBox(width: 14),
            ],
          ],
        ),
      ],
    );
  }
}

/// 敵からこちらへ向かう一撃。盤面で出るのと同じ向き・同じ赤で。
class _StrikeArt extends StatelessWidget {
  const _StrikeArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FoePortrait(ward: 4, size: 38),
            SizedBox(width: 20),
            FoePortrait(ward: 7, size: 38),
          ],
        ),
        const SizedBox(height: 6),
        const Icon(Icons.keyboard_double_arrow_down,
            color: Palette.danger, size: 26),
        const SizedBox(height: 6),
        SizedBox(
          width: 150,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  value: 0.62,
                  minHeight: 8,
                  backgroundColor: Palette.boardBg,
                  valueColor: AlwaysStoppedAnimation(Palette.life),
                ),
              ),
              const SizedBox(height: 7),
              Text('一党の体力', style: AppFont.label(9)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 連れていく顔ぶれと、そこから決まる盤面の色。
class _PartyArt extends StatelessWidget {
  const _PartyArt();

  static const _party = [MageKind.ember, MageKind.rime, MageKind.storm];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in _party)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MagePortrait(kind: kind, size: 38),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Icon(Icons.arrow_downward, color: Palette.textDim, size: 20),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in _party)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: PhaseSwatch(phase: Mage.of(kind).phase, size: 26),
              ),
          ],
        ),
      ],
    );
  }
}
