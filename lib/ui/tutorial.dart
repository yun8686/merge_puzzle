import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/board.dart';
import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/phase.dart';
import 'board_view.dart';
import 'mage_art.dart';
import 'theme.dart';

/// 初回だけ出る遊び方。**読ませるのではなく、実際になぞらせる。**
///
/// 盤面は本物（`BoardView` と `GameController`）。継ぎ方の決まりも、威力の
/// 計算も、毎ターンの反撃も本番と同じものが動く。絵で説明してから本番で
/// 学び直させるより、最初から本物を触らせるほうが速いし、嘘が混ざらない。
///
/// **稽古はひとつずつ筋書きになっている。** 盤面を組み、なぞらせる道を1本
/// 用意し、その道以外はなぞれないようにする（[GameController.lockedPath]）。
/// 始まりのマスも次の1マスも決まっていて、全部なぞり切るまで鎖にならない。
/// 自由になぞらせていた頃は、たとえば「2体を通る鎖」を課題にしても、その形の
/// 道が盤面に無いことがあった。**教えたい形は、出してやらないと出ない。**
///
/// ## 稽古の筋書き
///
/// 目指すのは「1回目の潜りで、何が起きているか分かる」ところまで。
/// **覚えることを1つずつ積む**。前の稽古で作った盤面が、次の稽古の材料に
/// なるように並べてある。
///
/// 1. **鎖を編む** … 指でなぞって継ぐ。3枚で成立
/// 2. **長いほど強い** … 枚数がそのまま威力。6枚
/// 3. **守りを破る** … マスの数字は越えるべき線。守り3を討つ
/// 4. **まとめて当てる** … 1本の鎖は通った敵すべてに当たる。2体とも討つ
/// 5. **体力のある敵** … 守りは破れても討てない1体。粒が残りの体力
/// 6. **削り切る** … **同じ敵にもう一度**。つけた傷は残っている
/// 7. **一撃で討つ** … 守りを上回るほど深く削れる。威力6なら体力2も一撃
/// 8. **届かないとき** … 守り8には弾かれる。**それでもマナは消える**
/// 9. **並びを変えて討つ** … 降りてきたマスで8枚つながる。討ち取る
/// 10. **毎ターンの反撃** … 敵は毎手殴ってくる。残りを討ち果たす
///
/// 5〜7 は同じ相手（守り5・体力2）の三段。2本で削り切ってから、**同じ敵を
/// 1本で討てる威力**を見せる。8・9 も同じ相手（守り8）の二段で、**届かない
/// 手にも意味がある**ことと、盤面は崩せば変わることを続けて見せる。
///
/// **一度に1つだけ新しくする。** 4 で通る2体は守りも体力も同じにしてあり、
/// 2体とも討ち取れる。ここに体力持ちを混ぜると、片方だけ残った理由が
/// 分からないまま「まとめて当たった」ことまで疑わしくなる。体力の話は
/// 5・6 で、1体だけを相手に、**同じ敵へ二度当てさせて**見せる（道は横から
/// 縦へ変える。同じなのは道ではなく敵のほう）。
///
/// 盤面で試せないことだけ、終いの画面で言い添える（[_DiveNote] は階層と
/// 手数、[_PartyNote] は編成）。手数切れの痛手は**わざと味わわせない**。
/// 覚える前に落とされると、覚えたことごと投げられる。
///
/// 記録は読み書きしない。通し終えたことを [onDone] で知らせるだけで、印を
/// 付けて保存するのは拠点の仕事。
/// 稽古の種類。**出すきっかけが違うので、筋書きも別に持つ。**
enum TutorialCourse {
  /// 初めて遊ぶ人に。継ぎ方から毎ターンの反撃まで。
  basics,

