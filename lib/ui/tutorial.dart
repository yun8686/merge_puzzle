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
/// に、通る道がずっと光っている。
///
/// ## 稽古の筋書き
///
/// 目指すのは「1回目の潜りで、何が起きているか分かる」ところまで。
/// **覚えることを1つずつ積む**。前の課題で作った盤面が、次の課題の材料に
/// なるように並べてある。
///
/// 1. **鎖を編む** … 指でなぞって継ぐ。同じ相は続けて継げない。3枚で成立
/// 2. **長いほど強い** … 枚数がそのまま威力。まず6枚
/// 3. **守りを破る** … マスの数字は越えるべき線。守り3を討つ
/// 4. **まとめて当てる** … 1本の鎖は通った敵すべてに当たる。2体を通す
/// 5. **削って討つ** … 1本で討てない敵が居る。傷は残るので、もう一度当てる
/// 6. **毎ターンの反撃** … 敵は毎手殴ってくる。残りを討ち果たす
///
/// 4 が 5 を用意する。2体を通した鎖は、厚いほうを討ち切れずに傷だけ残す
/// ことが多い。**その傷ついた敵がそのまま 5 の教材になる**ので、「傷は
/// 残る」を言葉ではなく盤面で見せられる。3 で1体討ったあとにも2体残る
/// よう、敵は3体置いてある。
///
/// 盤面で試せないことだけ、終いの画面で言い添える（[_DiveNote] は階層と
/// 手数、[_PartyNote] は編成）。手数切れの痛手は**わざと味わわせない**。
/// 覚える前に落とされると、覚えたことごと投げられる。
///
/// 記録は読み書きしない。通し終えたことを [onDone] で知らせるだけで、印を
/// 付けて保存するのは拠点の仕事。
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onDone, this.controller});

  final VoidCallback onDone;

  /// 差し込むと、画面が自前で作る代わりにこれを使う。特定の局面から始めたい
  /// テスト用（`GameScreen` と同じ約束）。
  final GameController? controller;

  /// 1本では討ち切れない敵の守り。**「削って討つ」の教材。** 体力2なので、
  /// 討ち取るには威力5の鎖を2本（または威力6以上の1本）要る。
  static const int toughWard = 5;

  /// 稽古場。敵は3体で、手数はたっぷり取ってある。
  ///
  /// 攻撃力を1ずつに抑えてあるのは、覚えるより先に倒されないため。3体とも
  /// 生かしたまま40手を使い切ってようやく 120 で、初期体力とちょうど同じ。
  /// 討つたびに減るので、普通に進めればそこまで届かない（倒れたところで
  /// 稽古場は黙って組み直す）。
  ///
  /// **置く場所は決め打ち**（[FoeSpec.at]）。散らすと隣り合って出ることが
  /// あり、最初の稽古で「敵と敵を繋いでいる」ように見えてしまう。3体とも
  /// 4マス以上離しつつ、下の2体は1本の鎖で通せる間合いに置いてある
  /// （「まとめて当てる」の稽古で通る道が要る）。
  ///
  /// 3体居るのは、「守りを破る」で1体討ったあとにも2体残すため。2体だけだと
  /// まとめて当てる稽古が試しようがなくなる。
  static const Dungeon dungeon = Dungeon(
    id: 'tutorial',
    name: '稽古場',
    floors: [
      FloorSpec(
        [
          FoeSpec(3, atk: 1, at: Cell(1, 1)),
          FoeSpec(3, atk: 1, at: Cell(5, 1)),
          FoeSpec(toughWard, hp: 2, atk: 1, at: Cell(4, 4)),
        ],
        moves: 40,
      ),
    ],
  );

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

/// 課題ひとつ。盤面の状態だけで「できた」を決める。
class _Lesson {
  const _Lesson({
    required this.label,
    required this.text,
    required this.done,
    this.pairHint = false,
  });

  /// お手本に、2体の敵を通る道を出すか。まとめて当てる稽古だけが立てる。
  /// 普段の道を出してしまうと、示した手では課題が進まない。
  final bool pairHint;

  /// 終いの振り返りに並べる短い名札。
  final String label;

  /// 上に出す一言。`**` で挟んだところだけ明るくする。
  final String text;

  final bool Function(GameController) done;
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final GameController _controller;
  late final bool _ownsController;
  Timer? _cheer;
  int _at = 0;

  /// 課題が変わった直後だけ出す「できた」。
  bool _cheering = false;

