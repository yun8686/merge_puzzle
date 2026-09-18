import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';

/// 決め打ちの盤面を作る。
///
///  - `'o'` / `'e'` … 奇数 / 偶数の通常ブロック（数字は書かれていない）
///  - `'o5'` / `'e3'` … その必要チェイン長を持つ目標ブロック
///  - `'.'` … 空マス
Board boardOf(List<List<String>> spec) {
  final board = Board(
    rows: spec.length,
    cols: spec.first.length,
    rng: Random(1),
  );
  var id = 0;
  for (var r = 0; r < spec.length; r++) {
    for (var c = 0; c < spec[r].length; c++) {
      final s = spec[r][c];
      if (s == '.') {
        board.grid[r][c] = null;
        continue;
      }
      board.grid[r][c] = Tile(
        id: id++,
        isOdd: s[0] == 'o',
        requiredLength: s.length > 1 ? int.parse(s.substring(1)) : null,
      );
    }
  }
  return board;
}

/// 盤面の偶奇を 'o' / 'e' / '.' で書き出す。重力の確認用。
List<List<String>> dump(Board b) => [
      for (var r = 0; r < b.rows; r++)
        [
          for (var c = 0; c < b.cols; c++)
            b.grid[r][c] == null ? '.' : (b.grid[r][c]!.isOdd ? 'o' : 'e'),
        ],
    ];

