import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/dungeon.dart';
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

    final floor = controller.floor;
    final hp = controller.party.hp;
    controller.retryFloor();
    expect(controller.floor, floor, reason: '深さは変わらない');
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
      final controller = newController();
      controller.party.members.add(Mage.storm);
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);

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
      controller.commitPath();
      expect(controller.felledWards, [6]);
    });

    test('階層が変わると空に戻る', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();
      expect(controller.felledWards, [3]);

      controller.nextFloor(Blessing.heal);
      expect(controller.felledWards, isEmpty);
    });

    test('討ち漏らした敵の守りは盤面から読める', () {
      final controller = newController();
      paintCheckerboard(controller.board, foe: const Cell(7, 5), ward: 6);
      expect(controller.board.foeWards, [6]);
    });
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

    test('雷は8枚継いだ鎖で階層の敵すべてを削る', () {
      final controller = newController();
      controller.party.members.add(Mage.storm);
      // 守り8の敵を、鎖から離れた隅に置く。
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // 上段6枚＋下段2枚で8枚。
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
      final controller = newController();
      controller.party.members.add(Mage.storm);
      // 体力2の敵。雷の1ダメージでは討てず、傷ついて残る。
      paintCheckerboard(controller.board, foe: const Cell(7, 5), hp: 2);

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

      // 討ててはいないので bolt は空。それでも当たってはいるので、
      // 演出が「何も起きなかった」ように見えないよう boltCells には残る。
      expect(result!.bolt, isEmpty);
      expect(result.boltCells, [const Cell(7, 5)]);
      expect(controller.board.tileAt(const Cell(7, 5))!.hp, 1);
    });

    test('焔の補正で威力8に届いても、7枚では雷は落ちない', () {
      final controller = newController();
      controller.party.members.add(Mage.storm);
      paintCheckerboard(controller.board, foe: const Cell(7, 5));

      // 7枚。熱が4枚あるので焔の補正が乗り、威力は8になる。
      trace(controller, const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
        Cell(0, 5),
        Cell(1, 5),
      ]);
      expect(controller.pathLength, stormChain - 1);
      expect(controller.power, stormChain);

      // 威力は届いているが、見ているのは枚数なので落ちない。
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

    test('未所持の魔導士は加入順に返る', () {
      // 道中では増えないが、この並びはガチャが未所持を数えるのに使う。
      final party = Party.initial();
      expect(party.nextRecruit, Mage.rime);
      party.members.add(Mage.rime);
      expect(party.nextRecruit, Mage.storm);
      party.members.add(Mage.storm);
      expect(party.nextRecruit, isNull);
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
      controller.nextFloor(Blessing.vigor);
      expect(controller.floor, 2);
      expect(controller.party.maxHp, Party.startingHp + Party.vigorGain);
    });

    test('祝福で仲間は増えない', () {
      final party = Party.initial();
      final before = party.members.length;
      for (final offer in party.offers()) {
        party.grant(offer.blessing);
      }
      expect(party.members.length, before);
    });
  });

  test('次の階層に進むと、その階層の定義どおりに組み直される', () {
    final controller = newController();
    final dungeon = controller.dungeon;
    expect(controller.floor, 1);
    expect(controller.remainingFoes, dungeon.floorAt(1).foes.length);
    expect(controller.movesLeft, dungeon.floorAt(1).moveLimit);

    controller.nextFloor();
    expect(controller.floor, 2);
    expect(controller.remainingFoes, dungeon.floorAt(2).foes.length);
    expect(controller.movesLeft, dungeon.floorAt(2).moveLimit);
    expect(controller.phase, GamePhase.playing);
  });

  test('やり直すと1階層目からになり、一党もスコアも戻る', () {
    final controller = newController();
    paintCheckerboard(controller.board, foe: const Cell(7, 5));
    trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    controller.commitPath();
    controller.settle();
    controller.nextFloor(Blessing.vigor);
    controller.party.hp = 3;
    expect(controller.floor, 2);

    controller.restart();
    expect(controller.floor, 1);
    expect(controller.score, 0);
    expect(controller.party.hp, Party.startingHp);
    expect(controller.party.maxHp, Party.startingHp, reason: '加護も戻る');
    expect(controller.party.members, [Mage.ember]);
    expect(controller.movesLeft, controller.dungeon.floorAt(1).moveLimit);
    expect(controller.phase, GamePhase.playing);
  });

  group('ダンジョン', () {
    test('階層は定義どおりに組まれる', () {
      for (final dungeon in Dungeons.all) {
        for (var floor = 1; floor <= dungeon.depth; floor++) {
          final controller = GameController(
            createBoard: () => Board(rng: Random(floor)),
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
          expect(controller.movesLeft, spec.moveLimit);
          expect(controller.movesLeft, greaterThanOrEqualTo(5));
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
        createBoard: () => Board(rng: Random(2)),
        startFloor: Dungeons.all.first.depth,
      );
      expect(controller.isLastFloor, isTrue);

      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();

      expect(controller.phase, GamePhase.dungeonCleared);
    });

    test('最下層の手前なら踏破ではなく制圧になる', () {
      final controller = newController();
      expect(controller.isLastFloor, isFalse);

      paintCheckerboard(controller.board, foe: const Cell(0, 1), ward: 3);
      trace(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      controller.commitPath();
      controller.settle();

      expect(controller.phase, GamePhase.stageCleared);
    });

    test('最下層では次の階層に進めない', () {
      final dungeon = Dungeons.all.first;
      final controller = GameController(
        createBoard: () => Board(rng: Random(2)),
        startFloor: dungeon.depth,
      );
      controller.nextFloor(Blessing.vigor);
      expect(controller.floor, dungeon.depth);
      expect(controller.party.maxHp, Party.startingHp, reason: '祝福も乗らない');
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
      expect(controller.party.hp, Party.startingHp);
      expect(controller.movesLeft, Dungeons.all[1].floorAt(1).moveLimit);
    });

    test('連れていく顔ぶれは入り直しても保たれる', () {
      final controller = GameController(
        createBoard: () => Board(rng: Random(4)),
        roster: const [Mage.ember, Mage.storm],
      );
      expect(controller.party.members, [Mage.ember, Mage.storm]);

      controller.restart();
      expect(controller.party.members, [Mage.ember, Mage.storm]);
      expect(controller.party.hp, Party.startingHp);
    });

    test('ダンジョンは3本あって、どれも7階層', () {
      expect(Dungeons.all.length, 3);
      for (final d in Dungeons.all) {
        expect(d.depth, 7, reason: d.id);
        expect(Dungeons.byId(d.id).id, d.id);
      }
      expect(Dungeons.after(Dungeons.all.last), isNull);
      expect(Dungeons.after(Dungeons.all.first)?.id, Dungeons.all[1].id);
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