  /// 初めて3色で潜る人に。巡回の決まりだけ。相が2つの間は継ぎ方が
  /// 「交互」1本で、2色だった頃と何も変わらない。3つ目を入れて初めて
  /// 効きはじめる決まりなので、そこで一度だけ教える。
  prism,
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    required this.onDone,
    this.controller,
    this.course = TutorialCourse.basics,
  });

  /// どの稽古を通すか。
  final TutorialCourse course;

  final VoidCallback onDone;

  /// 差し込むと、画面が自前で作る代わりにこれを使う。特定の局面から始めたい
  /// テスト用（`GameScreen` と同じ約束）。
  final GameController? controller;

  /// 1本では討ち切れない敵の守り。**体力の稽古の教材。** 体力2なので、
  /// 討ち取るには威力5の鎖を2本、または威力6の1本。
  static const int toughWard = 5;

  /// いまの道では届かない敵の守り。**盤面を崩す稽古の教材。**
  /// 8枚つなげば届くが、3枚では弾かれる。
  static const int thickWard = 8;

  /// 稽古場の階層。**ここに書いた敵は始まりの姿でしかない。**
  ///
  /// 稽古はひとつずつ盤面を組み直す（[_TutorialScreenState._paint]）ので、
  /// 置かれる敵も相の並びも稽古の側が決める。ここで要るのは手数だけ。
  /// たっぷり取ってあるのは、覚えるより先に手数で詰まらせないため。
  static const Dungeon dungeon = Dungeon(
    id: 'tutorial',
    name: '稽古場',
    floors: [
      FloorSpec([FoeSpec(3, atk: 1)], moves: 40),
    ],
  );

  /// 3色の稽古場。敵も相の並びも稽古の側が決めるので、ここで要るのは手数だけ。
  static const Dungeon prismDungeon = Dungeon(
    id: 'tutorial-prism',
    name: '稽古場',
    floors: [
      FloorSpec([FoeSpec(3, atk: 1)], moves: 30),
    ],
  );

  static Dungeon dungeonFor(TutorialCourse course) => switch (course) {
    TutorialCourse.basics => dungeon,
    TutorialCourse.prism => prismDungeon,
  };

  /// その稽古で連れる一党。**能力を持たない従者だけ。** 威力＝枚数になるので、
  /// 「6枚つなぐ」がそのまま「威力6」になって説明と食い違わない。
  /// 盤面に出る相は編成で決まるので、3色の稽古は従者3人で組む。
  static List<Mage> rosterFor(TutorialCourse course) => switch (course) {
    TutorialCourse.basics => const [Mage.squireHeat, Mage.squireCold],
    TutorialCourse.prism => const [
      Mage.squireHeat,
      Mage.squireCold,
      Mage.squireBolt,
    ],
  };

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

/// 稽古ひとつぶんに置く敵。
class _Foe {
  const _Foe(this.at, this.ward, {this.hp = 1});

  final Cell at;
  final int ward;
  final int hp;
}

/// 稽古ひとつ。**盤面を組み、なぞらせる道を1本だけ用意する。**
///
/// 道を決め打ちにしているので、教えたい形の鎖が必ず編まれる。自由になぞらせ
/// ていた頃は、たとえば「2体を通る鎖」を課題にしても、その形の道が盤面に
/// 無いことがあった。
class _Lesson {
  const _Lesson({
    required this.label,
    required this.text,
    required this.route,
    this.foes,
    this.shape,
    this.keepBoard = false,
  });

  /// 盤面をそのまま使う。**崩した結果を見せる稽古**だけが立てる。
  /// 敷き直すと、崩して並びが変わったことが伝わらない。
  final bool keepBoard;

  /// 終いの振り返りに並べる短い名札。
  final String label;

  /// 上に出す一言。`**` で挟んだところだけ明るくする。
  final String text;

  /// この稽古で置く敵。**null なら盤面の敵をそのまま引き継ぐ。**
  /// 前の稽古でつけた傷を持ち越すのに使う。
  final List<_Foe>? foes;

  /// 敷いたあとの手直し。**盤面を「詰まった形」にしたいときだけ使う。**
  /// 市松のままでは長い道がどこにでも通ってしまうので、そこを崩す稽古では
  /// これで相を揃えて袋小路を作る。
  final void Function(Board)? shape;

