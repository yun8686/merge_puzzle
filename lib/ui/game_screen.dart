import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/party.dart';
import 'board_view.dart';
import 'foe_art.dart';
import 'theme.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.controller});

  /// 差し込むと、画面が自前で作る代わりにこれを使う。
  /// 決着画面のように、特定の局面から始めたいテスト用。
  final GameController? controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController _controller;

  /// 差し込まれたものは差し込んだ側が畳む。
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? GameController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _restart() => _controller.restart();

  void _nextStage(Blessing blessing) => _controller.nextStage(blessing);

  void _retryFloor() => _controller.retryFloor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          // 盤面の後ろだけ明るくして、視線を中央に集める。
          const Positioned.fill(
            key: ValueKey('backdrop'),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 1.0,
                  colors: [Palette.backgroundGlow, Palette.background],
                  stops: [0, 0.85],
                ),
              ),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final board = _controller.board;
                return Stack(
                  children: [
                    Column(
                      children: [
                        const _TitleBar(),
                        _Header(controller: _controller),
                        _StatusBar(
                          oddCount: board.oddCount,
                          evenCount: board.evenCount,
                          movesLeft: _controller.movesLeft,
                          remainingFoes: _controller.remainingFoes,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: BoardView(controller: _controller),
                          ),
                        ),
                        _PartyBar(
                          party: _controller.party,
                          healed: _controller.lastHealed,
                        ),
                        _Footer(controller: _controller, onRestart: _restart),
                      ],
                    ),
                    if (_controller.phase == GamePhase.stageCleared)
                      _StageClearOverlay(
                        controller: _controller,
                        onChoose: _nextStage,
                      ),
                    if (_controller.phase == GamePhase.floorLost)
                      _FloorLostOverlay(
                        controller: _controller,
                        onRetry: _retryFloor,
                      ),
                    if (_controller.phase == GamePhase.defeated)
                      _DefeatOverlay(
                        controller: _controller,
                        onRestart: _restart,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ロゴタイプ。熱の相=暖色、冷の相=寒色というルールの色をそのまま使うので、
/// 見出しがそのまま配色の説明になっている。
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Palette.oddA, Palette.oddB, Palette.evenB, Palette.evenA],
        ).createShader(rect),
        child: Text(
          'FROSTFIRE CHAIN',
          style: AppFont.number(
            19,
            color: Colors.white,
          ).copyWith(letterSpacing: 5),
        ),
      ),
    );
  }
}