  static final List<_Lesson> _lessons = [
    _Lesson(
      label: '鎖を編む',
      text: '隣り合うマスを指でなぞって継ぐ。\n'
          '**同じ相（色）は続けて継げない。**\n'
          '3枚つなげば鎖になる。',
      done: (c) => c.bestChain >= 3,
    ),
    _Lesson(
      label: '長いほど強い',
      text: '継いだ枚数が、そのまま鎖の**威力**になる。\n'
          '遠回りしてでも、6枚つないでみよう。',
      done: (c) => c.bestChain >= 6,
    ),
    _Lesson(
      label: '守りを破る',
      text: 'マスに書かれた数字は、その敵の**守り**。\n'
          '下の帯の威力がその数に届けば、傷がつく。\n'
          '守り3の敵を討ち取ろう。',
      done: (c) => c.felledWards.isNotEmpty,
    ),
    _Lesson(
      label: 'まとめて当てる',
      text: '1本の鎖は、**通った敵すべて**に当たる。\n'
          '離れた敵どうしも、道でつなげば一度に狙える。\n'
          '2体の敵を通る鎖を編もう。',
      // 残り1体になったら試しようがないので、そこで畳む。稽古場で
      // 詰ませない。
      done: (c) => c.lastFoesHit >= 2 || c.remainingFoes < 2,
      pairHint: true,
    ),
    _Lesson(
      label: '削って討つ',
      text: '守りの厚い敵は、1本では討ち切れない。\n'
          '**つけた傷はそのまま残る。**粒が残りの体力。\n'
          'もう一度当てて、削り切ろう。',
      // 前の課題（まとめて当てる）で傷だけ残っていることが多い。その敵が
      // そのまま教材になる。先に討ててしまっていれば、ここは素通りする。
      //
      // 体力を持つ敵が盤面から居なくなったら畳む。討ち取ったのなら覚えた
      // ことだし、そうでなくても、もう試しようがない。
      done: (c) =>
          c.felledWards.contains(TutorialScreen.toughWard) ||
          !c.board.foeCells.any((at) => c.board.tileAt(at)!.maxHp > 1),
    ),
    _Lesson(
      label: '毎ターンの反撃',
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
    // 開いた瞬間から出す。盤面が組み上がってからでないと道が引けないので、
    // 最初の1枚を描き終えてから。
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepHint());
  }

