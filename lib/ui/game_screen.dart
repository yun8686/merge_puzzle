import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/phase.dart';
import 'board_view.dart';
import 'foe_art.dart';
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
                        ),
                        _Footer(controller: _controller, onRestart: _restart),
                      ],
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
                              danger:
                                  total > 0 && counts[i] / total < floor,
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

/// 相1つぶんの呼び名と枚数。
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
        Text(phase.label, style: AppFont.label(10, color: tint)),
        const SizedBox(width: 5),
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