/// パネル1枚。ラベルを上、数字を下に置くだけの共通の器。
class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.label, required this.value, this.accent});

  final String label;
  final Widget value;

  /// 指定すると枠と背景がその色に寄る。目立たせたいパネル用。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    return DecoratedBox(
      decoration: panelDecoration(
        color: accent == null
            ? Palette.panel
            : Color.alphaBlend(accent.withValues(alpha: 0.10), Palette.panel),
        border: accent == null
            ? Palette.panelBorder
            : accent.withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppFont.label(10, color: accent ?? Palette.textDim),
            ),
            const SizedBox(height: 6),
            value,
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      // 高さは中身任せなので、隣り合うパネルを揃えるには実測が要る。
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StatPanel(
                label: 'SCORE',
                value: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: controller.score.toDouble()),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) =>
                      Text(value.round().toString(), style: AppFont.number(42)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StatPanel(
              label: 'DEPTH',
              value: Text(
                'B${controller.stage}F',
                style: AppFont.number(22, color: Palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 残りターン、残りの敵、熱と冷の比率。
/// 相のバーは「強い鎖をまだ編めるか」の目安。長い鎖は必ず冷の相を消費するので、
/// 冷が細ると厚い守りを破れなくなる。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.oddCount,
    required this.evenCount,
    required this.movesLeft,
    required this.remainingFoes,
  });

  final int oddCount;
  final int evenCount;
  final int movesLeft;
  final int remainingFoes;

  @override
  Widget build(BuildContext context) {
    final total = oddCount + evenCount;
    final evenRatio = total == 0 ? 0.0 : evenCount / total;
    // 鎖は必ず冷の相を1枚以上使うので、危ないのは常に冷の側。
    final danger = evenRatio < 0.18;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatPanel(
              label: 'TURNS',
              accent: movesLeft <= 2 ? Palette.danger : null,
              value: Text(
                '$movesLeft',
                style: AppFont.number(
                  24,
                  color: movesLeft <= 2 ? Palette.danger : Palette.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StatPanel(
              label: 'FOES',
              accent: Palette.gold,
              value: Text(
                '$remainingFoes',
                style: AppFont.number(24, color: Palette.gold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: panelDecoration(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'HEAT',
                            style: AppFont.label(10, color: Palette.oddA),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$oddCount',
                            style: AppFont.number(13, color: Palette.oddA),
                          ),
                          const Spacer(),
                          Text(
                            '$evenCount',
                            style: AppFont.number(
                              13,
                              color: danger ? Palette.danger : Palette.evenA,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'FROST',
                            style: AppFont.label(
                              10,
                              color: danger ? Palette.danger : Palette.evenA,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ParityBar(evenRatio: evenRatio, danger: danger),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 熱と冷で1本のバーを分け合う。盤面は常に埋まっているので、
/// 片方が伸びれば必ずもう片方が縮む。どちらに傾いているかが一目で分かる。
class _ParityBar extends StatelessWidget {
  const _ParityBar({required this.evenRatio, required this.danger});

  final double evenRatio;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: evenRatio.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, even, _) => Stack(
            children: [
              // 下地は熱の相。冷を右から重ねるので、残りが熱の幅になる。
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Palette.oddA, Palette.oddB],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: even,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: danger
                            ? const [Palette.danger, Color(0xFFFF8A4E)]
                            : const [Palette.evenB, Palette.evenA],
                      ),
                    ),
                  ),
                ),
              ),
              // 境目を暗く落として、2色の切り替わりを立たせる。
              Align(
                alignment: Alignment(1 - even * 2, 0),
                child: const SizedBox(
                  width: 2,
                  child: ColoredBox(color: Color(0xCC07070F)),
                ),
              ),
              // 五分五分の位置。どちらに傾いているかの基準線。
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 1,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// いま指を離すとどうなるかを一言で。
/// 敵を巻き込んでいるときは、討ち取るまでの残りを優先して出す。
String _pendingLabel(GameController controller) {
  if (controller.missingTiles > 0) {
    return 'あと ${controller.missingTiles} 継げば鎖になる';
  }
  final toFoe = controller.tilesToNextFoe;
  if (toFoe > 0) {
    return controller.pathIsValid
        ? 'あと $toFoe 継げば討ち取れる'
        : 'あと $toFoe 継げば届く';
  }
  if (controller.pathIsValid) return '+${controller.pendingScore}';
  return '守りに弾かれる';
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.onRestart});

  final GameController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tracing = controller.isTracing;
    final valid = controller.pathIsValid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: panelDecoration(
                color: valid
                    ? Color.alphaBlend(
                        Palette.gold.withValues(alpha: 0.14),
                        Palette.panel,
                      )
                    : Palette.panel,
                border: valid
                    ? Palette.gold.withValues(alpha: 0.5)
                    : Palette.panelBorder,
                radius: 16,
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: tracing
                    ? Row(
                        key: const ValueKey('tracing'),
                        children: [
                          Text('威力', style: AppFont.label(10)),
                          const SizedBox(width: 6),
                          Text(
                            '${controller.power}',
                            style: AppFont.number(
                              26,
                              color: valid ? Palette.gold : Palette.textMuted,
                            ),
                          ),
                          // 魔導士が乗せた分は、枚数と区別できるように別に出す。
                          if (controller.powerBonus > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '+${controller.powerBonus}',
                                style: AppFont.number(
                                  14,
                                  color: Palette.mageColor(MageKind.ember),
                                ),
                              ),
                            ),
                          if (controller.pendingFelled > 0) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.shield,
                              size: 16,
                              color: Palette.gold,
                            ),
                            Text(
                              ' ×${controller.pendingFelled}',
                              style: AppFont.number(16, color: Palette.gold),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _pendingLabel(controller),
                            style: valid
                                ? AppFont.number(20, color: Palette.gold)
                                : const TextStyle(
                                    color: Palette.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                          ),
                        ],
                      )
                    : const Text(
                        '熱と冷を交互に継いで鎖を編む',
                        key: ValueKey('hint'),
                        style: TextStyle(
                          color: Palette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _IconAction(
            icon: Icons.lightbulb,
            tint: Palette.gold,
            onTap: () {
              controller.showHint();
              Future<void>.delayed(
                const Duration(milliseconds: 1600),
                controller.clearHint,
              );
            },
          ),
          const SizedBox(width: 8),
          _IconAction(
            icon: Icons.refresh,
            tint: Palette.evenA,
            onTap: onRestart,
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.tint,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: Color.alphaBlend(tint.withValues(alpha: 0.12), Palette.panel),
          border: tint.withValues(alpha: 0.4),
          radius: 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Icon(icon, color: tint, size: 22),
          ),
        ),
      ),
    );
  }
}

/// 決着画面の共通の器。暗幕と、その中央のパネル。
/// 中身が縦に伸びても画面から溢れないように、常にスクロールできるようにしてある。
class _Curtain extends StatelessWidget {
  const _Curtain({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: const Color(0xCC07070F),
          // 中身が短いときは中央に置き、伸びたときだけスクロールさせる。
          // 素の SingleChildScrollView では高さが無制限になり、Center が
          // 縮んで上に張り付いてしまう。
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    child: Center(
                      child: DecoratedBox(
                        decoration: panelDecoration(radius: 26),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: children,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 階層を落とした。ターン切れか手詰まり。
/// 討ち漏らした敵の反撃を受けるが、一党が立っている限り編み直せる。
class _FloorLostOverlay extends StatelessWidget {
  const _FloorLostOverlay({required this.controller, required this.onRetry});

  final GameController controller;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Curtain(
      children: [
        Text(
          'B${controller.stage}F を落とした',
          style: AppFont.number(26, color: Palette.danger),
        ),
        const SizedBox(height: 6),
        Text(
          controller.movesLeft <= 0 ? 'ターンを使い切った' : '継げる相がなくなった',
          style: const TextStyle(
            color: Palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _FoeLineup(wards: controller.board.foeWards),
        const SizedBox(height: 18),
        Text('討ち漏らした敵の反撃', style: AppFont.label(10)),
        const SizedBox(height: 8),
        Text(
          '-${controller.lastBacklash}',
          style: AppFont.number(48, color: Palette.danger),
        ),
        const SizedBox(height: 18),
        _ResultRow(
          label: '残り体力',
          value: '${controller.party.hp} / ${controller.party.maxHp}',
        ),
        const SizedBox(height: 8),
        _ResultRow(
          label: '討ち漏らし',
          value: '${controller.remainingFoes} 体',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: 'この階層を編み直す', onTap: onRetry),
      ],
    );
  }
}

/// 一党が倒れた。ここだけが本当の終わり。
class _DefeatOverlay extends StatelessWidget {
  const _DefeatOverlay({required this.controller, required this.onRestart});

  final GameController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return _Curtain(
      children: [
        Text('一党は倒れた', style: AppFont.number(30, color: Palette.danger)),
        const SizedBox(height: 6),
        Text(
          'B${controller.stage}F の反撃で体力が尽きた',
          style: const TextStyle(
            color: Palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _FoeLineup(wards: controller.board.foeWards),
        const SizedBox(height: 20),
        Text('SCORE', style: AppFont.label(10)),
        const SizedBox(height: 8),
        Text('${controller.score}', style: AppFont.number(56)),
        const SizedBox(height: 18),
        _ResultRow(label: '到達', value: 'B${controller.stage}F'),
        const SizedBox(height: 8),
        _ResultRow(label: '最大威力', value: '${controller.bestChain}'),
        const SizedBox(height: 8),
        _ResultRow(
          label: '討ち漏らし',
          value: '${controller.remainingFoes} 体',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: 'やり直す', onTap: onRestart),
      ],
    );
  }
}

/// 階層の制圧。その階の敵を全部討ったときだけ出る。
/// ここで祝福を1つ選ぶ。階層をまたいで残るものが増えるのはこの瞬間だけ。
class _StageClearOverlay extends StatelessWidget {
  const _StageClearOverlay({required this.controller, required this.onChoose});

  final GameController controller;
  final void Function(Blessing) onChoose;

  @override
  Widget build(BuildContext context) {
    return _Curtain(
      children: [
        Text(
          'B${controller.stage}F 制圧',
          style: AppFont.number(26, color: Palette.gold),
        ),
        const SizedBox(height: 6),
        const Text(
          'この階層の敵を討ち果たした',
          style: TextStyle(
            color: Palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        _FoeLineup(wards: controller.felledWards, felled: true),
        const SizedBox(height: 18),
        Text('SCORE', style: AppFont.label(10)),
        const SizedBox(height: 8),
        Text('${controller.score}', style: AppFont.number(44)),
        const SizedBox(height: 14),
        _ResultRow(label: '残ったターン', value: '${controller.movesLeft}'),
        const SizedBox(height: 8),
        _ResultRow(label: '最大威力', value: '${controller.bestChain}'),
        const SizedBox(height: 22),
        Text('祝福を1つ選ぶ', style: AppFont.label(10, color: Palette.life)),
        const SizedBox(height: 10),
        for (final offer in controller.party.offers())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BlessingCard(
              offer: offer,
              onTap: () => onChoose(offer.blessing),
            ),
          ),
      ],
    );
  }
}

/// 祝福の1択。押した瞬間に次の階層が始まる。
class _BlessingCard extends StatelessWidget {
  const _BlessingCard({required this.offer, required this.onTap});

  final BlessingOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = switch (offer.blessing) {
      Blessing.heal => Palette.life,
      Blessing.vigor => Palette.gold,
      Blessing.companion => Palette.evenA,
    };
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: Color.alphaBlend(
            tint.withValues(alpha: 0.12),
            Palette.surface,
          ),
          border: tint.withValues(alpha: 0.5),
          radius: 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(offer.title, style: AppFont.number(18, color: tint)),
                  const SizedBox(height: 6),
                  Text(
                    offer.detail,
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 決着画面に敵の姿を並べる。
///
/// 盤面のマスは実機で 40〜50px しかなく、守りの数字と体力の粒で埋まっている。
/// 姿はここでだけ見せる。色は守りの厚さから決まるので、盤面で見ていた封印の
/// 色とそのまま繋がる。
class _FoeLineup extends StatelessWidget {
  const _FoeLineup({required this.wards, this.felled = false});

  final List<int> wards;

  /// 討ち取った側の並びか。沈めて「もう居ない」ことを見せる。
  final bool felled;

  @override
  Widget build(BuildContext context) {
    if (wards.isEmpty) return const SizedBox.shrink();
    // 同じ敵が何体も居ることがあるので、守りごとに数える。
    final counts = <int, int>{};
    for (final w in wards) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    final order = counts.keys.toList()..sort();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          felled ? '討ち果たした' : '討ち漏らした',
          style: AppFont.label(10, color: Palette.textDim),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 268),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final ward in order)
                FoeChip(ward: ward, count: counts[ward]!, felled: felled),
            ],
          ),
        ),
      ],
    );
  }
}

/// 決着画面に並ぶ敵1種ぶんの札。盤面の敵マスにも同じ姿が出るので、
/// テストがどちらの姿を数えているか区別できるよう公開してある。
class FoeChip extends StatelessWidget {
  const FoeChip({
    super.key,
    required this.ward,
    required this.count,
    required this.felled,
  });

  final int ward;
  final int count;
  final bool felled;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.wardColorFor(ward);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            FoePortrait(ward: ward, size: 52, faded: felled),
            // 同じ敵が複数居るときだけ体数を出す。1体のときは数字が邪魔。
            if (count > 1)
              Positioned(
                right: -4,
                top: -2,
                child: Text(
                  '×$count',
                  style: AppFont.number(13, color: Palette.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          foeNameFor(ward),
          style: TextStyle(
            color: felled ? Palette.textDim : Palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text('$ward', style: AppFont.number(13, color: tint)),
      ],
    );
  }
}

/// 一党。階層をまたいで残る唯一の資源なので、盤面の外に常に出しておく。
/// 体力が減るのは階層を落としたときだけなので、普段は動かない目盛りになる。
class _PartyBar extends StatelessWidget {
  const _PartyBar({required this.party, required this.healed});

  final Party party;

  /// 直近の鎖で戻した体力。0 なら何も出さない。
  final int healed;

  @override
  Widget build(BuildContext context) {
    final ratio = party.maxHp == 0 ? 0.0 : party.hp / party.maxHp;
    final low = ratio < 0.3;
    final tint = low ? Palette.danger : Palette.life;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: DecoratedBox(
        decoration: panelDecoration(radius: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('PARTY', style: AppFont.label(10, color: tint)),
                        if (healed > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '+$healed',
                              style: AppFont.number(
                                12,
                                color: Palette.mageColor(MageKind.rime),
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '${party.hp}',
                          style: AppFont.number(14, color: tint),
                        ),
                        Text(
                          ' / ${party.maxHp}',
                          style: AppFont.label(10, color: Palette.textDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    _LifeBar(ratio: ratio.clamp(0.0, 1.0), tint: tint),
                  ],
                ),
              ),
              for (final mage in party.members)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _MageChip(mage: mage),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一党の体力。盤面の2色とぶつからない緑で、別の資源だと分かるようにする。
class _LifeBar extends StatelessWidget {
  const _LifeBar({required this.ratio, required this.tint});

  final double ratio;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFF241B33)),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tint.withValues(alpha: 0.7), tint],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一党に並ぶ魔導士。色はその魔導士が見ている相。
class _MageChip extends StatelessWidget {
  const _MageChip({required this.mage});

  final Mage mage;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.mageColor(mage.kind);
    return Tooltip(
      message: '${mage.name}／${mage.effect}',
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(tint.withValues(alpha: 0.18), Palette.panel),
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: 0.6)),
        ),
        child: Text(
          mage.sigil,
          style: TextStyle(
            color: tint,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Palette.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: AppFont.number(16, color: Palette.textMuted)),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

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
            color: Palette.evenB.withValues(alpha: 0.5),
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
            padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 15),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: AppFont.number(16).shadows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
