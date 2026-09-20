import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/board.dart';
import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import 'board_view.dart';
import 'mage_art.dart';
import 'theme.dart';

/// 初回だけ出る遊び方。**読ませるのではなく、実際になぞらせる。**
///
/// 盤面は本物（`BoardView` と `GameController`）。継ぎ方の決まりも、威力の
/// 計算も、毎ターンの反撃も本番と同じものが動く。絵で説明してから本番で
/// 学び直させるより、最初から本物を触らせるほうが速いし、嘘が混ざらない。
///
/// 課題は**盤面の状態だけ**で判定する（何枚継いだか、討ったか）。なぞる道を
/// 指定しないので、詰まっても自分で見つけた手で先へ進める。迷ったときのため
/// に、しばらく手が止まると通る道が光る。
///
/// 記録は読み書きしない。通し終えたことを [onDone] で知らせるだけで、印を
/// 付けて保存するのは拠点の仕事。
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onDone, this.controller});

  final VoidCallback onDone;

  /// 差し込むと、画面が自前で作る代わりにこれを使う。特定の局面から始めたい
  /// テスト用（`GameScreen` と同じ約束）。
  final GameController? controller;

  /// 稽古場。敵は2体だけで、手数はたっぷり取ってある。
  ///
  /// 攻撃力を1ずつに抑えてあるのは、覚えるより先に倒されないため。40手を
  /// 使い切っても 80 で、初期体力 120 には届かない。
  static const Dungeon dungeon = Dungeon(
    id: 'tutorial',
    name: '稽古場',
    floors: [
      FloorSpec(
        [FoeSpec(3, atk: 1), FoeSpec(5, hp: 2, atk: 1)],
        moves: 40,
      ),
    ],
  );

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

/// 課題ひとつ。盤面の状態だけで「できた」を決める。
class _Lesson {
  const _Lesson({required this.text, required this.done});

  /// 上に出す一言。`**` で挟んだところだけ明るくする。
  final String text;

  final bool Function(GameController) done;
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final GameController _controller;
  late final bool _ownsController;
  Timer? _idle;
  Timer? _cheer;
  int _at = 0;

  /// 課題が変わった直後だけ出す「できた」。
  bool _cheering = false;

  /// 手が止まってから道を光らせるまで。すぐ出すと自分で探す気が失せる。
  static const Duration _hintAfter = Duration(seconds: 6);

  static final List<_Lesson> _lessons = [
    _Lesson(
      text: '隣り合うマスを指でなぞって継ぐ。\n'
          '**同じ相（色）は続けて継げない。**\n'
          '3枚つなげば鎖になる。',
      done: (c) => c.bestChain >= 3,
    ),
    _Lesson(
      text: '継いだ枚数が、そのまま鎖の**威力**になる。\n'
          '遠回りしてでも、6枚つないでみよう。',
      done: (c) => c.bestChain >= 6,
    ),
    _Lesson(
      text: 'マスの数字は敵の**守り**。\n'
          '威力が守りに届けば傷がつく。\n'
          '守り3の敵を討ち取ろう。',
      done: (c) => c.felledWards.isNotEmpty,
    ),
    _Lesson(
      text: '**敵は毎ターン殴ってくる。**\n'
          '体力が減るのはそのため。早く討つほど楽になる。\n'
          '残りの敵も討ち取ろう。',
      done: (c) => c.remainingFoes == 0,
    ),
  ];

  bool get _finished => _at >= _lessons.length;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        GameController(
          rng: Random(4),
          dungeon: TutorialScreen.dungeon,
          // 能力を持たない従者だけ。威力＝枚数になるので、「6枚つなぐ」が
          // そのまま「威力6」になって説明と食い違わない。
          roster: const [Mage.squireHeat, Mage.squireCold],
        );
    _controller.addListener(_check);
    _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _cheer?.cancel();
    _controller.removeListener(_check);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// 手が止まったら道を光らせる。動かすたびに数え直す。
  void _restartIdle() {
    _idle?.cancel();
    if (_finished) return;
    _idle = Timer(_hintAfter, () {
      if (!mounted || _finished || !_controller.acceptsInput) return;
      _controller.showHint();
    });
  }