  /// なぞらせる道。敵は前の稽古の重力で落ちていることがあるので、
  /// マスを直に書くのではなく盤面から作る。
  final List<Cell> Function(Board) route;
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final GameController _controller;
  late final bool _ownsController;
  Timer? _cheer;
  int _at = 0;

  /// この稽古に入った時点の鎖の本数。増えたら道を辿り終えたということ。
  int _chainsAtEntry = 0;

  /// 課題が変わった直後だけ出す「できた」。
  bool _cheering = false;

  /// 横に1列ぶんの道。2色の盤面は市松なので、まっすぐでも折れても隣どうしで
  /// 相が入れ替わり、必ず成立する。
  static List<Cell> _row(int r, int from, int to) => [
    for (var c = from; c <= to; c++) Cell(r, c),
  ];

  /// 縦に1列ぶんの道。横と同じで、市松なら必ず成立する。
  static List<Cell> _col(int c, int from, int to) => [
    for (var r = from; r <= to; r++) Cell(r, c),
  ];

  /// 体力を持つ敵。前の稽古の重力で落ちていることがあるので、位置は盤面に訊く。
  static Cell _toughFoe(Board board) => board.foeCells.firstWhere(
    (c) => board.tileAt(c)!.maxHp > 1,
    orElse: () => board.foeCells.first,
  );

  /// その敵を**横から**通る5枚（「体力のある敵」）。列は6つ、道は5枚なので、
  /// 窓をどちらかに寄せれば必ずその敵を含められる。
  static List<Cell> _acrossTough(Board board) {
    final at = _toughFoe(board);
    final from = (at.col - 2).clamp(0, board.cols - 5);
    return _row(at.row, from, from + 4);
  }

  /// 同じ敵を**縦から**通る5枚（「削り切る」）。
  ///
  /// **道はわざと変えてある。** 教えたいのは「同じ道をもう一度なぞる」こと
  /// ではなく「**同じ敵にもう一度当てる**」ことなので、同じ形を出すと道の
  /// ほうを覚え直しているように見える。通る敵だけが同じ。
  static List<Cell> _downTough(Board board) {
    final at = _toughFoe(board);
    final from = (at.row - 2).clamp(0, board.rows - 5);
    return _col(at.col, from, from + 4);
  }

  /// 同じ敵を、列ぜんぶ使って**6枚**で通る（「一撃で討つ」）。
  /// 守り5に威力6なら削れるのは2つぶんなので、体力2でも1本で討ち切れる。
  static List<Cell> _oneShotTough(Board board) {
    final at = _toughFoe(board);
    return _row(at.row, 0, board.cols - 1);
  }

  /// 守りのいちばん厚い敵。位置は盤面に訊く。
  static Cell _thickFoe(Board board) {
    var best = board.foeCells.first;
    for (final at in board.foeCells) {
      if (board.tileAt(at)!.ward! > board.tileAt(best)!.ward!) best = at;
    }
    return best;
  }

  /// その敵を通る**3枚**（「届かないとき」）。威力3では守り8に弾かれるが、
  /// **通したマナは消える**。盤面を崩す手がこれ。
  static List<Cell> _shortAt(Board board) {
    final at = _thickFoe(board);
    final from = (at.col - 1).clamp(0, board.cols - 3);
    return _row(at.row, from, from + 2);
  }

  /// 崩したあとの盤面で、同じ敵を通る**8枚**（「並びを変えて討つ」）。
  ///
  /// 左右の列が1枚ぶん落ちて、敵の行から上へ折れられるようになっている。
  /// **盤面を敷き直さずに通る道**なので、崩して並びが変わったことがそのまま
  /// 手になる（[_pocket] が仕込んだ形）。
  static List<Cell> _aroundThick(Board board) {
    final at = _thickFoe(board);
    final r = at.row;
    final c = at.col;
    return [
      Cell(r - 2, c - 2),
      Cell(r - 2, c - 1),
      Cell(r - 1, c - 1),
      Cell(r, c - 1),
      at,
      Cell(r, c + 1),
      Cell(r - 1, c + 1),
      Cell(r - 2, c + 1),
    ];
  }

