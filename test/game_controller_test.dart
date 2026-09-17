import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';

void main() {
  test('なぞって離すと点が入り、盤面が補充される', () {
    final controller = GameController(board: Board(rng: Random(3)));
    final path = controller.board.findBestPath();
    expect(path.length, greaterThanOrEqualTo(Board.minPathLength));

    controller.beginPath(path.first);
    for (final c in path.skip(1)) {
      expect(controller.extendPath(c), isTrue);
    }
    expect(controller.path.length, path.length);

    final result = controller.commitPath();
    expect(result, isNotNull);
    expect(controller.score, greaterThan(0));
    expect(controller.path, isEmpty);

    // 消した後も盤面は満杯のまま。
    final board = controller.board;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        expect(board.grid[r][c], isNotNull);
      }
    }
  });

  test('1つ戻ると縮む', () {
    final controller = GameController(board: Board(rng: Random(5)));
    final path = controller.board.findBestPath();
    controller.beginPath(path[0]);
    controller.extendPath(path[1]);
    controller.extendPath(path[2]);
    expect(controller.path.length, 3);

    controller.extendPath(path[1]);
    expect(controller.path.length, 2);
  });

  test('繋がらないマスは伸ばせない', () {
    final controller = GameController(board: Board(rng: Random(7)));
    final board = controller.board;
    final start = const Cell(0, 0);
    controller.beginPath(start);

    for (var c = 0; c < board.cols; c++) {
      for (var r = 0; r < board.rows; r++) {
        final target = Cell(r, c);
        if (target == start) continue;
        if (!board.canExtend(start, target)) {
          expect(controller.extendPath(target), isFalse);
          expect(controller.path.length, 1);
          return;
        }
      }
    }
  });

  test('合計が必要値に届かないパスは成立しない', () {
    final controller = GameController(board: Board(rng: Random(13)));
    final board = controller.board;
    // 1 と 2 の市松。3枚だと 4 にしかならず、初期の必要合計値 6 に届かない。
    var id = 0;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        board.grid[r][c] = Tile(id: id++, value: (r + c).isEven ? 1 : 2);
      }
    }

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    expect(controller.pathTotal, 4);
    expect(controller.requiredTotal, Board.baseRequiredTotal);
    expect(controller.pathIsValid, isFalse);
    expect(controller.pendingScore, 0);
    expect(controller.missingTotal, 2);
    expect(controller.commitPath(), isNull);
    expect(controller.score, 0);

    // 4枚に伸ばせば合計 6 で成立する。
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.extendPath(const Cell(0, 3));
    expect(controller.pathTotal, 6);
    expect(controller.pathIsValid, isTrue);
    expect(controller.commitPath(), isNotNull);
    expect(controller.score, greaterThan(0));
  });

  test('消すほど必要合計値が上がる', () {
    final controller = GameController(board: Board(rng: Random(17)));
    expect(controller.requiredTotal, Board.baseRequiredTotal);

    controller.board.clearedTotal = Board.requiredTotalStep * 5;
    expect(controller.requiredTotal, Board.baseRequiredTotal + 5);
  });

  test('打ち続ければ必ず終局する', () {
    const limit = 300;
    for (var seed = 0; seed < 3; seed++) {
      final controller = GameController(board: Board(rng: Random(seed)));
      var moves = 0;
      while (moves < limit) {
        final path = controller.board.findBestPath();
        if (path.isEmpty) break;
        controller.beginPath(path.first);
        for (final c in path.skip(1)) {
          controller.extendPath(c);
        }
        if (controller.commitPath() == null) break;
        moves++;
      }
      // 必要合計値が上がっていくので、最短チェイン連打でも無限には遊べない。
      expect(moves, lessThan(limit), reason: 'seed=$seed: $limit 手で終わらない');
      expect(controller.phase, GamePhase.gameOver, reason: 'seed=$seed');
      expect(
        controller.requiredTotal,
        greaterThan(Board.baseRequiredTotal),
        reason: 'seed=$seed: 必要合計値が上がっていない',
      );
    }
  });

  test('成立しないパスは離しても何も起きない', () {
    final controller = GameController(board: Board(rng: Random(11)));
    final path = controller.board.findBestPath();
    controller.beginPath(path.first);
    controller.extendPath(path[1]);

    expect(controller.commitPath(), isNull);
    expect(controller.score, 0);
    expect(controller.path, isEmpty);
  });
}
