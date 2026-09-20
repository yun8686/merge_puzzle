import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/phase.dart';
import 'board_view.dart';
import 'foe_art.dart';
import 'mage_art.dart';
import 'theme.dart';

/// ダンジョン1回ぶんの結末。拠点に持ち帰って記録に書く。
class DungeonOutcome {
  const DungeonOutcome({
    required this.dungeonId,
    required this.cleared,
    required this.floor,
  });

  final String dungeonId;

  /// 踏破したか。false なら全滅。
  final bool cleared;

  /// 全滅したときに到達していた階層。踏破なら最下層。
  final int floor;
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.controller, this.onFinished});

  /// 差し込むと、画面が自前で作る代わりにこれを使う。
  /// 決着画面のように、特定の局面から始めたいテスト用。
  final GameController? controller;

  /// 踏破・全滅したときに呼ぶ。魔晶を足して保存するのは拠点の仕事で、
  /// この画面は「終わった」と伝えるだけ。渡されていなければ、この画面の中で
  /// 次のダンジョンへ進む／やり直す（拠点を持たない古い呼び出し方）。
  final void Function(DungeonOutcome outcome)? onFinished;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController _controller;

  /// 差し込まれたものは差し込んだ側が畳む。
  bool _ownsController = false;

  /// 最後の敵を討ってから、制圧の画面で盤面を覆うまでの間。
  /// 0 だと討った手応えが残らないうちに画面が覆われて、
  /// 自分が何をして勝ったのかが見えないまま次の選択を迫られる。
  static const Duration _clearPause = Duration(milliseconds: 300);

  /// 制圧したが、まだ間を取っている最中か。
  bool _holdingClear = false;
  Timer? _pause;
  late GamePhase _lastPhase;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? GameController();
    // 差し込まれた局面から始まったときは間を取らない。
    // 間を取るのは、目の前で討ち果たしたときだけ。
    _lastPhase = _controller.phase;
    _controller.addListener(_onPhaseChanged);
  }

  @override
  void dispose() {
    _pause?.cancel();
    _controller.removeListener(_onPhaseChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onPhaseChanged() {
    final phase = _controller.phase;
    if (phase == _lastPhase) return;
    final wasPlaying = _lastPhase == GamePhase.playing;
    _lastPhase = phase;

    // ここは notifyListeners の中なので setState は呼ばない。
    // 画面は AnimatedBuilder が同じ通知で描き直す。
    _pause?.cancel();
    final cleared =
        phase == GamePhase.stageCleared || phase == GamePhase.dungeonCleared;
    if (!cleared || !wasPlaying) {
      _holdingClear = false;
      return;
    }
    _holdingClear = true;
    _pause = Timer(_clearPause, () {
      if (!mounted) return;
      setState(() => _holdingClear = false);
    });
  }

  void _restart() => _controller.restart();

  /// 拠点を持っているか。持っていれば、決着したら呼び出し側に返す。
  bool get _reportsHome => widget.onFinished != null;

  void _finish({required bool cleared}) {
    widget.onFinished?.call(
      DungeonOutcome(
        dungeonId: _controller.dungeon.id,
        cleared: cleared,
        floor: _controller.floor,
      ),
    );
  }

  /// 踏破したので次のダンジョンへ。最後まで行っていたら1本目に戻る。
  /// 拠点があるときはそちらに返すので、ここには来ない。
  void _nextDungeon() {
    if (_reportsHome) {
      _finish(cleared: true);
      return;
    }
    final next = Dungeons.after(_controller.dungeon) ?? Dungeons.all.first;
    _controller.enterDungeon(next);
  }

  void _leaveDefeated() => _finish(cleared: false);

  void _nextFloor(Blessing blessing) => _controller.nextFloor(blessing);

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
                          phases: board.phases,
                          counts: board.phaseCounts,
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
                          hit: _controller.lastHit,
                          hitTick: _controller.hitTick,
                        ),
                        _Footer(controller: _controller, onRestart: _restart),
                      ],
                    ),
                    _HurtFlash(
                      tick: _controller.hitTick,
                      amount: _controller.lastHit + _controller.lastBacklash,
                    ),
                    if (_controller.phase == GamePhase.stageCleared &&
                        !_holdingClear)
                      _StageClearOverlay(
                        controller: _controller,
                        onChoose: _nextFloor,
                      ),
                    if (_controller.phase == GamePhase.dungeonCleared &&
                        !_holdingClear)
                      _DungeonClearOverlay(
                        controller: _controller,
                        onNext: _nextDungeon,
                        toHome: _reportsHome,
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
                        onLeave: _reportsHome ? _leaveDefeated : null,
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
              value: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'B${controller.floor}F',
                    style: AppFont.number(22, color: Palette.textMuted),
                  ),
                  // あと何階層あるのかが分からないと、体力をどこまで使ってよいか
                  // 決められない。踏破が目標になった以上ここは要る。
                  Text(
                    ' /${controller.dungeon.depth}',
                    style: AppFont.number(13, color: Palette.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 残りターン、残りの敵、相ごとの枚数。
///
/// 相のバーは「強い鎖をまだ編めるか」の目安。鎖は同じ相を続けて継げないので、
/// **いちばん少ない相の枚数が、編める長さの上限を決める**。だから危ないのは
/// 常に一番細い相で、そこだけ赤くする。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.phases,
    required this.counts,
    required this.movesLeft,
    required this.remainingFoes,
  });

  final List<Phase> phases;
  final List<int> counts;
  final int movesLeft;
  final int remainingFoes;

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final n in counts) {
      total += n;
    }
    // 相が増えるほど1つあたりの取り分は小さくなるので、危ない線も割って見る。
    final floor = phases.isEmpty ? 0.0 : 0.36 / phases.length;
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < phases.length; i++) ...[
                            if (i > 0) const Spacer(),
                            _PhaseCount(
                              phase: phases[i],
                              count: counts[i],
                              danger: total > 0 && counts[i] / total < floor,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      _PhaseBar(phases: phases, counts: counts),
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

/// 相1つぶんの色と枚数。
///
/// 呼び名は出さない。盤面で数えるのは色なので、同じ色のマスを小さく置く。
class _PhaseCount extends StatelessWidget {
  const _PhaseCount({
    required this.phase,
    required this.count,
    required this.danger,
  });

  final Phase phase;
  final int count;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? Palette.danger : Palette.baseFor(phase);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhaseSwatch(phase: phase, size: 13),
        const SizedBox(width: 6),
        Text('$count', style: AppFont.number(13, color: tint)),
      ],
    );
  }
}