  /// 1マスだけ相を塗り替える。敵のマスには触らない。
  static void _repaintAt(Board board, int r, int c, Phase phase) {
    if (r < 0 || r >= board.rows || c < 0 || c >= board.cols) return;
    final tile = board.grid[r][c];
    if (tile == null || tile.isFoe) return;
    board.grid[r][c] = Tile(id: tile.id, phase: phase);
  }

  /// 守りの厚い敵のまわりを**袋小路**にする（「届かないとき」）。
  ///
  /// 市松のままだと8枚の道がすでに通っていて、崩す意味が無い。敵の居る行を
  /// 通り道として残し、**その上下と行の先を同じ相で塞ぐ**。同じ相は続けて
  /// 継げないので、鎖は行から出られず、どう編んでも5枚止まりになる。
  ///
  /// 塞ぐのは敵のまわりだけ。ほかの場所は市松のままにしておく。盤面ぜんぶを
  /// 手詰まりにすると、1手のあとに階層が落ちて稽古がやり直しになる。
  static void _pocket(Board board) {
    final at = _thickFoe(board);
    final row = at.row;
    final phases = board.phases;
    Phase along(int c) => phases[(row + c) % phases.length];
    Phase other(int c) => phases[(row + c + 1) % phases.length];

    // 通り道は行の端まで。最後の1列は塞ぐのに使う。
    final last = board.cols - 2;
    for (var c = 0; c <= last; c++) {
      _repaintAt(board, row - 1, c, along(c));
      _repaintAt(board, row + 1, c, along(c));
    }
    _repaintAt(board, row, board.cols - 1, along(last));

    // 崩したあとに降りてくる2列ぶんを仕込む。
    //
    // **塞ぎを消しただけでは、上から同じ相が降りてきて塞がったままになる。**
    // 敵の左右の列だけ、上2枚を先に入れ替えておく。1枚ぶん落ちると、そこに
    // 上へ折れる道ができて、[_aroundThick] の8枚が通るようになる。
    for (final c in [at.col - 1, at.col + 1]) {
      _repaintAt(board, row - 2, c, other(c));
      _repaintAt(board, row - 3, c, along(c));
    }
  }

  late final List<_Lesson> _lessons = switch (widget.course) {
    TutorialCourse.basics => _basics,
    TutorialCourse.prism => _prism,
  };

