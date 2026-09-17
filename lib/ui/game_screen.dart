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
  int _best = 0;

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

  void _restart() {
    setState(() {
      _best = _best > _controller.score ? _best : _controller.score;
      _controller.dispose();
      _controller = GameController()..best = _best;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final board = _controller.board;
            final evenRatio = board.evenCount / board.tileCount;
            return Stack(
              children: [
                Column(
                  children: [
                    _Header(controller: _controller, best: _best),
                    _StatusBar(
                      ratio: evenRatio,
                      count: board.evenCount,
                      requiredTotal: board.requiredTotal,
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
                if (_controller.phase == GamePhase.gameOver)
                  _GameOverOverlay(
                    controller: _controller,
                    onRestart: _restart,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.best});

  final GameController controller;
  final int best;

  @override
  Widget build(BuildContext context) {
    final displayBest = best > controller.score ? best : controller.score;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCORE',
                  style: TextStyle(
                    color: Palette.textMuted,
                    fontSize: 11,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: controller.score.toDouble()),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    value.round().toString(),
                    style: const TextStyle(
                      color: Palette.textPrimary,
                      fontSize: 38,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'BEST',
                style: TextStyle(
                  color: Palette.textMuted,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$displayBest',
                style: const TextStyle(
                  color: Palette.textMuted,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 偶数の残量メーター。これが尽きると詰むので、盤面の寿命そのもの。
/// 偶数の残量と、いま必要な合計値。どちらも「あと何手遊べるか」の目安。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.ratio,
    required this.count,
    required this.requiredTotal,
  });

  final double ratio;
  final int count;
  final int requiredTotal;

  @override
  Widget build(BuildContext context) {
    final danger = ratio < 0.18;
    final color = danger ? Palette.danger : Palette.evenA;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Text(
            '偶数 $count',
            style: TextStyle(
              color: danger ? Palette.danger : Palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 350),
                builder: (context, value, _) => Stack(
                  children: [
                    Container(height: 6, color: Palette.surface),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '必要合計 $requiredTotal',
            style: const TextStyle(
              color: Palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 成立まで何が足りないかを一言で。枚数が先、足りたら合計値を出す。
String _pendingLabel(GameController controller) {
  if (controller.pathIsValid) return '+${controller.pendingScore}';
  if (controller.missingTiles > 0) return 'あと ${controller.missingTiles} 枚';
  return 'あと ${controller.missingTotal}';
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.onRestart});

  final GameController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tracing = controller.isTracing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: tracing
                  ? Row(
                      key: const ValueKey('tracing'),
                      children: [
                        Text(
                          '${controller.path.length} 枚 · '
                          '${controller.pathTotal}/${controller.requiredTotal}',
                          style: TextStyle(
                            color: controller.pathIsValid
                                ? Palette.textPrimary
                                : Palette.textMuted,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _pendingLabel(controller),
                          style: TextStyle(
                            color: controller.pathIsValid
                                ? const Color(0xFFFFE14E)
                                : Palette.textMuted,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      '奇数 → 偶数 → 奇数 … と交互になぞる',
                      key: ValueKey('hint'),
                      style: TextStyle(
                        color: Palette.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          _IconAction(
            icon: Icons.lightbulb_outline,
            onTap: () {
              controller.showHint();
              Future<void>.delayed(
                const Duration(milliseconds: 1600),
                controller.clearHint,
              );
            },
          ),
          const SizedBox(width: 8),
          _IconAction(icon: Icons.refresh, onTap: onRestart),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Palette.textMuted, size: 22),
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
      child: ColoredBox(
        color: const Color(0xE60E0E16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '繋げる手がなくなりました',
                style: TextStyle(
                  color: Palette.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${controller.score}',
                style: const TextStyle(
                  color: Palette.textPrimary,
                  fontSize: 64,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '最長チェイン ${controller.bestChain} 枚',
                style: const TextStyle(
                  color: Palette.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.evenB,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 44,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'もう一度',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
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
