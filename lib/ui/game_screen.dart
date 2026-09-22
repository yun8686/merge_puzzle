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

  /// スキルを開いている魔導士。null なら閉じている。
  ///
  /// **潜っている最中にスキルを確かめる道はここしか無い。** 名簿は拠点にあって
  /// 途中では開けないので、無いと「誰を連れてきたか」は姿で分かるのに
  /// 「何をする人か」が確かめられない。
  MageKind? _inspecting;

  /// アクティブスキルが空振りしたときの一言。**札の中に出す。**
  ///
  /// 盤面に何も起きないので、閉じてしまうと「押したのに無反応」に見える。
  /// 札を開いたまま、なぜ何も起きなかったかを言う。
  String? _useNote;

  void _inspect(Mage mage) => setState(() {
    _inspecting = mage.kind;
    _useNote = null;
  });

  void _closeInspect() => setState(() {
    _inspecting = null;
    _useNote = null;
  });

  /// アクティブスキルを使う。通ったら札を閉じて、見せた道を盤面に出す。
  ///
  /// **空振りでは閉じない。** 回数も減っていないので、盤面を崩してから
  /// もう一度押せばよい――そのことごと札の中で言う。
  void _use(MageKind kind) {
    final result = _controller.useActive(kind);
    setState(() {
      _useNote = switch (result) {
        ActiveResult.done => null,
        ActiveResult.missed => 'どのルートも敵に届かなかった　使用回数は減っていない',
        ActiveResult.unavailable => 'いまは使えない',
      };
      if (result == ActiveResult.done) _inspecting = null;
    });
  }

  /// 中断の確かめを出しているか。
  ///
  /// **押してすぐには帰さない。** 潜っている途中の体力も戦果もここで打ち切られ、
  /// 次は1階層目からになる。取り返しが付かない側なので、一度止めて訊く。
  bool _confirmingAbort = false;

  void _askAbort() => setState(() => _confirmingAbort = true);

  void _cancelAbort() => setState(() => _confirmingAbort = false);

  void _abort() {
    setState(() => _confirmingAbort = false);
    // 途中で切り上げただけなので、討ち果たしてはいない。降りた階層のぶんを
    // どう扱うかは拠点の仕事（この画面は記録を読まない）。
    _finish(cleared: false);
  }

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

  void _nextFloor() => _controller.nextFloor();

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
                          remainingFoes: _controller.remainingFoes,
                        ),
                        // 体力は盤面の上。**殴られた側が盤面の上に居る**ので、
                        // 敵の一撃もそちらへ飛ぶ（`BoardView` の `_foeWindUp`）。
                        _PartyBar(
                          party: _controller.party,
                          healed: _controller.lastHealed,
                          hit: _controller.lastHit,
                          hitTick: _controller.hitTick,
                          evaded: _controller.lastEvaded,
                          onInspect: _inspect,
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
                        _Footer(
                          controller: _controller,
                          // 戻る先が無い差し込み（テストなど）では出さない。
                          onAbort: _reportsHome ? _askAbort : null,
                        ),
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
                        onNext: _nextFloor,
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
                    if (_confirmingAbort &&
                        _controller.phase == GamePhase.playing)
                      _AbortOverlay(
                        controller: _controller,
                        onCancel: _cancelAbort,
                        onLeave: _abort,
                      ),
                    if (_controller.phase == GamePhase.defeated)
                      _DefeatOverlay(
                        controller: _controller,
                        onRestart: _restart,
                        onLeave: _reportsHome ? _leaveDefeated : null,
                      ),
                    // いちばん上。決着の覆いが出ている間も閉じられる。
                    if (_inspecting != null)
                      _MageSheet(
                        controller: _controller,
                        kind: _inspecting!,
                        onSelect: (kind) => setState(() {
                          _inspecting = kind;
                          // 別の人に移ったら、前の人の空振りの話は消す。
                          _useNote = null;
                        }),
                        onUse: _use,
                        note: _useNote,
                        onClose: _closeInspect,
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

/// ロゴタイプ。赤の相=暖色、青の相=寒色というルールの色をそのまま使うので、
/// 見出しがそのまま配色の説明になっている。
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Palette.redA, Palette.redB, Palette.blueB, Palette.blueA],
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

/// 残りの敵と、相ごとの枚数。
///
/// 相のバーは「強い鎖をまだ編めるか」の目安。鎖は同じ相を続けて継げないので、
/// **いちばん少ない相の枚数が、編める長さの上限を決める**。だから危ないのは
/// 常に一番細い相で、そこだけ赤くする。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.phases,
    required this.counts,
    required this.remainingFoes,
  });

  final List<Phase> phases;
  final List<int> counts;
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
    return 'あと ${controller.missingTiles} つなげばチェインになる';
  }
  final toFoe = controller.tilesToNextFoe;
  if (toFoe > 0) {
    return controller.pathIsValid
        ? 'あと $toFoe つなげば倒せる'
        : 'あと $toFoe つなげば届く';
  }
  if (controller.pathIsValid) return '+${controller.pendingScore}';
  return '防御を破れない';
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, this.onAbort});

  final GameController controller;

  /// 潜りを中断して拠点へ戻る。戻る先が無いときは null で、札も出さない。
  final VoidCallback? onAbort;

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
                    : _RuleNote(spread: controller.board.spreadPhase),
              ),
            ),
          ),
          if (onAbort != null) ...[
            const SizedBox(width: 8),
            _IconAction(
              icon: Icons.logout,
              tint: Palette.danger,
              onTap: onAbort!,
            ),
          ],
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
  const _Curtain({required this.children, this.onDismiss});

  final List<Widget> children;

  /// 覆いの外を押したときに呼ぶ。決着の覆いは押して消えては困るので既定は
  /// null。**閉じられるのは、閉じても何も失われない覆いだけ。**
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // onTap が null のときは認識器を置かないので、決着の覆いの当たり方は
        // 今までと変わらない。
        behavior: onDismiss == null
            ? HitTestBehavior.deferToChild
            : HitTestBehavior.opaque,
        onTap: onDismiss,
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
                        // 札そのものを押しても閉じない。中の切り替えを押す
                        // つもりで外したときに消えると、読み直せない。
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
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
        ),
      ),
    );
  }
}

