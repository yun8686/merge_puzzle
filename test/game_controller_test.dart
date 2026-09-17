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
