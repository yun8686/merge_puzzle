import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';

/// 0 を空マスとして、決め打ちの盤面を作る。
Board boardOf(List<List<int>> values) {
  final board = Board(
    rows: values.length,
    cols: values.first.length,
    rng: Random(1),
  );
  var id = 0;
  for (var r = 0; r < values.length; r++) {
    for (var c = 0; c < values[r].length; c++) {
      final v = values[r][c];
      board.grid[r][c] = v == 0 ? null : Tile(id: id++, value: v);
    }
  }
  return board;
}

List<List<int>> dump(Board b) => [
      for (var r = 0; r < b.rows; r++)
        [for (var c = 0; c < b.cols; c++) b.grid[r][c]?.value ?? 0],
    ];

void main() {
  group('パスの判定', () {
    final board = boardOf([
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ]);

    test('偶奇が交互で隣接していれば成立する', () {
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]),
        isTrue,
      );
    });

    test('同じ偶奇が隣り合っていても繋げない', () {
      final sameParity = boardOf([
        [1, 3, 2],
        [2, 4, 6],
      ]);
      // 1(奇) -> 3(奇) は隣接しているが偶奇が同じなので不可。
      expect(sameParity.canExtend(const Cell(0, 0), const Cell(0, 1)), isFalse);
      // 2(偶) -> 4(偶) も同様。
      expect(sameParity.canExtend(const Cell(1, 0), const Cell(1, 1)), isFalse);
      // 偶奇が同じマスを含むパスは成立しない。
      expect(
        sameParity.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(1, 1)]),
        isFalse,
      );
      // 交互になっていれば成立する: 4(偶) -> 3(奇) -> 2(偶)。
      expect(
        sameParity.isValidPath(const [Cell(1, 1), Cell(0, 1), Cell(0, 2)]),
        isTrue,
      );
    });

    test('斜めは繋げない', () {
      expect(board.canExtend(const Cell(0, 0), const Cell(1, 1)), isFalse);
    });

    test('同じマスを2度通れない', () {
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 0)]),
        isFalse,
      );
    });

    test('最低枚数に満たないと成立しない', () {
      expect(board.isValidPath(const [Cell(0, 0), Cell(0, 1)]), isFalse);
    });
  });

  test('パスを消すとタイルが全部消える', () {
    final board = boardOf([
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ]);
    final result =
        board.applyPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);

    expect(result.total, 1 + 2 + 3);
    expect(result.length, 3);
    // 合成タイルは残さない。残すと際限なく育って必要合計値を素通りできる。
    expect(board.grid[0][0], isNull);
    expect(board.grid[0][1], isNull);
    expect(board.grid[0][2], isNull);
    expect(board.clearedTotal, 1 + 2 + 3);
  });

  test('重力で下に詰まる', () {
    final board = boardOf([
      [1, 0, 3],
      [0, 0, 0],
      [0, 8, 9],
    ]);
    board.applyGravity();
    expect(dump(board), [
      [0, 0, 0],
      [0, 0, 3],
      [1, 8, 9],
    ]);
  });

  test('補充で空きマスが全部埋まる', () {
    final board = boardOf([
      [0, 0],
      [0, 3],
    ]);
    final added = board.refill();
    expect(added.length, 3);
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        expect(board.grid[r][c], isNotNull);
      }
    }
  });

  group('詰み判定', () {
    test('全部奇数なら手が無い', () {
      final board = boardOf([
        [1, 3, 5],
        [7, 1, 3],
        [5, 7, 1],
      ]);
      expect(board.hasAnyPath(), isFalse);
      expect(board.findBestPath(), isEmpty);
    });

    test('交互に並んでいれば手がある', () {
      final board = boardOf([
        [1, 2, 3],
        [2, 1, 2],
        [3, 2, 1],
      ]);
      expect(board.hasAnyPath(), isTrue);
      expect(board.findBestPath().length, greaterThanOrEqualTo(3));
    });

    test('偶数が1枚だけでも合計が足りれば詰みではない', () {
      final board = boardOf([
        [3, 2],
        [3, 3],
      ]);
      // 3(0,0) -> 2(0,1) -> 3(1,1) で3枚繋がり、合計 8 で成立する。
      expect(board.hasAnyPath(), isTrue);
    });

    test('偶数が尽きると詰む', () {
      final board = boardOf([
        [1, 1, 1],
        [3, 5, 3],
        [5, 1, 7],
      ]);
      expect(board.evenCount, 0);
      expect(board.hasAnyPath(), isFalse);
    });
  });

  group('必要合計値', () {
    test('合計が足りないパスは成立しない', () {
      final board = boardOf([
        [1, 2, 1],
        [1, 1, 1],
      ]);
      // 偶奇は交互だが 1+2+1 = 4 で、初期の必要合計値 6 に届かない。
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]),
        isFalse,
      );
      // 偶数が1枚しかないのでこれ以上伸ばせず、盤面ごと詰み。
      expect(board.hasAnyPath(), isFalse);
    });

    test('消した合計値が積み上がると必要合計値が上がる', () {
      final board = boardOf([
        [1, 2],
        [3, 4],
      ]);
      expect(board.requiredTotal, Board.baseRequiredTotal);
      board.clearedTotal = Board.requiredTotalStep * 3;
      expect(board.requiredTotal, Board.baseRequiredTotal + 3);
    });

    test('必要合計値が上がると同じ盤面でも詰む', () {
      final board = boardOf([
        [1, 2, 1],
        [2, 1, 2],
        [1, 2, 1],
      ]);
      // 1+2+1+2 = 6 で成立する手がある。
      expect(board.hasAnyPath(), isTrue);

      // 全マス辿っても 13 にしかならないので、必要合計値を超えると詰む。
      board.clearedTotal = Board.requiredTotalStep * 20;
      expect(board.requiredTotal, greaterThan(13));
      expect(board.hasAnyPath(), isFalse);
      expect(board.findBestPath(), isEmpty);
    });

    test('ヒントは必要合計値を満たすパスを返す', () {
      final board = boardOf([
        [1, 2, 1, 2],
        [2, 1, 2, 1],
        [1, 2, 1, 2],
      ]);
      board.clearedTotal = Board.requiredTotalStep * 4; // 必要合計 10
      final hint = board.findBestPath();
      expect(hint, isNotEmpty);
      expect(board.totalOf(hint), greaterThanOrEqualTo(board.requiredTotal));
      expect(board.isValidPath(hint), isTrue);
    });
  });

  test('ヒントは実際に成立するパスを返す', () {
    final board = boardOf([
      [1, 2, 3],
      [2, 1, 2],
      [3, 2, 1],
    ]);
    final hint = board.findBestPath();
    expect(board.isValidPath(hint), isTrue);
  });

  group('得点', () {
    test('長いチェインほど指数的に伸びる', () {
      final three = Board.scoreFor(30, 3);
      final four = Board.scoreFor(30, 4);
      final six = Board.scoreFor(30, 6);
      expect(four, greaterThan(three));
      expect(six, greaterThan(four * 2));
    });
  });

  test('偶数の残量を数える', () {
    final board = boardOf([
      [1, 2, 3],
      [4, 5, 6],
    ]);
    expect(board.evenCount, 3);
    expect(board.tileCount, 6);
  });

  test('初期盤面は必ず手がある状態で始まる', () {
    for (var seed = 0; seed < 30; seed++) {
      final board = Board(rng: Random(seed));
      board.fillInitial();
      expect(board.hasAnyPath(), isTrue, reason: 'seed=$seed');
    }
  });
}