  void _check() {
    if (!mounted) return;
    // 倒れても手数が尽きても、稽古場なので黙って組み直す。ここで躓かせると
    // 覚える前に投げられる。
    if (_controller.phase == GamePhase.floorLost ||
        _controller.phase == GamePhase.defeated) {
      _controller.enterDungeon(TutorialScreen.dungeon);
      return;
    }
    // 最後の課題（敵を討ち切る）が片付いたら、途中が残っていても終い。
    // 盤面から敵が居なくなると、残した課題はもう試しようがない。
    final int i;
    if (_lessons.last.done(_controller)) {
      i = _lessons.length;
    } else {
      var n = _at;
      while (n < _lessons.length && _lessons[n].done(_controller)) {
        n++;
      }
      i = n;
    }
    if (i != _at) {
      final finished = i >= _lessons.length;
      setState(() {
        _at = i;
        // 終いの言葉が出るところでは重ねない。
        _cheering = !finished;
      });
      _cheer?.cancel();
      if (!finished) {
        _cheer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _cheering = false);
        });
      }
    }
    _restartIdle();
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
              builder: (context, _) => Column(
                children: [
                  _Banner(
                    at: _at,
                    total: _lessons.length,
                    text: _finished
                        ? ''
                        : _lessons[_at].text,
                    onSkip: widget.onDone,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: BoardView(controller: _controller),
                    ),
                  ),
                  _Gauges(controller: _controller),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (_cheering && !_finished)
            const IgnorePointer(child: Center(child: _Cheer())),
          if (_finished) _Finish(onDone: widget.onDone),
        ],
      ),
    );
  }
}

/// 上に出す課題。高さを決め打ちにして、文が変わっても盤面が動かないように
/// してある。
class _Banner extends StatelessWidget {
  const _Banner({
    required this.at,
    required this.total,
    required this.text,
    required this.onSkip,
  });

  final int at;
  final int total;
  final String text;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < total; i++)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: i == at ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i <= at ? Palette.evenA : Palette.panelBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'とばす',
                  style: AppFont.label(10, color: Palette.textDim),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 76,
            child: Center(child: _Body(text)),
          ),
        ],
      ),
    );
  }
}

/// 一言。`**` で挟んだところだけ明るくする。
///
/// 覚えてほしいのは各課題に1つだけ。そこだけ色を変えておけば、読み飛ばしても
/// 目が止まる。
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      color: Palette.textMuted,
      fontSize: 12.5,
      height: 1.6,
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

/// 下の目盛り。体力・残りの手数・残りの敵。
///
/// 盤面の画面と同じものを並べてある。ここで覚えた読み方が、そのまま本番で
/// 効くようにするため。
class _Gauges extends StatelessWidget {
  const _Gauges({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final party = controller.party;
    final ratio = party.maxHp == 0 ? 0.0 : party.hp / party.maxHp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: panelDecoration(radius: 14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
          child: Row(
            children: [
              Text('体力', style: AppFont.label(9, color: Palette.life)),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Palette.boardBg,
                    valueColor: const AlwaysStoppedAnimation(Palette.life),
                  ),
                ),
              ),
              const Spacer(),
              Text('残り手数', style: AppFont.label(9)),
              const SizedBox(width: 6),
              Text(
                '${controller.movesLeft}',
                style: AppFont.number(15, color: Palette.textMuted),
              ),
              const SizedBox(width: 14),
              Text('敵', style: AppFont.label(9, color: Palette.gold)),
              const SizedBox(width: 6),
              Text(
                '${controller.remainingFoes}',
                style: AppFont.number(15, color: Palette.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 課題がひとつ片付いたときの短い手応え。
class _Cheer extends StatelessWidget {
  const _Cheer();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.boardBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.life.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Palette.life.withValues(alpha: 0.28),
            blurRadius: 30,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 16, 30, 18),
        child: Text(
          'できた',
          style: AppFont.number(22, color: Palette.life),
        ),
      ),
    );
  }
}

/// 通し終えたところ。**盤面では教えられない編成の話だけ、ここで足す。**
class _Finish extends StatelessWidget {
  const _Finish({required this.onDone});

  final VoidCallback onDone;

  static const _party = [MageKind.ember, MageKind.rime, MageKind.storm];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.background.withValues(alpha: 0.94),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ひととおり覚えた', style: AppFont.number(22)),
              const SizedBox(height: 26),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in _party)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: MagePortrait(kind: kind, size: 36),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Icon(
                Icons.arrow_downward,
                color: Palette.textDim,
                size: 18,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in _party)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: PhaseSwatch(
                        phase: Mage.of(kind).phase,
                        size: 24,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const _Body(
                'あとひとつ。盤面に出る相は、\n'
                '**連れていった魔導士で決まる。**\n'
                '相は2種類以上でなければ、鎖が1枚も編めない。',
              ),
              const SizedBox(height: 30),
              _DoneButton(onTap: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 15),
            child: Text(
              '拠点へ',
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
    );
  }
}
