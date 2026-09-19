import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/game/party.dart';

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
        isOdd: (r + c).isEven,
        ward: isHere ? ward : null,
        hp: isHere ? hp : 1,
      );
    }
  }
}

GameController newController([int seed = 3]) =>
    GameController(createBoard: () => Board(rng: Random(seed)));

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
    expect(controller.isSettling, isFalse);
    expect(controller.phase, GamePhase.playing);
    expect(controller.acceptsInput, isTrue);
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        expect(board.grid[r][c], isNotNull);
      }
    }
  });

  test('チェインを成立させると手数が1減る', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));
    final before = controller.movesLeft;

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();

    expect(controller.movesLeft, before - 1);
  });

  test('成立しないパスでは手数が減らない', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));
    final before = controller.movesLeft;

    // 2枚しか繋いでいないので成立しない。
    trace(controller, const [Cell(0, 0), Cell(0, 1)]);
    expect(controller.commitPath(), isNull);

    expect(controller.movesLeft, before);
    expect(controller.score, 0);
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
    expect(controller.remainingFoes, 0);
    expect(controller.phase, GamePhase.stageCleared);
    expect(controller.acceptsInput, isFalse);
  });

  test('手数を使い切ると階層を落とし、討ち漏らした敵の反撃を受ける', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
    controller.movesLeft = 1;
    final hpBefore = controller.party.hp;

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();

    expect(controller.movesLeft, 0);
    expect(controller.phase, GamePhase.floorLost);
    // 反撃は討ち漏らした敵の守りの合計。
    expect(controller.lastBacklash, 6);
    expect(controller.party.hp, hpBefore - 6);
  });

  test('落とした階層は同じ深さで編み直す', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
    controller.movesLeft = 1;
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();
    expect(controller.phase, GamePhase.floorLost);

    final stage = controller.stage;
    final hp = controller.party.hp;
    controller.retryFloor();
    expect(controller.stage, stage, reason: '深さは変わらない');
    expect(controller.party.hp, hp, reason: '体力は反撃のときに減らしてある');
    expect(controller.phase, GamePhase.playing);
    expect(controller.movesLeft, greaterThan(0));
  });

  test('反撃で体力が尽きると全滅する', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
    controller.party.hp = 4;
    controller.movesLeft = 1;

    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();

    expect(controller.party.hp, 0);
    expect(controller.party.isDown, isTrue);
    expect(controller.phase, GamePhase.defeated);
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
    expect(controller.remainingFoes, 1);
    // 消えたのは左右のマナだけなので、敵は同じマスに傷ついたまま残る。
    final foe = controller.board.tileAt(const Cell(0, 1))!;
    expect(foe.hp, 2);
    expect(foe.maxHp, 3);
  });

  group('一党', () {
    test('始まりは焔の魔導士ひとり', () {
      final controller = newController();
      expect(controller.party.members, [Mage.ember]);
      expect(controller.party.hp, Party.startingHp);
    });

    test('焔は熱を3枚以上継いだ鎖に威力を1足す', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // 熱（奇数）は (0,0) (0,2) の2枚だけ。まだ乗らない。
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      expect(controller.powerBonus, 0);
      expect(controller.power, 3);

      // 5枚まで伸ばすと熱が3枚になる。
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

    test('氷雨は冷を3枚以上継いだ鎖で体力を戻す', () {
      final controller = newController();
      controller.party.members.add(Mage.rime);
      controller.party.hp = 10;
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // (0,1) (0,3) (0,5) が冷（偶数）。
      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
      ]);
      controller.commitPath();
      expect(controller.lastHealed, 1);
      expect(controller.party.hp, 11);
    });

    test('体力は最大を超えない', () {
      final party = Party.initial();
      expect(party.heal(5), 0);
      expect(party.hp, Party.startingHp);
    });

    test('雷は威力8以上の鎖で階層の敵すべてを削る', () {
      final controller = newController();
      controller.party.members.add(Mage.storm);
      // 守り8の敵を、鎖から離れた隅に置く。
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // 上段6枚＋下段2枚で8枚。焔の補正も乗るので威力は9。
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
      expect(controller.power, greaterThanOrEqualTo(8));

      final result = controller.commitPath();
      // 鎖は敵に触れていないのに、雷で落ちている。
      expect(result!.bolt.length, 1);
      expect(result.bolt.first.cell, const Cell(7, 5));
      expect(result.felled, 1);
      expect(controller.board.remainingFoes, 0);
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

    test('祝福は仲間が揃うまで同行を出す', () {
      final party = Party.initial();
      expect(party.offers().map((o) => o.blessing), contains(Blessing.companion));

      party.grant(Blessing.companion);
      expect(party.members, [Mage.ember, Mage.rime]);
      party.grant(Blessing.companion);
      expect(party.members, [Mage.ember, Mage.rime, Mage.storm]);

      // 全員揃えば同行は出ない。
      expect(party.nextRecruit, isNull);
      expect(
        party.offers().map((o) => o.blessing),
        isNot(contains(Blessing.companion)),
      );
    });

    test('加護は最大体力を増やす', () {
      final party = Party.initial();
      party.hp = 10;
      party.grant(Blessing.vigor);
      expect(party.maxHp, Party.startingHp + Party.vigorGain);
      expect(party.hp, 10 + Party.vigorGain);
    });

    test('制圧の祝福は次の階層に持ち越される', () {
      final controller = newController();
      controller.nextStage(Blessing.companion);
      expect(controller.stage, 2);
      expect(controller.party.members.length, 2);
    });
  });

  test('次の階層に進むと敵が増えて手数が戻る', () {
    final controller = newController();
    expect(controller.stage, 1);
    expect(controller.remainingFoes, 1);
    expect(controller.movesLeft, Board.movesFor(1));

    controller.nextStage();
    expect(controller.stage, 2);
    expect(controller.remainingFoes, 2);
    expect(controller.movesLeft, Board.movesFor(2));
    expect(controller.phase, GamePhase.playing);
  });

  test('やり直すと1階からになり、一党もスコアも戻る', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();
    controller.nextStage(Blessing.companion);
    controller.party.hp = 3;
    expect(controller.stage, 2);

    controller.restart();
    expect(controller.stage, 1);
    expect(controller.score, 0);
    expect(controller.party.hp, Party.startingHp);
    expect(controller.party.members, [Mage.ember]);
    expect(controller.movesLeft, Board.movesFor(1));
    expect(controller.phase, GamePhase.playing);
  });

  group('階層の難度', () {
    test('敵の数は5体で頭打ちになる', () {
      expect(GameController.foeCountFor(1), 1);
      expect(GameController.foeCountFor(5), 5);
      expect(GameController.foeCountFor(9), 5);
    });

    test('序盤は小さい守りしか出ない', () {
      expect(GameController.maxWardFor(1), 4);
      expect(GameController.maxWardFor(20), Board.maxWard);
    });

    test('体力を持つ敵は3階から出てくる', () {
      expect(GameController.maxFoeHpFor(1), 1);
      expect(GameController.maxFoeHpFor(2), 1);
      expect(GameController.maxFoeHpFor(3), 2);
      expect(GameController.maxFoeHpFor(6), 3);
    });

    test('手数は敵の体力の合計から決まる', () {
      // 体力を持つ敵が居なければ、体数で数えていた頃と同じ。
      expect(GameController.moveLimitFor(5), Board.movesFor(5));
      expect(GameController.moveLimitFor(6), Board.movesFor(5) - 1);
      expect(GameController.moveLimitFor(40), greaterThanOrEqualTo(10));
      // 体力の合計が増えれば、そのぶん手数も増える。
      expect(
        GameController.moveLimitFor(3, totalFoeHp: 6),
        greaterThan(GameController.moveLimitFor(3, totalFoeHp: 3)),
      );
    });

    test('階層を作ると、その階層の体力の合計から手数が決まる', () {
      for (var stage = 1; stage <= 8; stage++) {
        final controller = GameController(
          createBoard: () => Board(rng: Random(stage)),
          startStage: stage,
        );
        expect(
          controller.movesLeft,
          GameController.moveLimitFor(
            stage,
            totalFoeHp: controller.board.totalFoeHp,
          ),
          reason: 'stage=$stage',
        );
        expect(controller.movesLeft, greaterThanOrEqualTo(5));
      }
    });
  });

  test('繋げる手が無くなると階層を落とす', () {
    final controller = newController();
    final board = controller.board;
    // 盤面を全部奇数にすると、どこへも繋げない。
    var id = 0;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        board.grid[r][c] = Tile(id: id++, isOdd: true);
      }
    }
    // 敵を1体残しておく（制圧扱いにならないように）。
    board.grid[7][5] = Tile(id: id++, isOdd: true, ward: 8);

    expect(board.hasAnyChain(), isFalse);

    // settle を通すために、いったん演出中の状態にする。
    controller.isSettling = true;
    controller.settle();
    expect(controller.phase, GamePhase.floorLost);
    expect(controller.lastBacklash, 8);
  });
}