  @override
  void dispose() {
    _cheer?.cancel();
    _controller.removeListener(_check);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// 稽古場ではお手本を出しっぱなしにする。ここは覚えるための場所なので、
  /// 道を隠して考えさせる理由がない。なぞり始めれば消え（`beginPath`）、
  /// 指が離れてまた打てるようになれば戻る。
  ///
  /// 1度の通知につき1回しか出し直さない。[GameController.showHint] は道が
  /// 見つからなくても知らせるので、見つからないまま呼び続けると止まらなく
  /// なる。[_showingHint] はそのための歯止め。
  bool _showingHint = false;

  void _keepHint() {
    if (_showingHint || !mounted) return;
    // 通し終えたら片付ける。終いの言葉の裏で指が回り続ける理由はない。
    if (_finished) {
      _controller.clearHint();
      return;
    }
    // なぞっている最中に出すと、自分の指と重なって読めない。
    if (!_controller.acceptsInput || _controller.path.isNotEmpty) return;
    if (_controller.hintPath.isNotEmpty) return;
    _showingHint = true;
    _controller.showHint(pair: _lessons[_at].pairHint);
    _showingHint = false;
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
    _keepHint();
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
                  _Reach(controller: _controller),
                  _Gauges(controller: _controller),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (_cheering && !_finished)
            const IgnorePointer(child: Center(child: _Cheer())),
          if (_finished)
            _Finish(
              onDone: widget.onDone,
              learned: [for (final l in _lessons) l.label],
            ),
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

/// 盤面と目盛りの間に挟む物差し。**敵のマスの数字の意味は、ここで伝わる。**
///
/// 「数字は守り」と文で言っても、目の前の鎖とは結びつかない。なぞっている
/// 最中に、いまの鎖の威力と、通した敵の守りを並べて出す。1枚伸ばすたびに
/// 威力が増え、届いた瞬間に言葉も色も変わるので、**数字が越えるべき線である
/// ことが動きで分かる**。稽古場の一党は能力を持たない従者だけなので、
/// 威力＝枚数。数字と鎖の長さが1対1で対応する。
///
/// 守りの数字は盤面と同じチップで描く（[WardChip]）。ここだけの飾りを作ると、
/// マスに載っているあの数字の話だと分からない。
///
/// 高さは決め打ち。なぞるたびに伸び縮みすると盤面が動いて、指の下のマスが
/// ずれる。
class _Reach extends StatelessWidget {
  const _Reach({required this.controller});

  final GameController controller;

  /// 道が通っている敵のうち、いま話をすべき1体。まだ討てない中でいちばん
  /// 近いもの――伸ばせば届くところを見せたいので。全部討てるなら先頭。
  ///
  /// 2体ぶん並べると帯が詰まるうえ、どちらの数字の話か分からなくなる。
  Cell? get _focus {
    final board = controller.board;
    Cell? best;
    var bestNeed = 0;
    Cell? first;
    for (final c in controller.path) {
      final t = board.tileAt(c);
      if (t == null || !t.isFoe) continue;
      first ??= c;
      final need = t.powerToFell - controller.power;
      if (need > 0 && (best == null || need < bestNeed)) {
        best = c;
        bestNeed = need;
      }
    }
    return best ?? first;
  }

  /// 帯の下に添える一言。**数字だけ出しても読み方は伝わらない。**
  /// いまの状態に合わせて、何と何を見比べているのかを言葉で置く。
  String get _caption {
    if (controller.path.isEmpty) {
      return 'マスの数字は敵の守り。鎖の威力がその数に届けば傷がつく';
    }
    if (_focus == null) {
      return '敵のマスを通すと、その敵の守りと、届いているかが出る';
    }
    return '威力が守りの数字に届けば傷がつく。上回るほど深く削れる';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: DecoratedBox(
          decoration: panelDecoration(radius: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 26,
                  child: controller.path.isEmpty ? _idle() : _tracing(),
                ),
                // 狭い端末では縮めて収める。折り返すと帯の高さを越える。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _caption,
                    style: AppFont.label(9, color: Palette.textDim),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _idle() => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '鎖をなぞると、ここに威力が出る',
        style: AppFont.label(10, color: Palette.textMuted),
      ),
    ),
  );

  Widget _tracing() {
    final cell = _focus;
    final tile = cell == null ? null : controller.board.tileAt(cell);
    return Row(
      children: [
        Text('威力', style: AppFont.label(9)),
        const SizedBox(width: 6),
        Text(
          '${controller.power}',
          style: AppFont.number(
            18,
            color: controller.pathIsValid ? Palette.gold : Palette.textMuted,
          ),
        ),
        const Spacer(),
        if (tile == null)
          Text(
            '敵のマスを通すと、守りに届くか出る',
            style: AppFont.label(9, color: Palette.textDim),
          )
        else ...[
          Text('守り', style: AppFont.label(9, color: Palette.ward)),
          const SizedBox(width: 6),
          // 盤面のマスと同じチップ。一辺 64 のマスに載る大きさで描く。
          WardChip(ward: tile.ward!, size: 64, color: Palette.ward),
          const SizedBox(width: 10),
          Flexible(child: _verdict(cell!, tile)),
        ],
      ],
    );
  }

  /// いまの威力がその守りに何をするか。**討てる・傷がつく・届かない**の
  /// 3つしかない。届いていないときだけ、あと何枚かを言う。
  Widget _verdict(Cell cell, Tile tile) {
    final String text;
    final Color color;
    if (controller.willFell(cell)) {
      text = '討ち取れる';
      color = Palette.gold;
    } else if (controller.willHurt(cell)) {
      text = '傷がつく';
      color = Palette.evenA;
    } else {
      text = 'あと ${tile.powerToHurt - controller.power} 枚で届く';
      color = Palette.textMuted;
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: AppFont.label(10, color: color),
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

/// 通し終えたところ。
///
/// **ここをあっさり閉じると、覚えたことが残らない。** 何ができるように
/// なったのかを順に並べ直してから送り出す。並ぶ名札は課題そのものなので、
/// さっきまで自分でやっていたことがそのまま出てくる。
///
/// 盤面では教えられない編成の話だけ、最後にここで足す。
class _Finish extends StatefulWidget {
  const _Finish({required this.onDone, required this.learned});

  final VoidCallback onDone;
  final List<String> learned;

  @override
  State<_Finish> createState() => _FinishState();
}

class _FinishState extends State<_Finish> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _party = [MageKind.ember, MageKind.rime, MageKind.storm];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      // 名札を1つずつ点け、そのあと盤面で試せなかった話を2枚。
      duration: const Duration(milliseconds: 3000),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [from]〜[to] の区間を 0〜1 に均した進み具合。
  double _stage(double from, double to) =>
      Curves.easeOutCubic.transform(
        ((_c.value - from) / (to - from)).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final veil = _stage(0, 0.08);
        final title = _stage(0.05, 0.26);
        final dive = _stage(0.66, 0.78);
        final party = _stage(0.78, 0.90);
        final button = _stage(0.90, 1.0);
        return ColoredBox(
          color: Palette.background.withValues(alpha: 0.95 * veil),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 30,
                vertical: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: title,
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * title,
                      child: const _Crest(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (var i = 0; i < widget.learned.length; i++)
                    _Learned(
                      label: widget.learned[i],
                      // 1つずつ順に点く。全部まとめて出すと、何を覚えたのか
                      // 目が追えないまま終わる。
                      at: _stage(0.26 + i * 0.06, 0.38 + i * 0.06),
                    ),
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: dive,
                    child: Transform.translate(
                      offset: Offset(0, (1 - dive) * 12),
                      child: const _DiveNote(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: party,
                    child: Transform.translate(
                      offset: Offset(0, (1 - party) * 12),
                      child: _PartyNote(party: _party),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: button,
                    child: _DoneButton(onTap: widget.onDone),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 終いの紋。金の輪の中に一言。
class _Crest extends StatelessWidget {
  const _Crest();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Palette.gold.withValues(alpha: 0.65)),
        gradient: RadialGradient(
          colors: [
            Palette.gold.withValues(alpha: 0.22),
            Palette.boardBg.withValues(alpha: 0.2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Palette.gold.withValues(alpha: 0.3),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 16, 30, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ひととおり覚えた', style: AppFont.number(21, color: Palette.gold)),
            const SizedBox(height: 6),
            Text('READY', style: AppFont.label(10, color: Palette.textDim)),
          ],
        ),
      ),
    );
  }
}

/// 覚えたことを1つ。点くまでは沈めておく。
class _Learned extends StatelessWidget {
  const _Learned({required this.label, required this.at});

  final String label;

  /// 0 で沈んだまま、1 で点いた状態。
  final double at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: 0.15 + 0.85 * at,
        child: Transform.translate(
          offset: Offset((1 - at) * -14, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                // 点く瞬間だけ少し大きく出す。
                scale: 1 + (at < 1 ? at * (1 - at) * 1.6 : 0),
                child: Icon(
                  Icons.check_circle,
                  size: 19,
                  color: Color.lerp(Palette.textDim, Palette.life, at),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Color.lerp(Palette.textDim, Palette.textPrimary, at),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 盤面では試せない話その1。**階層・体力・手数。**
///
/// 手数切れの痛手は稽古場でわざと味わわせない（覚える前に落とされると、
/// 覚えたことごと投げられる）。だからここで言葉にして送り出す。
class _DiveNote extends StatelessWidget {
  const _DiveNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 階層は続く。盤面の画面と同じ呼び方で並べる。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right,
                        color: Palette.textDim,
                        size: 14,
                      ),
                    ),
                  Text(
                    'B${i + 1}F',
                    style: AppFont.number(
                      15,
                      color: i == 0 ? Palette.gold : Palette.textDim,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const _Body(
              'ダンジョンは階層が続く。**体力は持ち越し**で、\n'
              '制圧するたび祝福をひとつ選んで戻せる。\n'
              '手数が尽きると、討ち漏らした敵の守りぶんを浴びる。',
            ),
          ],
        ),
      ),
    );
  }
}

/// 盤面では教えられない編成の話。
class _PartyNote extends StatelessWidget {
  const _PartyNote({required this.party});

  final List<MageKind> party;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final kind in party)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: MagePortrait(kind: kind, size: 32),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward,
                  color: Palette.textDim,
                  size: 16,
                ),
                const SizedBox(width: 8),
                for (final kind in party)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: PhaseSwatch(phase: Mage.of(kind).phase, size: 22),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _Body(
              'あとひとつ。盤面に出る相は、\n'
              '**連れていった魔導士で決まる。**\n'
              '相は2種類以上でなければ、鎖が1枚も編めない。',
            ),
          ],
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