  /// 初めて遊ぶ人の筋書き。
  static final List<_Lesson> _basics = [
    _Lesson(
      label: '鎖を編む',
      text: '隣り合うマスを指でなぞって継ぐ。\n'
          '**同じ相（色）は続けて継げない。**\n'
          '光っている道を3枚なぞろう。',
      foes: const [_Foe(Cell(1, 4), 3)],
      route: (b) => _row(5, 1, 3),
    ),
    _Lesson(
      label: '長いほど強い',
      text: '継いだ枚数が、そのまま鎖の**威力**になる。\n'
          '下の帯に出ているのが、いまの威力。\n'
          '今度は6枚つないでみよう。',
      foes: const [_Foe(Cell(1, 4), 3)],
      route: (b) => _row(5, 0, 5),
    ),
    _Lesson(
      label: '守りを破る',
      text: 'マスに書かれた数字は、その敵の**守り**。\n'
          '威力がその数に届けば、傷がつく。\n'
          '守り3の敵を、3枚の鎖で討ち取ろう。',
      foes: const [_Foe(Cell(5, 3), 3), _Foe(Cell(1, 1), 3)],
      route: (b) => _row(5, 1, 3),
    ),
    _Lesson(
      label: 'まとめて当てる',
      text: '1本の鎖は、**通った敵すべて**に当たる。\n'
          '離れた敵どうしも、道でつなげば一度に討てる。\n'
          '2体を通る道をなぞろう。',
      // **2体とも同じ守り3・体力1にしておく。** 片方だけ残ると、なぜ残ったのか
      // が分からないまま「まとめて当たった」ことまで疑わしくなる。体力の話は
      // 次の稽古で、1体だけを相手にして分ける。
      // 控えの1体は、盤面を空にしないために置いてある。
      foes: const [
        _Foe(Cell(6, 1), 3),
        _Foe(Cell(4, 3), 3),
        _Foe(Cell(0, 0), 3),
      ],
      route: (b) => const [
        Cell(6, 1),
        Cell(6, 2),
        Cell(6, 3),
        Cell(5, 3),
        Cell(4, 3),
      ],
    ),
    _Lesson(
      label: '体力のある敵',
      text: 'この敵は**体力を2つ持っている**。\n'
          'マスの下の粒が、その残り。\n'
          '威力5を当てて、1つ削ろう。',
      // 1体だけを相手にする。守りは破れているのに討てない、という一度きりの
      // 出来事を、他の敵と混ぜずに見せる。
      foes: const [
        _Foe(Cell(4, 3), TutorialScreen.toughWard, hp: 2),
        _Foe(Cell(0, 0), 3),
      ],
      route: _acrossTough,
    ),
    _Lesson(
      label: '削り切る',
      text: '**つけた傷はそのまま残る。**\n'
          '粒が1つ減っているはず。\n'
          '同じ敵にもう一度当てて、討ち取ろう。',
      // 敵は置き直さない。さっき傷をつけた敵が、そのまま教材になる。
      // 道は縦に変えてある。同じなのは道ではなく敵のほう。
      route: _downTough,
    ),
    _Lesson(
      label: '一撃で討つ',
      text: '威力が守りを**上回るほど深く削れる**。\n'
          '守り5に威力6なら、2つぶん。\n'
          '6枚つないで、体力2を一撃で討とう。',
      foes: const [
        _Foe(Cell(4, 3), TutorialScreen.toughWard, hp: 2),
        _Foe(Cell(0, 0), 3),
      ],
      route: _oneShotTough,
    ),
    _Lesson(
      label: '届かないとき',
      text: '守り8。まわりは同じ相で塞がっていて、\n'
          '**この敵には5枚までしかつなげない。**\n'
          '届かなくても、通したマナのマスは消える。',
      foes: const [
        _Foe(Cell(4, 2), TutorialScreen.thickWard),
        _Foe(Cell(0, 0), 3),
      ],
      shape: _pocket,
      route: _shortAt,
    ),
    _Lesson(
      label: '並びを変えて討つ',
      text: '降りてきたマスで、並びが変わった。\n'
          '**今度は8枚つなげる。**\n'
          '威力8なら守り8に届く。討ち取ろう。',
      // **盤面は敷き直さない。** 崩した並びをそのまま使う。敷き直すと、
      // 崩して変わったことが伝わらない。
      keepBoard: true,
      route: _aroundThick,
    ),
    _Lesson(
      label: '毎ターンの反撃',
      text: '**敵は毎ターン殴ってくる。**\n'
          '体力が減るのはそのため。早く討つほど楽になる。\n'
          '残った敵を討ち取ろう。',
      foes: const [_Foe(Cell(3, 2), 3)],
      route: (b) => _row(3, 0, 2),
    ),
  ];