/// 階層を落とした。盤面から継げる手が消えたとき。
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
          'B${controller.floor}F で行き詰まった',
          style: AppFont.number(26, color: Palette.danger),
        ),
        const SizedBox(height: 6),
        const Text(
          'つなげる色がなくなった',
          style: TextStyle(
            color: Palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _FoeLineup(wards: controller.board.foeWards),
        const SizedBox(height: 18),
        Text('残った敵の反撃', style: AppFont.label(10)),
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
          label: '残りの敵',
          value: '${controller.remainingFoes} 体',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: 'この階層をやり直す', onTap: onRetry),
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
        Text('パーティは全滅した', style: AppFont.number(30, color: Palette.danger)),
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
          label: '残りの敵',
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

/// 中断の確かめ。**押してすぐには帰さない。**
///
/// 潜っている途中の体力も戦果もここで打ち切られる。取り返しが付かない側なので、
/// 何が失われるかを出したうえで訊く。既定（目立つほう）は「続ける」。
/// 盤面の下に出す、いまの継ぎ方の決まり。
///
/// **延焼のあいだはここが入れ替わる。** 決まりが緩んでいることを盤面の外で
/// 言わないと、押したのに何も起きていないように見える（盤面の側は、継げる
/// マスの光り方が変わるだけ）。緩めた相の色で出すので、どの色が繋がるように
/// なったのかも読める。
class _RuleNote extends StatelessWidget {
  const _RuleNote({required this.spread});

  /// 延焼している相。null なら普段の決まり。
  final Phase? spread;

  @override
  Widget build(BuildContext context) {
    final phase = spread;
    if (phase == null) {
      return const Text(
        '同じ色を続けずに、なぞってつなぐ',
        key: ValueKey('hint'),
        style: TextStyle(
          color: Palette.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Row(
      key: const ValueKey('hint-spread'),
      mainAxisSize: MainAxisSize.min,
      children: [
        PhaseSwatch(phase: phase, size: 14),
        const SizedBox(width: 7),
        Text(
          '延焼中　今のチェインは${phase.label}どうしもつなげる',
          style: TextStyle(
            color: Palette.baseFor(phase),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AbortOverlay extends StatelessWidget {
  const _AbortOverlay({
    required this.controller,
    required this.onCancel,
    required this.onLeave,
  });

  final GameController controller;
  final VoidCallback onCancel;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final party = controller.party;
    return _Curtain(
      children: [
        Text('中断する', style: AppFont.number(26, color: Palette.danger)),
        const SizedBox(height: 10),
        const Text(
          '探索をやめて拠点へ戻る。\n'
          '体力もスコアも引き継がれず、次は1階層目から。\n'
          '降りた階層ぶんの魔晶は持ち帰れる。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Palette.textMuted,
            fontSize: 13,
            height: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _ResultRow(label: '到達', value: 'B${controller.floor}F'),
        const SizedBox(height: 8),
        _ResultRow(label: '残った体力', value: '${party.hp} / ${party.maxHp}'),
        const SizedBox(height: 26),
        _PrimaryButton(label: '続ける', onTap: onCancel),
        const SizedBox(height: 10),
        _PlainButton(label: '中断して拠点へ', onTap: onLeave),
      ],
    );
  }
}

/// 階層の制圧。その階の敵を全部討ったときだけ出る。
///
/// **ここでは何も選ばせない。** 道中で増えるものは無く、体力もそのまま
/// 持ち越すので、戦果を見せて次の階層へ送るだけ。
class _StageClearOverlay extends StatelessWidget {
  const _StageClearOverlay({required this.controller, required this.onNext});

  final GameController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Curtain(
      children: [
        Text(
          'B${controller.floor}F クリア',
          style: AppFont.number(26, color: Palette.gold),
        ),
        const SizedBox(height: 6),
        const Text(
          'この階層の敵を全部倒した',
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
        _ResultRow(label: '最大威力', value: '${controller.bestChain}'),
        const SizedBox(height: 8),
        _ResultRow(
          label: '残った体力',
          value: '${controller.party.hp} / ${controller.party.maxHp}',
        ),
        const SizedBox(height: 26),
        _PrimaryButton(label: 'B${controller.floor + 1}F へ降りる', onTap: onNext),
      ],
    );
  }
}

/// ダンジョンの踏破。最下層を制圧したときだけ出る。
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
        Text('クリア', style: AppFont.number(34, color: Palette.gold)),
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
        _ResultRow(label: 'クリアした階層', value: 'B${controller.dungeon.depth}F'),
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
          felled ? '倒した敵' : '残った敵',
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
    required this.evaded,
    required this.onInspect,
  });

  final Party party;

  /// 直近の鎖で戻した体力。0 なら何も出さない。
  final int healed;

  /// 直近の1手で敵から受けた痛手。敵は毎ターン殴ってくるので、これを
  /// 出さないと体力がひとりでに減っているように見える。
  final int hit;

  /// 痛手を受けた回数。[_HitTag] がこれを見て出方を流し直す。
  final int hitTick;

  /// 直近の鎖で風が反撃を凌いだ。**痛手が 0 なだけでは理由が読めない**ので、
  /// 凌いだことを風の色で名乗らせる。
  final bool evaded;

  /// 姿を押したときに開く。スキルを確かめる道はここしか無い。
  final ValueChanged<Mage> onInspect;

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
                        if (evaded)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '反撃なし',
                              style: AppFont.label(
                                9,
                                color: Palette.mageColor(MageKind.gale),
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
                  child: _MageChip(
                    key: ValueKey('party-${mage.kind.name}'),
                    mage: mage,
                    ready: party.canUse(mage.kind),
                    onTap: () => onInspect(mage),
                  ),
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
///
/// **押すとスキルが開く**（[_MageSheet]）。指で遊ぶので、被せの札
/// （[Tooltip]）だけでは長押ししないと出ず、あることに気付けない。
class _MageChip extends StatelessWidget {
  const _MageChip({
    super.key,
    required this.mage,
    required this.onTap,
    this.selected = false,
    this.ready = false,
  });

  final Mage mage;
  final VoidCallback onTap;

  /// いま開いている魔導士。切り替えの列で、どれを見ているかを示す。
  final bool selected;

  /// アクティブスキルがまだ残っている。**印が無いと気付けない。**
  /// 潜り1本に1回しか使えないものを、押してみるまで分からない場所に
  /// 置くと、そのまま使われずに終わる。
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.mageColor(mage.kind);
    return Tooltip(
      message: [
        mage.name,
        if (mage.passiveName case final name?)
          '$name（パッシブ）　${mage.passiveEffect}'
        else
          mage.passiveEffect,
        if (mage.activeEffect case final text?)
          '${mage.activeName}（アクティブ）　$text',
      ].join('\n'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              tint.withValues(alpha: selected ? 0.4 : 0.18),
              Palette.panel,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: tint.withValues(alpha: selected ? 1 : 0.6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              MagePortrait(kind: mage.kind, size: 21),
              if (ready)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Palette.gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: Palette.panel, width: 1.5),
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

/// 連れている魔導士1人の詳細。一党の帯の姿を押すと開く。
///
/// **潜っている最中にスキルを確かめられる唯一の場所。** 名簿は拠点にあって
/// 途中では開けないので、ここが無いと「誰を連れてきたか」は姿で分かるのに
/// 「何をする人か」が確かめられない。
///
/// **開いたまま他の顔ぶれへ移れる。** 下に連れている全員を並べてあるので、
/// 焔と烈火のどちらが何枚で乗るのかを、閉じて開き直さずに見比べられる。
///
/// 覆いで盤面を隠すのは、ここが手を選ぶ場面ではないから。読むあいだ盤面を
/// 半端に透かすより、読み終えて閉じたときに元の盤面がそのまま出るほうがよい。
class _MageSheet extends StatelessWidget {
  const _MageSheet({
    required this.controller,
    required this.kind,
    required this.onSelect,
    required this.onUse,
    required this.note,
    required this.onClose,
  });

  final GameController controller;

  /// いま開いている魔導士。
  final MageKind kind;

  final ValueChanged<MageKind> onSelect;

  /// アクティブスキルを使う。
  final ValueChanged<MageKind> onUse;

  /// 空振りしたときの一言。無ければ出さない。
  final String? note;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final party = controller.party;
    final mage = Mage.of(kind);
    final tint = Palette.mageColor(kind);
    final active = mage.active;
    return _Curtain(
      onDismiss: onClose,
      children: [
        MagePortrait(kind: kind, size: 64),
        const SizedBox(height: 12),
        Text(mage.name, style: AppFont.number(22, color: tint)),
        const SizedBox(height: 12),
        // 相は呼び名より先に色で読む。盤面のマスと同じ小片を並べる。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhaseSwatch(phase: mage.phase, size: 18),
            const SizedBox(width: 8),
            Text(
              '${mage.phase.label}属性',
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('パッシブスキル', style: AppFont.label(10, color: Palette.textDim)),
        const SizedBox(height: 8),
        if (mage.passiveName case final name?) ...[
          Text(name, style: AppFont.number(17, color: Palette.passive)),
          const SizedBox(height: 6),
        ],
        Text(
          mage.passiveEffect,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.textPrimary,
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        // この1人がどれだけ厚みを出しているか。合計しか帯に出ていないので、
        // 誰を連れてきたから 135 なのかはここでしか読めない。
        _ResultRow(label: 'この魔導士の体力', value: '${mage.hp}'),
        const SizedBox(height: 8),
        _ResultRow(label: 'パーティの体力', value: '${party.hp} / ${party.maxHp}'),
        if (active != null) ...[
          const SizedBox(height: 22),
          Text(
            'アクティブスキル',
            style: AppFont.label(10, color: Palette.textDim),
          ),
          const SizedBox(height: 8),
          Text(active.name, style: AppFont.number(17, color: Palette.active)),
          const SizedBox(height: 6),
          Text(
            mage.activeEffect!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.textMuted,
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '1回の探索で ${Party.activeUses} 回',
            style: AppFont.label(9, color: Palette.textDim),
          ),
          const SizedBox(height: 12),
          if (party.canUse(kind) && controller.acceptsInput)
            _PrimaryButton(label: '使う', onTap: () => onUse(kind))
          else
            Text(
              party.canUse(kind) ? '盤面が動いている' : 'この探索ではもう使った',
              style: AppFont.label(10, color: Palette.textDim),
            ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.danger,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final other in party.members)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _MageChip(
                  key: ValueKey('sheet-${other.kind.name}'),
                  mage: other,
                  selected: other.kind == kind,
                  ready: party.canUse(other.kind),
                  onTap: () => onSelect(other.kind),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _PlainButton(label: '閉じる', onTap: onClose),
      ],
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
        gradient: const LinearGradient(colors: [Palette.blueA, Palette.blueB]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Palette.blueB.withValues(alpha: 0.5),
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