/// 相ごとに1本のバーを分け合う。盤面は常に埋まっているので、
/// どれかが伸びれば必ず他が縮む。どこに傾いているかが一目で分かる。
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phases, required this.counts});

  final List<Phase> phases;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final n in counts) {
      total += n;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (var i = 0; i < phases.length; i++)
              Expanded(
                // 枚数が 0 でも幅が消えないよう、最低限の重みを残す。
                // 帯が消えると「その相がある」ことまで見えなくなる。
                flex: total == 0 ? 1 : counts[i] * 100 + 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: Palette.gradientFor(phases[i]),
                  ),
                ),
              ),
          ],
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
          'B${controller.floor}F を落とした',
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
  const _DefeatOverlay({
    required this.controller,
    required this.onRestart,
    this.onLeave,
  });

  final GameController controller;
  final VoidCallback onRestart;

  /// 拠点があるときだけ。魔晶が入るのはこちらを押したときで、
  /// その場でやり直す限り、失敗ぶんの魔晶は溜まらない。
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return _Curtain(
      children: [
        Text('一党は倒れた', style: AppFont.number(30, color: Palette.danger)),
        const SizedBox(height: 6),
        Text(
          'B${controller.floor}F の反撃で体力が尽きた',
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
        _ResultRow(label: '到達', value: 'B${controller.floor}F'),
        const SizedBox(height: 8),
        _ResultRow(label: '最大威力', value: '${controller.bestChain}'),
        const SizedBox(height: 8),
        _ResultRow(
          label: '討ち漏らし',
          value: '${controller.remainingFoes} 体',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: '1階層目からやり直す', onTap: onRestart),
        if (onLeave != null) ...[
          const SizedBox(height: 10),
          _PlainButton(label: '拠点へ戻る', onTap: onLeave!),
        ],
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
          'B${controller.floor}F 制圧',
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

/// ダンジョンの踏破。最下層を制圧したときだけ出る。
///
/// ここでは祝福を選ばせない。持ち越す先が無いのと、踏破の瞬間に選択を挟むと
/// 「終わった」という区切りがぼやけるため。
class _DungeonClearOverlay extends StatelessWidget {
  const _DungeonClearOverlay({
    required this.controller,
    required this.onNext,
    this.toHome = false,
  });

  final GameController controller;
  final VoidCallback onNext;

  /// 拠点に戻る形か。戻る先があるなら、次のダンジョンは拠点で選ばせる。
  final bool toHome;

  @override
  Widget build(BuildContext context) {
    final next = Dungeons.after(controller.dungeon);
    final party = controller.party;
    return _Curtain(
      children: [
        Text('踏 破', style: AppFont.number(34, color: Palette.gold)),
        const SizedBox(height: 8),
        Text(
          controller.dungeon.name,
          style: const TextStyle(
            color: Palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        _FoeLineup(wards: controller.felledWards, felled: true),
        const SizedBox(height: 20),
        Text('SCORE', style: AppFont.label(10)),
        const SizedBox(height: 8),
        Text('${controller.score}', style: AppFont.number(56)),
        const SizedBox(height: 18),
        _ResultRow(label: '踏破した階層', value: 'B${controller.dungeon.depth}F'),
        const SizedBox(height: 8),
        _ResultRow(label: '最大威力', value: '${controller.bestChain}'),
        const SizedBox(height: 8),
        _ResultRow(
          label: '残った体力',
          value: '${party.hp} / ${party.maxHp}',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(
          label: toHome
              ? '拠点へ戻る'
              : next == null
              ? '最初のダンジョンへ'
              : '${next.name} へ',
          onTap: onNext,
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
/// 敵に殴られた瞬間、画面の縁から差す赤。
///
/// 一党の帯に出る `-N` だけでは、盤面を見ている目に入らない。毎ターン
/// 殴られる以上、視線を動かさずに分かる知らせが要る。
///
/// **中央は透かしたまま**にしてある。盤面の上に色を乗せると、マスの相が
/// 読めなくなって次の手を選べない。縁だけを染める。
class _HurtFlash extends StatefulWidget {
  const _HurtFlash({required this.tick, required this.amount});

  /// 痛手を受けた回数。変わるたびに頭から流し直す。量だけを見ていると、
  /// 同じ量が続けて来たときに2回目が鳴らない。
  final int tick;

  /// 受けた量。濃さに効く。
  final int amount;

  @override
  State<_HurtFlash> createState() => _HurtFlashState();
}

class _HurtFlashState extends State<_HurtFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// 差し込みから引くまで。長いと次の手を考える邪魔になる。
  static const _span = Duration(milliseconds: 700);

  /// 立ち上がりにかける割合。殴られた手応えは速さで出る。
  static const double _rise = 0.10;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _span);
  }

  @override
  void didUpdateWidget(_HurtFlash old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick && widget.amount > 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 毎ターンの反撃は 1〜6、階層を落としたときの反撃は 20 を超える。
    // 濃さは頭打ちにして、痛手が大きいほど濃いが画面は潰れないようにする。
    final strength = (widget.amount / 8).clamp(0.55, 1.0);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          if (t == 0 || t == 1) return const SizedBox.expand();
          final e = t < _rise ? t / _rise : 1 - (t - _rise) / (1 - _rise);
          final a = Curves.easeOut.transform(e.clamp(0.0, 1.0)) * strength;
          // 立ち上がりに1回だけ、画面全体を薄く赤に沈める。縁だけだと
          // 目の端に流れてしまうので、最初の一瞬だけ視界の真ん中にも置く。
          final wash = t < _rise * 2
              ? (1 - (t / (_rise * 2))) * strength * 0.18
              : 0.0;
          return Stack(
            children: [
              if (wash > 0)
                Positioned.fill(
                  child: ColoredBox(
                    color: Palette.danger.withValues(alpha: wash),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      // 縁を厚く取る。薄い輪だと画面の外に逃げて見えない。
                      radius: 0.92,
                      colors: [
                        const Color(0x00000000),
                        Palette.danger.withValues(alpha: a * 0.45),
                        Palette.danger.withValues(alpha: a * 0.95),
                      ],
                      stops: const [0.28, 0.66, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 受けた痛手の数字。跳ねてから薄く残る。
///
/// 出しっぱなしの文字だと、同じ量が続いたときに「まだ殴られているのか、
/// さっきのが残っているのか」が分からない。1手ごとに跳ね直す。
class _HitTag extends StatefulWidget {
  const _HitTag({required this.amount, required this.tick});

  final int amount;
  final int tick;

  @override
  State<_HitTag> createState() => _HitTagState();
}

class _HitTagState extends State<_HitTag> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void didUpdateWidget(_HitTag old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick) _c.forward(from: 0);
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
        final t = _c.value;
        // 立ち上がりで少し大きく出して、すぐ等倍に落とす。
        final pop = t < 0.22
            ? 1 + Curves.easeOut.transform(t / 0.22) * 0.55
            : 1.55 - Curves.easeOutCubic.transform((t - 0.22) / 0.78) * 0.55;
        return Transform.translate(
          // 下から突き上げる。落ちてくる向きだと回復と見分けがつかない。
          offset: Offset(0, (1 - Curves.easeOut.transform(t)) * 5),
          child: Transform.scale(scale: pop, child: child),
        );
      },
      child: Text(
        '-${widget.amount}',
        style: AppFont.number(12, color: Palette.danger),
      ),
    );
  }
}

class _PartyBar extends StatelessWidget {
  const _PartyBar({
    required this.party,
    required this.healed,
    required this.hit,
    required this.hitTick,
  });

  final Party party;

  /// 直近の鎖で戻した体力。0 なら何も出さない。
  final int healed;

  /// 直近の1手で敵から受けた痛手。敵は毎ターン殴ってくるので、これを
  /// 出さないと体力がひとりでに減っているように見える。
  final int hit;

  /// 痛手を受けた回数。[_HitTag] がこれを見て出方を流し直す。
  final int hitTick;

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
                        if (hit > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _HitTag(amount: hit, tick: hitTick),
                          ),
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
        child: MagePortrait(kind: mage.kind, size: 21),
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

/// 主でない方の選択肢。枠だけのボタン。
class _PlainButton extends StatelessWidget {
  const _PlainButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(radius: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
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