void main() {
  group('パスの判定', () {
    final board = boardOf([
      ['o', 'e', 'o'],
      ['e', 'o', 'e'],
      ['o', 'e', 'o'],
    ]);

    test('偶奇が交互で隣接していれば成立する', () {
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]),
        isTrue,
      );
    });

    test('同じ偶奇が隣り合っていても繋げない', () {
      final same = boardOf([
        ['o', 'o', 'e'],
        ['e', 'e', 'o'],
      ]);
      expect(same.canExtend(const Cell(0, 0), const Cell(0, 1)), isFalse);
      expect(same.canExtend(const Cell(1, 0), const Cell(1, 1)), isFalse);
      expect(
        same.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(1, 1)]),
        isFalse,
      );
      // 交互になっていれば成立する。
      expect(
        same.isValidPath(const [Cell(1, 1), Cell(0, 1), Cell(0, 2)]),
        isTrue,
      );
    });

    test('3枚未満は成立しない', () {
      expect(board.isValidPath(const [Cell(0, 0), Cell(0, 1)]), isFalse);
    });

    test('離れたマスや同じマスの二度通りは成立しない', () {
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(2, 2)]),
        isFalse,
      );
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 0)]),
        isFalse,
      );
    });
  });

  group('目標ブロック', () {
    List<List<String>> layout() => [
          ['o', 'e5', 'o'],
          ['e', 'o', 'e'],
        ];

    test('長さが足りないと消えずに残る', () {
      final board = boardOf(layout());
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      // 3枚では 5 に届かない。
      expect(board.clearMaskFor(path), [true, false, true]);
      // 通常ブロックは消えるので、チェインとしては成立する。
      expect(board.isValidPath(path), isTrue);

      final result = board.applyPath(path);
      expect(result.clearedTargets, 0);
      expect(board.tileAt(const Cell(0, 1)), isNotNull);
      expect(board.tileAt(const Cell(0, 0)), isNull);
      expect(board.tileAt(const Cell(0, 2)), isNull);
    });

    test('長さが足りれば消える', () {
      final board = boardOf(layout());
      // e o e5 o e の5枚。目標ブロックを真ん中に巻き込む。
      const path = [
        Cell(1, 0),
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(1, 2),
      ];
      expect(board.isConnected(path), isTrue);
      expect(board.clearMaskFor(path).every((x) => x), isTrue);

      final result = board.applyPath(path);
      expect(result.clearedTargets, 1);
      expect(result.length, 5);
      expect(board.remainingTargets, 0);
    });

    test('何も消えないチェインは成立しない', () {
      // 3枚とも要求 5 の目標ブロックなので、1枚も消えない。
      final board = boardOf([
        ['o5', 'e5', 'o5'],
      ]);
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      expect(board.isConnected(path), isTrue);
      expect(board.isValidPath(path), isFalse);
    });

    test('目標ブロックは補充で降ってこない', () {
      final board = boardOf([
        ['o3', 'e', 'o'],
        ['e', 'o', 'e'],
        ['o', 'e', 'o'],
      ]);
      expect(board.remainingTargets, 1);
      board.applyPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      board.applyGravity();
      board.refill();
      // 盤面は埋め戻されるが、目標ブロックは1つも増えない。
      expect(board.remainingTargets, 0);
      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          expect(board.grid[r][c], isNotNull);
        }
      }
    });
  });

  group('重力', () {
    test('空いた分だけ下に詰む', () {
      final board = boardOf([
        ['o', 'e'],
        ['.', 'o'],
        ['.', 'e'],
      ]);
      board.applyGravity();
      expect(dump(board), [
        ['.', 'e'],
        ['.', 'o'],
        ['o', 'e'],
      ]);
    });
  });

  group('探索', () {
    final board = boardOf([
      ['o', 'e', 'o'],
      ['e', 'o', 'e'],
      ['o', 'e', 'o'],
    ]);

    test('指定のマスを通る、長さ N 以上のパスを返す', () {
      final path = board.findPathThrough(const Cell(1, 1), 5);
      expect(path.length, greaterThanOrEqualTo(5));
      expect(path, contains(const Cell(1, 1)));
      expect(board.isConnected(path), isTrue);
    });

    test('盤面より長いパスは見つからない', () {
      expect(board.findPathThrough(const Cell(1, 1), 100), isEmpty);
    });

    test('偶奇が一色の盤面では手が無い', () {
      final stuck = boardOf([
        ['o', 'o', 'o'],
        ['o', 'o', 'o'],
      ]);
      expect(stuck.hasAnyChain(), isFalse);
      expect(stuck.findHint(), isEmpty);
    });

    test('交互に並んでいれば手がある', () {
      expect(board.hasAnyChain(), isTrue);
      expect(board.findHint().length, greaterThanOrEqualTo(3));
    });

    test('ヒントは目標ブロックを消せる手を優先する', () {
      final withTarget = boardOf([
        ['o', 'e3', 'o'],
        ['e', 'o', 'e'],
        ['o', 'e', 'o'],
      ]);
      final hint = withTarget.findHint();
      expect(hint, contains(const Cell(0, 1)));
      expect(hint.length, greaterThanOrEqualTo(3));
    });

    test('消せない目標ブロックは canClearTarget が false', () {
      // 要求 8 だが盤面が 6 マスしかないので、どう繋いでも届かない。
      final tight = boardOf([
        ['o', 'e8', 'o'],
        ['e', 'o', 'e'],
      ]);
      expect(tight.canClearTarget(const Cell(0, 1)), isFalse);
    });
  });

  group('ステージの数値', () {
    test('手数は目標の数から決まる', () {
      expect(Board.movesFor(1), 5);
      expect(Board.movesFor(3), 11);
      expect(Board.movesFor(5), 17);
    });

    test('長いチェインほど点が伸びる', () {
      expect(Board.scoreFor(4, 0), greaterThan(Board.scoreFor(3, 0)));
      expect(Board.scoreFor(6, 0), greaterThan(Board.scoreFor(4, 0)));
    });

    test('目標を消すと加点される', () {
      expect(Board.scoreFor(3, 1), greaterThan(Board.scoreFor(3, 0)));
    });
  });

  group('生成した盤面', () {
    test('開幕から手があり、目標ブロックが指定の数だけ置かれる', () {
      for (var seed = 0; seed < 30; seed++) {
        final board = Board(rng: Random(seed));
        board.buildStage(targetCount: 3, maxRequiredLength: 6);
        expect(board.remainingTargets, 3, reason: 'seed=$seed');
        expect(board.hasAnyChain(), isTrue, reason: 'seed=$seed');
        for (final cell in board.targetCells) {
          final need = board.tileAt(cell)!.requiredLength!;
          expect(need, greaterThanOrEqualTo(Board.minRequired));
          expect(need, lessThanOrEqualTo(6));
        }
      }
    });
  });
}