  /// 3色で初めて潜る人の筋書き。
  ///
  /// 3色の盤面は `phases[(r + c) % 3]` で敷いてあるので、**右か下へ進めば
  /// 相が 熱→冷→雷→熱… と回り、上か下へ折り返せば2色で往復する**。
  /// この2つの形が、そのまま2本立ての決まりに対応している。
  ///
  ///  - 右上へ階段（右・上・右・上…）… 使う相は2つ。**交互**で成立する
  ///  - 右下へ階段（右・下・右・下…）… 3色を順に踏む。**巡回**で成立する
  static final List<_Lesson> _prism = [
    _Lesson(
      label: '2色なら今までどおり',
      text: '3つ目の相が盤面に出ている。\n'
          'それでも**使う相が2つだけなら**、\n'
          'これまでどおり交互に継げる。',
      foes: const [_Foe(Cell(0, 0), 3)],
      route: (b) => const [
        Cell(5, 1),
        Cell(5, 2),
        Cell(4, 2),
        Cell(4, 3),
        Cell(3, 3),
      ],
    ),
    _Lesson(
      label: '3つ目を踏む',
      text: '3つ目の相を踏むと、決まりが入れ替わる。\n'
          '**直前2枚と同じ相は継げない。**\n'
          '3色を順に踏む道をなぞろう。',
      foes: const [_Foe(Cell(0, 0), 3)],
      route: (b) => const [
        Cell(2, 1),
        Cell(2, 2),
        Cell(3, 2),
        Cell(3, 3),
        Cell(4, 3),
        Cell(4, 4),
      ],
    ),
    _Lesson(
      label: '巡って長く編む',
      text: '同じ相に戻らないぶん、**巡回は長く伸びる**。\n'
          '長い鎖ほど、厚い守りを破れる。\n'
          '7枚つないで、守り6の敵を討ち取ろう。',
      foes: const [_Foe(Cell(4, 3), 6)],
      route: (b) => const [
        Cell(1, 0),
        Cell(1, 1),
        Cell(2, 1),
        Cell(2, 2),
        Cell(3, 2),
        Cell(3, 3),
        Cell(4, 3),
      ],
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
          dungeon: TutorialScreen.dungeonFor(widget.course),
          roster: TutorialScreen.rosterFor(widget.course),
        );
    _controller.addListener(_check);
    // 最初の稽古の盤面をここで組む。描く前なので知らせる必要はない。
    _enterScene();
  }

