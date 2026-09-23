import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/dungeon.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/phase.dart';

/// 盤面を奇数・偶数の市松に塗り直す。どの方向にも繋がる状態になる。
/// [foe] を指定すると、そのマスだけ敵にする。
void paintCheckerboard(
  Board board, {
  Cell? foe,
  int ward = 8,
  int hp = 1,
}) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final isHere = foe != null && foe.row == r && foe.col == c;
      board.grid[r][c] = Tile(
        id: id++,
        phase: (r + c).isEven ? Phase.red : Phase.blue,
        ward: isHere ? ward : null,
        hp: isHere ? hp : 1,
      );
    }
  }
}

/// 盤面を1色で塗り潰して、**どこへも繋げない状態**にする。
/// [foe] のマスだけ敵にして、制圧扱いにならないようにしておく。
///
/// 反撃のあとでこの形なら、盤面が敷き直される（[Board.reshuffle]）。
void paintDead(
  Board board, {
  required Cell foe,
  int ward = 8,
  int hp = 1,
}) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final isHere = foe.row == r && foe.col == c;
      board.grid[r][c] = Tile(
        id: id++,
        phase: Phase.red,
        ward: isHere ? ward : null,
        hp: isHere ? hp : 1,
      );
    }
  }
}

/// 盤面が詰んだところから、反撃までを通す。
void strikeThrough(GameController controller) {
  controller.isSettling = true;
  controller.settle();
  controller.strike();
}

GameController newController([int seed = 3]) =>
    GameController(rng: Random(seed), roster: twoPhases);

/// 赤と青の2相だけの一党。この2色なら「直前1枚と違う」＝交互で、
/// 相を入れる前の盤面と規則も手触りも変わらない。市松の盤面を
/// 決め打ちで置くテストは、この2相を前提にしている。
const twoPhases = [Mage.squireRed, Mage.squireBlue];

/// 同じ2相を、見習いではなく焔と氷雨で揃えた一党。焔の補正（赤3枚で威力 +1）を
/// 見たいテストはこちらを連れていく。
const emberPair = [Mage.ember, Mage.rime];

GameController emberController([int seed = 3]) =>
    GameController(rng: Random(seed), roster: emberPair);

/// 3相の一党。雷のように3色の盤面を要る能力は、これで確かめる。
const threePhases = [Mage.squireRed, Mage.squireBlue, Mage.squireViolet];

GameController prismController([int seed = 3]) =>
    GameController(rng: Random(seed), roster: threePhases);

/// 盤面を3相の斜め縞に塗る。相は (r + c) を 3 で割った余りで決まる。
///
/// 3相の決まりは「直前2枚と違う」なので、市松では繋がらない。この縞なら
/// 右・下へ1歩ずつ進むかぎり相が 赤→青→紫→赤… と回り、条件を満たし続ける。
/// 折り返し（右に進んでから左に戻る）は余りが 0 に戻って繋がらないので、
/// 曲がるときは下へ降りること。
void paintPrism(Board board, {Cell? foe, int ward = 8, int hp = 1}) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final isHere = foe != null && foe.row == r && foe.col == c;
      board.grid[r][c] = Tile(
        id: id++,
        phase: Phase.values[(r + c) % 3],
        ward: isHere ? ward : null,
        hp: isHere ? hp : 1,
      );
    }
  }
}

/// 3相の盤面で8枚継ぐ道。上段を右へ6枚、そこから下へ2枚。
const boltPath = [
  Cell(0, 0),
  Cell(0, 1),
  Cell(0, 2),
  Cell(0, 3),
  Cell(0, 4),
  Cell(0, 5),
  Cell(1, 5),
  Cell(2, 5),
];

/// なぞって離す。
void trace(GameController controller, List<Cell> path) {
  controller.beginPath(path.first);
  for (final c in path.skip(1)) {
    controller.extendPath(c);
  }
}

