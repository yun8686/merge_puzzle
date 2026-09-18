import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import 'board_view.dart';
import 'theme.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _restart() => _controller.restart();

  void _nextStage() => _controller.nextStage();

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
                          remainingTargets: _controller.remainingTargets,
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
                        _Footer(controller: _controller, onRestart: _restart),
                      ],
                    ),
                    if (_controller.phase == GamePhase.stageCleared)
                      _StageClearOverlay(
                        controller: _controller,
                        onNext: _nextStage,
                      ),
                    if (_controller.phase == GamePhase.failed)
                      _GameOverOverlay(
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

/// ロゴタイプ。奇数=暖色、偶数=寒色というルールの色をそのまま使うので、
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
          'PARITY CHAIN',
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
              label: 'STAGE',
              value: Text(
                '${controller.stage}',
                style: AppFont.number(22, color: Palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 残り手数、残り目標、奇数・偶数の比率。
/// 偶奇バーは「長いチェインがまだ組めるか」の目安。長いチェインは必ず
/// 偶数を消費するので、偶数が細ると大きな数字の目標が狙えなくなる。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.oddCount,
    required this.evenCount,
    required this.movesLeft,
    required this.remainingTargets,
  });

  final int oddCount;
  final int evenCount;
  final int movesLeft;
  final int remainingTargets;

  @override
  Widget build(BuildContext context) {
    final total = oddCount + evenCount;
    final evenRatio = total == 0 ? 0.0 : evenCount / total;
    // チェインは必ず偶数を1枚以上使うので、危ないのは常に偶数側。
    final danger = evenRatio < 0.18;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatPanel(
              label: 'MOVES',
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
              label: 'GOALS',
              accent: Palette.gold,
              value: Text(
                '$remainingTargets',
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
                            'ODD',
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
                            'EVEN',
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

/// 奇数と偶数で1本のバーを分け合う。盤面は常に埋まっているので、
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
              // 下地は奇数。偶数を右から重ねるので、残りが奇数の幅になる。
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
/// 目標ブロックを巻き込んでいるときは、それが消えるまでの残り枚数を優先して出す。
String _pendingLabel(GameController controller) {
  if (controller.missingTiles > 0) {
    return 'あと ${controller.missingTiles} 枚で成立';
  }
  final toTarget = controller.tilesToNextTarget;
  if (toTarget > 0) return 'あと $toTarget 枚で目標が消える';
  if (controller.pathIsValid) return '+${controller.pendingScore}';
  return '何も消えない';
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
                          Text(
                            '${controller.pathLength}',
                            style: AppFont.number(
                              26,
                              color: valid ? Palette.gold : Palette.textMuted,
                            ),
                          ),
                          const Text(
                            ' 枚',
                            style: TextStyle(
                              color: Palette.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (controller.pendingClearedTargets > 0) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.adjust,
                              size: 16,
                              color: Palette.gold,
                            ),
                            Text(
                              ' ×${controller.pendingClearedTargets}',
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
                        '奇数と偶数を交互になぞる',
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

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({required this.controller, required this.onRestart});

  final GameController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: const Color(0xCC07070F),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: DecoratedBox(
                decoration: panelDecoration(radius: 26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GAME OVER',
                        style: AppFont.number(30, color: Palette.danger),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        controller.movesLeft <= 0
                            ? '手数を使い切りました'
                            : '繋げる手がなくなりました',
                        style: const TextStyle(
                          color: Palette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('SCORE', style: AppFont.label(10)),
                      const SizedBox(height: 8),
                      Text('${controller.score}', style: AppFont.number(56)),
                      const SizedBox(height: 18),
                      _ResultRow(
                        label: '到達ステージ',
                        value: '${controller.stage}',
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: '最長チェイン',
                        value: '${controller.bestChain} 枚',
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: '残した目標',
                        value: '${controller.remainingTargets} 個',
                      ),
                      const SizedBox(height: 26),
                      _PrimaryButton(label: 'もう一度', onTap: onRestart),
                    ],
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

/// ステージクリア。目標を全部消したときだけ出る。
class _StageClearOverlay extends StatelessWidget {
  const _StageClearOverlay({required this.controller, required this.onNext});

  final GameController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: const Color(0xCC07070F),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: DecoratedBox(
                decoration: panelDecoration(radius: 26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STAGE ${controller.stage} CLEAR',
                        style: AppFont.number(26, color: Palette.gold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '目標ブロックを全部消しました',
                        style: TextStyle(
                          color: Palette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('SCORE', style: AppFont.label(10)),
                      const SizedBox(height: 8),
                      Text('${controller.score}', style: AppFont.number(52)),
                      const SizedBox(height: 18),
                      _ResultRow(
                        label: '残した手数',
                        value: '${controller.movesLeft} 手',
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: '最長チェイン',
                        value: '${controller.bestChain} 枚',
                      ),
                      const SizedBox(height: 26),
                      _PrimaryButton(
                        label: '次のステージ',
                        onTap: onNext,
                      ),
                    ],
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