  @override
  void dispose() {
    _cheer?.cancel();
    _controller.removeListener(_check);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// 稽古の盤面を組む。マナを敷き直し、[foes] があれば敵を置き直す。
  ///
  /// 相は `phases[(r + c) % 相の数]` で置く。**2色なら市松**で、上下左右
  /// どちらへ進んでも相が入れ替わる。**3色なら斜めの縞**で、右か下へ進めば
  /// 相が順に回り（巡回）、右・上と折り返せば2色で往復する（交互）。どちらの
  /// 決まりで編む道も引けるのはこのため。鎖を1本編むたびに重力と補充で並びが
  /// 崩れるので、稽古ごとに敷き直す。
  ///
  /// [foes] が null なら敵はそのまま残す。**前の稽古でつけた傷を持ち越す**
  /// ための逃げ道で、「削って討つ」がこれを使う。
  void _paint(List<_Foe>? foes) {
    final board = _controller.board;
    final phases = board.phases;
    final n = phases.length;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final tile = board.grid[r][c];
        if (tile == null) continue;
        if (foes == null && tile.isFoe) continue;
        board.grid[r][c] = Tile(id: tile.id, phase: phases[(r + c) % n]);
      }
    }
    if (foes == null) return;
    for (final foe in foes) {
      final base = board.grid[foe.at.row][foe.at.col]!;
      board.grid[foe.at.row][foe.at.col] = Tile(
        id: base.id,
        phase: base.phase,
        ward: foe.ward,
        hp: foe.hp,
      );
    }
  }

  /// いまの稽古の盤面と道を用意する。**知らせない**――呼ぶのは組み上がる前
  /// か、誰かの通知の途中なので、そのまま描き直される。
  void _enterScene() {
    final lesson = _lessons[_at];
    if (!lesson.keepBoard) {
      _paint(lesson.foes);
      lesson.shape?.call(_controller.board);
    }
    final route = lesson.route(_controller.board);
    _controller.lockedPath = route;
    // お手本は決めた道そのもの。探すまでもない。
    _controller.hintPath = route;
    _chainsAtEntry = _controller.chains;
  }

  /// お手本は出しっぱなし。ここは覚えるための場所なので、道を隠して
  /// 考えさせる理由がない。なぞり始めれば消え（`beginPath`）、指が離れて
  /// また打てるようになれば戻る。
  void _keepHint() {
    if (_finished) {
      _controller.hintPath = const [];
      return;
    }
    // なぞっている最中に出すと、自分の指と重なって読めない。
    if (!_controller.acceptsInput || _controller.path.isNotEmpty) return;
    _controller.hintPath = _controller.lockedPath;
  }

  void _check() {
    if (!mounted || _finished) return;
    // 倒れても手数が尽きても、稽古場なので黙って組み直す。ここで躓かせると
    // 覚える前に投げられる。
    if (_controller.phase == GamePhase.floorLost ||
        _controller.phase == GamePhase.defeated) {
      _controller.enterDungeon(TutorialScreen.dungeonFor(widget.course));
      _enterScene();
      return;
    }
    // 盤面から敵が居なくなったら終い。最後の稽古で討ち果たしたところ。
    if (_controller.remainingFoes == 0) {
      _cheer?.cancel();
      setState(() {
        _at = _lessons.length;
        _cheering = false;
      });
      return;
    }
    // 決めた道を辿り終えたら次の稽古へ。盤面を組み直すのは、反撃まで
    // 終わって手が戻ってきてから（[GameController.acceptsInput]）。
    if (_controller.chains > _chainsAtEntry && _controller.acceptsInput) {
      _advance();
      return;
    }
    _keepHint();
  }

  void _advance() {
    _cheer?.cancel();
    setState(() {
      _at++;
      // 終いの言葉が出るところでは重ねない。
      _cheering = !_finished;
    });
    if (_finished) return;
    _cheer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _cheering = false);
    });
    _enterScene();
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
              course: widget.course,
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
  const _Finish({
    required this.onDone,
    required this.course,
    required this.learned,
  });

  final VoidCallback onDone;
  final TutorialCourse course;
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
      duration: const Duration(milliseconds: 3400),
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
        final dive = _stage(0.68, 0.79);
        final party = _stage(0.79, 0.90);
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
                      child: _Crest(
                        text: widget.course == TutorialCourse.basics
                            ? 'ひととおり覚えた'
                            : '3色を覚えた',
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (var i = 0; i < widget.learned.length; i++)
                    _Learned(
                      label: widget.learned[i],
                      // 1つずつ順に点く。全部まとめて出すと、何を覚えたのか
                      // 目が追えないまま終わる。
                      at: _stage(0.20 + i * 0.04, 0.32 + i * 0.04),
                    ),
                  const SizedBox(height: 26),
                  // 盤面では試せない話だけを、送り出す前に言い添える。
                  // 3色の稽古はそこだけ差し替える。
                  if (widget.course == TutorialCourse.basics) ...[
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
                  ] else
                    Opacity(
                      opacity: party,
                      child: Transform.translate(
                        offset: Offset(0, (1 - party) * 12),
                        child: const _PrismNote(),
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
  const _Crest({required this.text});

  final String text;

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
            Text(text, style: AppFont.number(21, color: Palette.gold)),
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

/// 3色の稽古の締め。**なぜ3色にするのか**を、盤面と同じ色で言い添える。
///
/// 巡回は長く伸びるぶん、厚い守りに届く。雷の魔導士が落ちるのも3色のときだけ
/// で、盤面では試せない（稽古場の一党は能力を持たない従者だけなので）。
class _PrismNote extends StatelessWidget {
  const _PrismNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 盤面と同じ色・同じ形。ここだけの飾りを作ると繋がらない。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final phase in Phase.values) ...[
                  if (phase != Phase.values.first)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        Icons.chevron_right,
                        color: Palette.textDim,
                        size: 14,
                      ),
                    ),
                  PhaseSwatch(phase: phase, size: 22),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const _Body(
              '3色の盤面は、**巡って編めば長く伸びる**。\n'
              '長い鎖ほど、厚い守りに届く。\n'
              '雷の魔導士は、3色の盤面でだけ雷を落とす。',
            ),
          ],
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
              '削られたぶんは戻らない。早く討つほど楽になる。\n'
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