void main() {
  test('なぞって離すと点が入り、settle で盤面が補充される', () {
    final controller = newController();
    // 敵は盤面の隅に、届かない守りで置いておく。
    // 階層が即制圧にならないようにするため。
    paintCheckerboard(controller.board, foe: const Cell(7, 5));

    const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
    controller.beginPath(path.first);
    for (final c in path.skip(1)) {
      expect(controller.extendPath(c), isTrue);
    }
    expect(controller.pathLength, 3);

    final result = controller.commitPath();
    expect(result, isNotNull);
    expect(controller.score, greaterThan(0));
    expect(controller.path, isEmpty);

    // 消える演出を見せている間、盤面は穴が開いたまま止まっている。
    final board = controller.board;
    expect(controller.isSettling, isTrue);
    expect(controller.acceptsInput, isFalse);
    for (final c in path) {
      expect(board.tileAt(c), isNull);
    }

    controller.settle();
    controller.strike();
    expect(controller.isSettling, isFalse);
    expect(controller.phase, GamePhase.playing);
    expect(controller.acceptsInput, isTrue);
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        expect(board.grid[r][c], isNotNull);
      }
    }
  });

  test('成立しないパスでは何も起きない', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));

    // 2枚しか繋いでいないので成立しない。
    trace(controller, const [Cell(0, 0), Cell(0, 1)]);
    expect(controller.commitPath(), isNull);

    expect(controller.score, 0);
    expect(controller.chains, 0);
    expect(controller.path, isEmpty);
  });

  test('敵を全部討つと階層を制圧する', () {
    final controller = newController();
    // 威力3で討てる敵をパス上に置く。
    paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
    expect(controller.remainingFoes, 1);

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    final result = controller.commitPath();
    expect(result!.felled, 1);

    controller.settle();
    controller.strike();
    expect(controller.remainingFoes, 0);
    expect(controller.phase, GamePhase.stageCleared);
    expect(controller.acceptsInput, isFalse);
  });

  group('毎ターンの反撃', () {
    test('残っている敵の攻撃力ぶんだけ毎ターン削られる', () {
      final controller = newController();
      // 守り6（攻撃力2）の敵を、鎖から離れた隅に置く。
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      final hpBefore = controller.party.hp;

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      expect(controller.party.hp, hpBefore, reason: '殴られるのは settle のとき');

      controller.settle();
      controller.strike();
      expect(controller.lastHit, 2);
      expect(controller.party.hp, hpBefore - 2);
      expect(controller.phase, GamePhase.playing);

      // 次の手でも同じだけ削られる。
      trace(controller, const [Cell(2, 0), Cell(2, 1), Cell(2, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();
      expect(controller.party.hp, hpBefore - 4);
    });

    test('攻撃力は守りの厚さから決まる', () {
      expect(Board.attackFor(3), 1);
      expect(Board.attackFor(5), 1);
      expect(Board.attackFor(6), 2);
      expect(Board.attackFor(8), 2);
    });

    test('攻撃力は盤面から合計で読める', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 8);
      expect(controller.board.foeAttack, 2);
      // 守りと違って、攻撃力は手で上書きできる。
      final board = Board(
        phases: const [Phase.red, Phase.blue],
        rng: Random(1),
      );
      board.buildStage(foes: const [FoeSpec(3, atk: 9), FoeSpec(3)]);
      expect(board.foeAttack, 9 + 1);
    });

    test('討ち果たした手は殴られない', () {
      final controller = newController();
      // 威力3で討てる敵を1体だけ。討った瞬間に制圧になる。
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      final hpBefore = controller.party.hp;

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.remainingFoes, 0);
      expect(controller.lastHit, 0);
      expect(controller.party.hp, hpBefore, reason: '制圧した手で減らない');
    });

    test('毎ターンの反撃だけでも全滅する', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      controller.party.hp = 2;

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.party.hp, 0);
      expect(controller.phase, GamePhase.defeated);
    });

    test('盤面が詰んでも、すぐには殴られない', () {
      // 消した瞬間に反撃が始まると、自分の手と相手の手が重なって読めない。
      // 詰んだ盤面を見せてから殴る。間を計るのは盤面を描く側。
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      final hpBefore = controller.party.hp;

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();

      expect(controller.isStriking, isTrue);
      expect(controller.party.hp, hpBefore, reason: 'まだ殴られていない');
      expect(controller.acceptsInput, isFalse, reason: '殴られる前に打たせない');

      controller.strike();
      expect(controller.isStriking, isFalse);
      expect(controller.party.hp, hpBefore - 2);
      expect(controller.acceptsInput, isTrue);
    });

    test('反撃は二度来ない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      final hpBefore = controller.party.hp;

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();
      controller.strike();
      controller.strike();

      expect(controller.party.hp, hpBefore - 2);
      expect(controller.hitTick, 1);
    });

    test('制圧した手では反撃を待たない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();

      expect(controller.isStriking, isFalse);
      expect(controller.phase, GamePhase.stageCleared);
    });

    test('痛手を受けた回数が数えられる', () {
      // 演出はこれが変わったのを見て走り出す。量だけを見ていると、同じ量が
      // 続けて来たときに2回目が鳴らない。
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      expect(controller.hitTick, 0);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();
      expect(controller.hitTick, 1);

      // 同じ量の痛手でも数は進む。
      trace(controller, const [Cell(2, 0), Cell(2, 1), Cell(2, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();
      expect(controller.lastHit, 2, reason: '量は同じ');
      expect(controller.hitTick, 2);
    });

    test('制圧した手では痛手の回数が進まない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.remainingFoes, 0);
      expect(controller.hitTick, 0);
    });

    test('敵を討つほど毎ターンの痛手が減る', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      // 守り6の敵をもう1体、鎖から離して置く。
      controller.board.grid[7][5] = Tile(
        id: 999,
        phase: controller.board.grid[7][5]!.phase,
        ward: 6,
      );
      expect(controller.board.foeAttack, 1 + 2);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.remainingFoes, 1, reason: '守り3の方を討った');
      expect(controller.lastHit, 2, reason: '討った敵のぶんはもう来ない');
    });
  });

  test('手数はダンジョンを通して数え、入り直すと戻る', () {
    // ★の「手数以内」に使う。階層ごとに戻る chains とは別に数える。
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();
    expect(controller.phase, GamePhase.stageCleared);
    expect(controller.moves, 1);

    controller.nextFloor();
    expect(controller.chains, 0, reason: '階層ごとの本数は戻る');
    expect(controller.moves, 1, reason: '手数は持ち越す');

    paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 8);
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    expect(controller.moves, 2);

    controller.enterDungeon(controller.dungeon);
    expect(controller.moves, 0);
  });

  group('手詰まり', () {
    test('階層を落とさず、敵を残して盤面を敷き直す', () {
      // 負けるのは体力が尽きたときだけ。盤面の運で詰んでも続けられる。
      final controller = newController();
      paintDead(controller.board, foe: const Cell(7, 5), ward: 6, hp: 2);
      expect(controller.board.hasAnyChain(), isFalse);
      final floor = controller.floor;
      final hpBefore = controller.party.hp;
      final cells = controller.board.rows * controller.board.cols;

      strikeThrough(controller);

      expect(controller.phase, GamePhase.playing);
      expect(controller.floor, floor, reason: '深さは変わらない');
      expect(controller.acceptsInput, isTrue);
      expect(controller.board.hasAnyChain(), isTrue);
      expect(controller.board.foeCells, [const Cell(7, 5)], reason: '敵はその場に');
      final foe = controller.board.tileAt(const Cell(7, 5))!;
      expect(foe.ward, 6);
      expect(foe.hp, 2, reason: '傷もそのまま');
      // 上乗せは無い。その手ぶんの毎ターンの攻撃だけ。
      expect(controller.party.hp, hpBefore - Board.attackFor(6));
      // 敵のほかは全部降り直してくる。
      expect(controller.freshTileIds.length, cells - 1);
      expect(controller.reshuffles, 1);
      expect(controller.reshuffled, isTrue);
    });

    test('敷き直したという知らせは、なぞり始めると消える', () {
      final controller = newController();
      paintDead(controller.board, foe: const Cell(7, 5), ward: 6);
      strikeThrough(controller);
      expect(controller.reshuffled, isTrue);

      controller.beginPath(const Cell(0, 0));
      expect(controller.reshuffled, isFalse);
      expect(controller.reshuffles, 1, reason: '回数は残る');
    });

    test('その手の攻撃で倒れたなら、敷き直さずに全滅', () {
      final controller = newController();
      paintDead(controller.board, foe: const Cell(7, 5), ward: 6);
      controller.party.hp = Board.attackFor(6);

      strikeThrough(controller);

      expect(controller.party.isDown, isTrue);
      expect(controller.phase, GamePhase.defeated);
      expect(controller.reshuffles, 0);
    });

    test('つなげる手があるうちは敷き直さない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      strikeThrough(controller);
      expect(controller.reshuffles, 0);
      expect(controller.reshuffled, isFalse);
    });
  });

  test('守りに届かない敵は傷もつかず、手数だけが減る', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 8);

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);

    // 巻き込んではいるが、威力 3 では守り 8 に 5 足りない。
    expect(controller.willFell(const Cell(0, 1)), isFalse);
    expect(controller.willHurt(const Cell(0, 1)), isFalse);
    expect(controller.tilesToNextFoe, 5);
    expect(controller.pendingFelled, 0);

    final result = controller.commitPath();
    expect(result!.felled, 0);
    expect(result.cleared, [true, false, true]);

    controller.settle();
    controller.strike();
    expect(controller.remainingFoes, 1);
    expect(controller.phase, GamePhase.playing);
  });

  test('威力が届けば willFell が立つ', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 4);

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    expect(controller.willFell(const Cell(0, 1)), isFalse);
    expect(controller.tilesToNextFoe, 1);

    // 4枚目を繋ぐと届く。
    controller.extendPath(const Cell(0, 3));
    expect(controller.willFell(const Cell(0, 1)), isTrue);
    expect(controller.tilesToNextFoe, 0);
    expect(controller.pendingFelled, 1);
  });

  test('討てない敵でも、守りを上回っていれば体力は削れる', () {
    final controller = newController();
    paintCheckerboard(
      controller.board,
      foe: const Cell(0, 1),
      ward: 3,
      hp: 3,
    );

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    expect(controller.willFell(const Cell(0, 1)), isFalse);
    expect(controller.willHurt(const Cell(0, 1)), isTrue);

    final result = controller.commitPath();
    expect(result!.felled, 0);
    expect(result.damages[1], 1);
    controller.settle();
    controller.strike();
    expect(controller.remainingFoes, 1);
    // 消えたのは左右のマナだけなので、敵は同じマスに傷ついたまま残る。
    final foe = controller.board.tileAt(const Cell(0, 1))!;
    expect(foe.hp, 2);
    expect(foe.maxHp, 3);
  });

  group('討った敵の記録', () {
    test('討ち取った敵の守りが階層ごとに積まれる', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      expect(controller.felledWards, isEmpty);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      expect(controller.felledWards, [3]);
    });

    test('弾かれた敵は積まれない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 8);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      expect(controller.felledWards, isEmpty);
    });

    test('雷で討った敵も積まれる', () {
      final controller = prismController();
      controller.party.members.add(Mage.storm);
      paintPrism(controller.board, foe: const Cell(7, 5), ward: 6);

      trace(controller, boltPath);
      controller.commitPath();
      expect(controller.felledWards, [6]);
    });

    test('階層が変わると空に戻る', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();
      expect(controller.felledWards, [3]);

      controller.nextFloor();
      expect(controller.felledWards, isEmpty);
    });

    test('討ち漏らした敵の守りは盤面から読める', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      expect(controller.board.foeWards, [6]);
    });
  });

  group('一党', () {
    test('体力は連れていく顔ぶれの合計', () {
      // 力のある者ほど薄い。厚さを取るか力を取るかが編成の判断に乗る。
      expect(Mage.squireRed.hp, greaterThan(Mage.blaze.hp));
      expect(Mage.squireRed.hp, greaterThan(Mage.storm.hp));

      expect(
        Party.poolFor(const [Mage.squireRed, Mage.squireBlue]),
        Mage.squireHp * 2,
      );
      // 3人目を入れれば厚くなる（そのぶん盤面は3色になる）。
      expect(
        Party.poolFor(Mage.squires),
        greaterThan(Party.poolFor(const [Mage.squireRed, Mage.squireBlue])),
      );

      final controller = GameController(
        rng: Random(1),
        roster: const [Mage.aegis, Mage.rime],
      );
      expect(controller.party.maxHp, Mage.aegis.hp + Mage.rime.hp);
    });

    test('一党は連れてきた顔ぶれそのままで始まる', () {
      final controller = newController();
      expect(controller.party.members, twoPhases);
      // 体力は連れてきた顔ぶれの合計。見習い2人なら 45 + 45。
      expect(controller.party.hp, Party.poolFor(twoPhases));
      expect(controller.party.hp, Mage.squireHp * 2);
    });

    test('焔は赤を3枚以上継いだ鎖に威力を1足す', () {
      final controller = emberController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // 赤（奇数）は (0,0) (0,2) の2枚だけ。まだ乗らない。
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      expect(controller.powerBonus, 0);
      expect(controller.power, 3);

      // 5枚まで伸ばすと赤が3枚になる。
      controller.extendPath(const Cell(0, 3));
      controller.extendPath(const Cell(0, 4));
      expect(controller.powerBonus, 1);
      expect(controller.power, 6);
    });

    test('焔が居なければ補正は乗らない', () {
      final controller = newController();
      controller.party.members.clear();
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
      ]);
      expect(controller.powerBonus, 0);
      expect(controller.power, 5);
    });

    test('氷雨は青を3枚以上継いだ鎖で体力を戻す', () {
      final controller = newController();
      controller.party.members.add(Mage.rime);
      controller.party.hp = 10;
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // (0,1) (0,3) (0,5) が青（偶数）。
      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
      ]);
      controller.commitPath();
      expect(controller.lastHealed, rimeMend);
      expect(controller.party.hp, 10 + rimeMend);
    });

    test('体力は最大を超えない', () {
      final party = Party.initial();
      expect(party.heal(5), 0);
      expect(party.hp, Party.poolFor(Mage.squires));
    });

    test('雷は3色の盤面で8枚継いだ鎖で階層の敵すべてを削る', () {
      final controller = prismController();
      controller.party.members.add(Mage.storm);
      // 守り8の敵を、鎖から離れた隅に置く。
      paintPrism(controller.board, foe: const Cell(7, 5));

      trace(controller, boltPath);
      expect(controller.pathLength, stormChain);

      final result = controller.commitPath();
      // 鎖は敵に触れていないのに、雷で落ちている。
      expect(result!.bolt.length, 1);
      expect(result.bolt.first.cell, const Cell(7, 5));
      expect(result.felled, 1);
      expect(controller.board.remainingFoes, 0);
      // 演出は落ちた先をここから読む。
      expect(result.boltCells, [const Cell(7, 5)]);
    });

    test('討ち取れなかった敵にも雷は落ちたことになる', () {
      final controller = prismController();
      controller.party.members.add(Mage.storm);
      // 体力2の敵。雷の1ダメージでは討てず、傷ついて残る。
      paintPrism(controller.board, foe: const Cell(7, 5), hp: 2);

      trace(controller, boltPath);
      final result = controller.commitPath();

      // 討ててはいないので bolt は空。それでも当たってはいるので、
      // 演出が「何も起きなかった」ように見えないよう boltCells には残る。
      expect(result!.bolt, isEmpty);
      expect(result.boltCells, [const Cell(7, 5)]);
      expect(controller.board.tileAt(const Cell(7, 5))!.hp, 1);
    });

    test('焔の補正で威力8に届いても、7枚では雷は落ちない', () {
      // 3色の盤面。雷が要る色数は満たしているので、枚数だけが争点になる。
      final controller = GameController(
        rng: Random(3),
        roster: const [Mage.ember, Mage.squireBlue, Mage.squireViolet],
      );
      controller.party.members.add(Mage.storm);
      paintPrism(controller.board, foe: const Cell(7, 5));

      // 7枚。赤が3枚あるので焔の補正が乗り、威力は8になる。
      trace(controller, boltPath.take(stormChain - 1).toList());
      expect(controller.pathLength, stormChain - 1);
      expect(controller.power, stormChain);

      // 威力は届いているが、見ているのは枚数なので落ちない。
      final result = controller.commitPath();
      expect(result!.bolt, isEmpty);
      expect(result.boltCells, isEmpty);
      expect(controller.board.remainingFoes, 1);
    });

    test('2色の盤面では、何枚継いでも雷は落ちない', () {
      // 3色にしてでも8枚編む、というのが雷を入れる理由。2色の編成では
      // 連れていても一度も落ちない。
      final controller = newController();
      controller.party.members.add(Mage.storm);
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
        Cell(1, 5),
        Cell(1, 4),
        Cell(1, 3),
      ]);
      expect(controller.pathLength, greaterThanOrEqualTo(stormChain));

      final result = controller.commitPath();
      expect(result!.bolt, isEmpty);
      expect(result.boltCells, isEmpty);
      expect(controller.board.remainingFoes, 1);
    });

    test('雷が居なければ追撃は起きない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
        Cell(1, 5),
        Cell(1, 4),
      ]);
      final result = controller.commitPath();
      expect(result!.bolt, isEmpty);
      expect(controller.board.remainingFoes, 1);
    });

    test('未所持の魔導士は名簿の順に返る', () {
      // 道中では増えないが、この並びはガチャが未所持を数えるのに使う。
      // 始まりの記録は見習い3人ぶん。返ってくるのは招ける7人の並び。
      final party = Party.initial();
      for (final mage in Mage.summonable) {
        expect(party.nextRecruit, mage);
        party.members.add(mage);
      }
      expect(party.nextRecruit, isNull, reason: '全員揃えば返らない');
    });

    test('階層をまたいでも、増えるものは何も無い', () {
      final controller = newController();
      final before = controller.party.members.length;
      controller.party.takeDamage(30);
      final hp = controller.party.hp;

      controller.nextFloor();

      expect(controller.floor, 2);
      // 体力はそのまま持ち越す。戻る手立ては道中に無い。
      expect(controller.party.hp, hp);
      expect(controller.party.maxHp, Party.poolFor(twoPhases));
      expect(controller.party.members.length, before);
    });
  });

  test('次の階層に進むと、その階層の定義どおりに組み直される', () {
    final controller = newController();
    final dungeon = controller.dungeon;
    expect(controller.floor, 1);
    expect(controller.remainingFoes, dungeon.floorAt(1).foes.length);

    controller.nextFloor();
    expect(controller.floor, 2);
    expect(controller.remainingFoes, dungeon.floorAt(2).foes.length);
    expect(controller.phase, GamePhase.playing);
  });

  test('やり直すと1階層目からになり、一党もスコアも戻る', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();
    controller.strike();
    controller.nextFloor();
    controller.party.hp = 3;
    expect(controller.floor, 2);

    controller.restart();
    expect(controller.floor, 1);
    expect(controller.score, 0);
    expect(controller.party.hp, Party.poolFor(twoPhases));
    expect(controller.party.maxHp, Party.poolFor(twoPhases));
    expect(controller.party.members, twoPhases);
    expect(controller.phase, GamePhase.playing);
  });

  group('ダンジョン', () {
    test('階層は定義どおりに組まれる', () {
      for (final dungeon in Dungeons.all) {
        for (var floor = 1; floor <= dungeon.depth; floor++) {
          final controller = GameController(
            rng: Random(floor),
            dungeon: dungeon,
            startFloor: floor,
          );
          final spec = dungeon.floorAt(floor);
          expect(
            controller.remainingFoes,
            spec.foes.length,
            reason: '${dungeon.id} B${floor}F',
          );
          expect(
            controller.board.totalFoeHp,
            spec.totalFoeHp,
            reason: '${dungeon.id} B${floor}F',
          );
        }
      }
    });

    test('守りと体力は指定した通りに置かれる', () {
      // 散らす側は「守りが厚いほど体力は薄く」と曲げるが、
      // 手で書いた階層は曲げない。竜に体力3を持たせられないと困る。
      final board = Board(rng: Random(1));
      board.buildStage(
        foes: const [FoeSpec(8, hp: 3), FoeSpec(3)],
      );
      final wards = board.foeWards.toList()..sort();
      expect(wards, [3, 8]);
      expect(board.totalFoeHp, 4);
    });

    test('最下層を制圧すると踏破になる', () {
      final controller = GameController(
        rng: Random(2),
        roster: twoPhases,
        startFloor: Dungeons.all.first.depth,
      );
      expect(controller.isLastFloor, isTrue);

      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.phase, GamePhase.dungeonCleared);
    });

    test('最下層の手前なら踏破ではなく制圧になる', () {
      final controller = newController();
      expect(controller.isLastFloor, isFalse);

      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      controller.strike();

      expect(controller.phase, GamePhase.stageCleared);
    });

    test('最下層では次の階層に進めない', () {
      final dungeon = Dungeons.all.first;
      final controller = GameController(
        rng: Random(2),
        roster: twoPhases,
        startFloor: dungeon.depth,
      );
      controller.nextFloor();
      expect(controller.floor, dungeon.depth);
    });

    test('別のダンジョンに入り直すと1階層目から始まる', () {
      final controller = newController();
      controller.nextFloor();
      controller.party.hp = 5;
      controller.score = 999;

      controller.enterDungeon(Dungeons.all[1]);
      expect(controller.dungeon.id, Dungeons.all[1].id);
      expect(controller.floor, 1);
      expect(controller.score, 0);
      expect(controller.party.hp, Party.poolFor(twoPhases));
    });

    test('連れていく顔ぶれは入り直しても保たれる', () {
      final controller = GameController(
        rng: Random(4),
        roster: const [Mage.ember, Mage.storm],
      );
      expect(controller.party.members, [Mage.ember, Mage.storm]);

      controller.restart();
      expect(controller.party.members, [Mage.ember, Mage.storm]);
      expect(controller.party.hp, Mage.ember.hp + Mage.storm.hp);
    });

    test('ダンジョンは6本。id も名前も重ならない', () {
      expect(Dungeons.all.length, 6);
      final ids = <String>{};
      final names = <String>{};
      for (final d in Dungeons.all) {
        expect(d.depth, inInclusiveRange(5, 7), reason: d.id);
        expect(Dungeons.byId(d.id).id, d.id);
        expect(ids.add(d.id), isTrue, reason: d.id);
        expect(names.add(d.name), isTrue, reason: d.name);
      }
      expect(Dungeons.after(Dungeons.all.last), isNull);
      expect(Dungeons.after(Dungeons.all.first)?.id, Dungeons.all[1].id);
    });

    test('後ろのダンジョンほど重い。梯子に段差を作らない見張り', () {
      // **並びがそのまま難易度の梯子**（前の1本をクリアすると次が開く）。
      // 増やすときに順番を崩すと、初めて遊ぶ人が2本目で詰む。
      //
      // 重さは「階層ごとの 体力合計 × 攻撃力合計」の総和で見る。1手ごとに
      // 殴られるので、体力（＝手数）と攻撃力の積がそのまま浴びる痛手になる
      // （`tools/sim/damage.py` と同じ見方）。
      int weightOf(Dungeon d) {
        var total = 0;
        for (final floor in d.floors) {
          var attack = 0;
          for (final foe in floor.foes) {
            attack += Board.attackFor(foe.ward);
          }
          total += floor.totalFoeHp * attack;
        }
        return total;
      }

      for (var i = 1; i < Dungeons.all.length; i++) {
        final prev = Dungeons.all[i - 1];
        final here = Dungeons.all[i];
        expect(
          weightOf(here),
          greaterThan(weightOf(prev)),
          reason: '${here.id} は ${prev.id} より重いこと',
        );
        expect(
          here.bossWard,
          greaterThanOrEqualTo(prev.bossWard),
          reason: '${here.id} の主は ${prev.id} の主より薄くないこと',
        );
      }
    });

    test('1本目は、始まりの2人でも通る重さに収める', () {
      // **ここで詰むと、編成もガチャも試す前に終わる。** 見習い2人の体力は
      // 90。1本目は手探りで打っても半分は残る重さにしておく。
      final first = Dungeons.all.first;
      expect(first.bossWard, lessThanOrEqualTo(5));
      var totalHp = 0;
      for (final floor in first.floors) {
        totalHp += floor.totalFoeHp;
        for (final foe in floor.foes) {
          expect(foe.ward, lessThanOrEqualTo(5), reason: '守りが厚すぎる');
          expect(foe.hp, lessThanOrEqualTo(2), reason: '体力が厚すぎる');
        }
        expect(floor.foes.length, lessThanOrEqualTo(2), reason: '敵が多すぎる');
      }
      // 体力の合計＝そのまま手数の目安。90 の体力に対して十分に軽いこと。
      expect(totalHp, lessThanOrEqualTo(10));
    });
  });

  group('増えた魔導士', () {
    /// 測りたい魔導士だけを連れた一党。
    ///
    /// 相が1つだけの編成は組めないので、足りなければ違う相の見習いを足して
    /// 2相にする。見習いは能力を持たないので、測りたい補正には影響しない。
    /// 2相なら決まりは「直前1枚と違う」＝交互で、市松の盤面がそのまま使える。
    GameController withRoster(List<Mage> roster) {
      final phases = roster.map((m) => m.phase).toSet();
      final list = [...roster];
      if (phases.length < 2) {
        list.add(Mage.squires.firstWhere((m) => !phases.contains(m.phase)));
      }
      return GameController(rng: Random(3), roster: list);
    }

    test('霜は青から継ぎ始めた鎖にだけ乗る', () {
      final controller = withRoster(const [Mage.frost]);
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // (0,0) は赤。赤から始めたので乗らない。
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      expect(controller.power, 3);
      controller.cancelPath();

      // (0,1) は青。青から始めたので +1。
      trace(controller, const [Cell(0, 1), Cell(0, 2), Cell(0, 3)]);
      expect(controller.power, 4);
    });

    test('烈火は赤5枚から乗り、焔と重なる', () {
      // 9枚で赤が5枚になる並び。
      const path = [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
        Cell(1, 5),
        Cell(1, 4),
        Cell(1, 3),
      ];

      final alone = withRoster(const [Mage.blaze]);
      paintCheckerboard(alone.board, foe: const Cell(7, 5));
      trace(alone, path);
      expect(alone.power, 9 + 2);

      final both = withRoster(const [Mage.ember, Mage.blaze]);
      paintCheckerboard(both.board, foe: const Cell(7, 5));
      trace(both, path);
      expect(both.power, 9 + 1 + 2, reason: '焔の +1 と重なって +3');
    });

    test('烈火は赤が4枚では乗らない', () {
      final controller = withRoster(const [Mage.blaze]);
      paintCheckerboard(controller.board, foe: const Cell(7, 5));
      // 7枚で赤は4枚。
      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
        Cell(1, 5),
      ]);
      expect(controller.power, 7);
    });

    test('風は7枚以上の鎖を編んだ手の反撃を凌ぐ', () {
      // 盤面は1手ごとに崩れるので、長さの違いは別の盤面で測る。
      GameController after(int length, List<Mage> roster) {
        final controller = withRoster(roster);
        paintCheckerboard(controller.board, foe: const Cell(7, 5));
        const path = [
          Cell(0, 0),
          Cell(0, 1),
          Cell(0, 2),
          Cell(0, 3),
          Cell(0, 4),
          Cell(0, 5),
          Cell(1, 5),
        ];
        trace(controller, path.take(length).toList());
        expect(controller.pathLength, length);
        controller.commitPath();
        controller.settle();
        controller.strike();
        return controller;
      }

      final short = after(6, const [Mage.gale]);
      expect(short.lastEvaded, isFalse, reason: '6枚では凌げない');
      expect(short.lastHit, greaterThan(0));

      final long = after(7, const [Mage.gale]);
      expect(long.lastEvaded, isTrue, reason: '7枚なら殴られない');
      expect(long.lastHit, 0);

      // 風が居なければ、どれだけ長く編んでも毎手殴られる。
      final without = after(7, const [Mage.ember]);
      expect(without.lastEvaded, isFalse);
      expect(without.lastHit, greaterThan(0));
    });

    test('盾は受ける痛手を半分にする', () {
      final controller = withRoster(const [Mage.aegis]);
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 7);
      final hpBefore = controller.party.hp;

      strikeThrough(controller);

      // 毎ターンの攻撃が半分になる。守り7の攻撃力2が1に。
      expect(Board.attackFor(7), 2);
      expect(controller.lastHit, 1);
      expect(controller.party.hp, hpBefore - 1);
    });

    test('名簿は見習い3人と招ける7人で、印は全員ちがう', () {
      expect(Mage.squires.length, 3);
      expect(Mage.summonable.length, 7);
      expect(Mage.roster.length, 10);
      // 見習いは相を1つずつ、重ならないように持つ。
      expect(
        Mage.squires.map((m) => m.phase).toSet().length,
        Phase.values.length,
      );
      expect(
        Mage.roster.map((m) => m.kind).toSet().length,
        Mage.roster.length,
      );
      expect(
        Mage.roster.map((m) => m.name).toSet().length,
        Mage.roster.length,
        reason: '名前で見分ける',
      );
      for (final kind in MageKind.values) {
        expect(Mage.of(kind).kind, kind);
      }
    });
  });

  group('押して使う力', () {
    GameController galeController() {
      final controller = GameController(
        rng: Random(3),
        roster: const [Mage.gale, Mage.squireBlue],
      );
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      return controller;
    }

    test('先読みは敵に届く道を見せる。潜り1本に1回だけ', () {
      final controller = galeController();
      expect(controller.hintPath, isEmpty, reason: '使うまでは出ない');

      expect(controller.useActive(MageKind.gale), ActiveResult.done);
      expect(controller.hintPath, isNotEmpty);
      expect(controller.hintPath, contains(const Cell(0, 1)), reason: '敵を通る');

      expect(
        controller.useActive(MageKind.gale),
        ActiveResult.unavailable,
        reason: '2回目',
      );
    });

    test('どの道も敵に届かなければ空振りで、回数は減らない', () {
      final controller = galeController();
      // 1色で塗り潰すと3枚も繋がらない。届く道がどこにも無い盤面。
      paintDead(controller.board, foe: const Cell(0, 1), ward: 3);

      expect(controller.useActive(MageKind.gale), ActiveResult.missed);
      expect(controller.hintPath, isEmpty, reason: '成立するだけの道でお茶を濁さない');
      expect(controller.revealedPath, isEmpty);
      expect(controller.party.canUse(MageKind.gale), isTrue, reason: '減らない');

      // 盤面が戻れば、同じ札がそのまま使える。
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      expect(controller.useActive(MageKind.gale), ActiveResult.done);
      expect(controller.party.canUse(MageKind.gale), isFalse);
    });

    test('見せた道は、なぞって離しただけでは失われない', () {
      final controller = galeController();
      expect(controller.useActive(MageKind.gale), ActiveResult.done);
      final shown = List<Cell>.of(controller.hintPath);

      // 自分の指と重なると読めないので、なぞっている間は引っ込む。
      controller.beginPath(const Cell(3, 3));
      expect(controller.hintPath, isEmpty);

      // 1回きりの札を、触れただけで失わせない。
      controller.cancelPath();
      expect(controller.hintPath, shown);
    });

    test('鎖を1本編むと、見せた道は捨てる', () {
      final controller = galeController();
      controller.useActive(MageKind.gale);

      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();

      // 盤面が変わったので、さっきの道はもう指していない。
      expect(controller.hintPath, isEmpty);
      expect(controller.revealedPath, isEmpty);
    });

    test('延焼は、その相だけの鎖を次の1本だけ通す', () {
      final controller = GameController(
        rng: Random(3),
        roster: const [Mage.blaze, Mage.squireBlue],
      );
      // 上の行を赤で揃えておく。普段は赤を続けて継げない。
      final board = controller.board;
      paintCheckerboard(board, foe: const Cell(7, 5), ward: 3);
      for (var c = 0; c < 3; c++) {
        final base = board.grid[0][c]!;
        board.grid[0][c] = Tile(id: base.id, phase: Phase.red);
      }
      const run = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      expect(board.isConnected(run), isFalse);

      expect(controller.useActive(MageKind.blaze), ActiveResult.done);
      expect(board.spreadPhase, Phase.red);
      expect(board.isConnected(run), isTrue);

      // 1本編んだら元に戻る。
      trace(controller, run);
      expect(controller.commitPath(), isNotNull);
      expect(board.spreadPhase, isNull, reason: '延焼は1本きり');
      expect(controller.party.canUse(MageKind.blaze), isFalse);
    });

    test('その相だけで3枚つながらなければ空振りで、回数も減らない', () {
      final controller = GameController(
        rng: Random(3),
        roster: const [Mage.blaze, Mage.squireBlue],
      );
      // 市松のままなら赤は飛び飛び。緩めても編める鎖は1本も増えない。
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 3);
      expect(controller.board.hasSamePhaseRun(Phase.red), isFalse);

      expect(controller.useActive(MageKind.blaze), ActiveResult.missed);
      expect(controller.board.spreadPhase, isNull);
      expect(controller.party.canUse(MageKind.blaze), isTrue, reason: '減らない');
    });

    test('連れていない魔導士の力は使えない', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      expect(controller.useActive(MageKind.gale), ActiveResult.unavailable);
      expect(controller.hintPath, isEmpty);
    });

    test('階層をまたいでも戻らず、潜り直すと戻る', () {
      final controller = galeController();
      expect(controller.useActive(MageKind.gale), ActiveResult.done);
      expect(controller.party.canUse(MageKind.gale), isFalse);

      controller.nextFloor();
      expect(controller.party.canUse(MageKind.gale), isFalse, reason: '階層は跨ぐ');

      controller.enterDungeon(controller.dungeon);
      expect(controller.party.canUse(MageKind.gale), isTrue, reason: '潜り直し');
    });
  });

  group('なぞれる道を縛る', () {
    test('決めた道の外はなぞれず、途中で離しても何も起きない', () {
      final c = newController();
      paintCheckerboard(c.board);
      c.lockedPath = const [Cell(0, 0), Cell(0, 1), Cell(0, 2)];

      // 始まりも1つに決まる。
      c.beginPath(const Cell(3, 3));
      expect(c.path, isEmpty);

      c.beginPath(const Cell(0, 0));
      expect(c.path.length, 1);

      // 隣で相も繋がるマスでも、道から外れていれば継げない。
      expect(c.extendPath(const Cell(1, 0)), isFalse);
      expect(c.isCandidate(const Cell(1, 0)), isFalse);
      expect(c.isCandidate(const Cell(0, 1)), isTrue);

      // 途中で離しても成立しない。鎖も増えない。
      expect(c.extendPath(const Cell(0, 1)), isTrue);
      expect(c.commitPath(), isNull);
      expect(c.path, isEmpty);
      expect(c.chains, 0);

      // 全部なぞれば通る。
      c.beginPath(const Cell(0, 0));
      c.extendPath(const Cell(0, 1));
      c.extendPath(const Cell(0, 2));
      expect(c.commitPath(), isNotNull);
      expect(c.chains, 1);
    });

    test('縛っていなければこれまで通り', () {
      final c = newController();
      paintCheckerboard(c.board);

      c.beginPath(const Cell(3, 3));
      expect(c.path.length, 1);
      expect(c.extendPath(const Cell(3, 4)), isTrue);
      expect(c.extendPath(const Cell(3, 5)), isTrue);
      expect(c.commitPath(), isNotNull);
    });
  });
}
