import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';

/// 盤面を奇数・偶数の市松に塗り直す。どの方向にも繋がる状態になる。
/// [target] を指定すると、そのマスだけ目標ブロックにする。
void paintCheckerboard(Board board, {Cell? target, int requiredLength = 8}) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final isHere = target != null && target.row == r && target.col == c;
      board.grid[r][c] = Tile(
        id: id++,
        isOdd: (r + c).isEven,
        requiredLength: isHere ? requiredLength : null,
      );
    }
  }
}

GameController newController([int seed = 3]) =>
    GameController(createBoard: () => Board(rng: Random(seed)));

void main() {
  test('なぞって離すと点が入り、settle で盤面が補充される', () {
    final controller = newController();
    // 目標は盤面の隅に、届かない大きさで置いておく。
    // ステージが即クリアにならないようにするため。
    paintCheckerboard(controller.board, target: const Cell(7, 5));

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
    paintCheckerboard(controller.board, target: const Cell(7, 5));
    final before = controller.movesLeft;

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();

    expect(controller.movesLeft, before - 1);
  });

  test('成立しないパスでは手数が減らない', () {
    final controller = newController();
    paintCheckerboard(controller.board, target: const Cell(7, 5));
    final before = controller.movesLeft;

    // 2枚しか繋いでいないので成立しない。
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    expect(controller.commitPath(), isNull);

    expect(controller.movesLeft, before);
    expect(controller.score, 0);
    expect(controller.path, isEmpty);
  });

  test('目標ブロックを全部消すとステージクリア', () {
    final controller = newController();
    // 3枚で消える目標をパス上に置く。
    paintCheckerboard(
      controller.board,
      target: const Cell(0, 1),
      requiredLength: 3,
    );
    expect(controller.remainingTargets, 1);

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    final result = controller.commitPath();
    expect(result!.clearedTargets, 1);

    controller.settle();
    expect(controller.remainingTargets, 0);
    expect(controller.phase, GamePhase.stageCleared);
    expect(controller.acceptsInput, isFalse);
  });

  test('手数を使い切ると失敗する', () {
    final controller = newController();
    paintCheckerboard(controller.board, target: const Cell(7, 5));
    controller.movesLeft = 1;

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();

    expect(controller.movesLeft, 0);
    expect(controller.phase, GamePhase.failed);
  });

  test('長さが足りない目標ブロックは消えず、手数だけが減る', () {
    final controller = newController();
    paintCheckerboard(
      controller.board,
      target: const Cell(0, 1),
      requiredLength: 8,
    );

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));

    // 巻き込んではいるが、8 には 5 枚足りない。
    expect(controller.willClear(const Cell(0, 1)), isFalse);
    expect(controller.tilesToNextTarget, 5);
    expect(controller.pendingClearedTargets, 0);

    final result = controller.commitPath();
    expect(result!.clearedTargets, 0);
    expect(result.cleared, [true, false, true]);

    controller.settle();
    expect(controller.remainingTargets, 1);
    expect(controller.phase, GamePhase.playing);
  });

  test('長さが届けば willClear が立つ', () {
    final controller = newController();
    paintCheckerboard(
      controller.board,
      target: const Cell(0, 1),
      requiredLength: 4,
    );

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    expect(controller.willClear(const Cell(0, 1)), isFalse);
    expect(controller.tilesToNextTarget, 1);

    // 4枚目を繋ぐと届く。
    controller.extendPath(const Cell(0, 3));
    expect(controller.willClear(const Cell(0, 1)), isTrue);
    expect(controller.tilesToNextTarget, 0);
    expect(controller.pendingClearedTargets, 1);
  });

  test('次のステージに進むと目標が増えて手数が戻る', () {
    final controller = newController();
    expect(controller.stage, 1);
    expect(controller.remainingTargets, 1);
    expect(controller.movesLeft, Board.movesFor(1));

    controller.nextStage();
    expect(controller.stage, 2);
    expect(controller.remainingTargets, 2);
    expect(controller.movesLeft, Board.movesFor(2));
    expect(controller.phase, GamePhase.playing);
  });

  test('やり直すと1面からになり、スコアも戻る', () {
    final controller = newController();
    paintCheckerboard(controller.board, target: const Cell(7, 5));
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    controller.nextStage();
    expect(controller.stage, 2);

    controller.restart();
    expect(controller.stage, 1);
    expect(controller.score, 0);
    expect(controller.movesLeft, Board.movesFor(1));
    expect(controller.phase, GamePhase.playing);
  });

  group('ステージの難度', () {
    test('目標の数は5個で頭打ちになる', () {
      expect(GameController.targetCountFor(1), 1);
      expect(GameController.targetCountFor(5), 5);
      expect(GameController.targetCountFor(9), 5);
    });

    test('序盤は小さい数字しか出ない', () {
      expect(GameController.maxRequiredFor(1), 4);
      expect(
        GameController.maxRequiredFor(20),
        Board.maxRequired,
      );
    });

    test('6面以降は手数が削られるが、下限で止まる', () {
      expect(GameController.moveLimitFor(5), Board.movesFor(5));
      expect(GameController.moveLimitFor(6), Board.movesFor(5) - 1);
      expect(GameController.moveLimitFor(40), greaterThanOrEqualTo(10));
    });
  });

  test('繋げる手が無くなると失敗する', () {
    final controller = newController();
    final board = controller.board;
    // 盤面を全部奇数にすると、どこへも繋げない。
    var id = 0;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        board.grid[r][c] = Tile(id: id++, isOdd: true);
      }
    }
    // 目標を1つ残しておく（クリア扱いにならないように）。
    board.grid[7][5] = Tile(id: id++, isOdd: true, requiredLength: 8);

    expect(board.hasAnyChain(), isFalse);

    // settle を通すために、いったん演出中の状態にする。
    controller.isSettling = true;
    controller.settle();
    expect(controller.phase, GamePhase.failed);
  });
}
