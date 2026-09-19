import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';

/// 決め打ちの盤面を作る。
///
///  - `'o'` / `'e'` … 奇数 / 偶数のマナ（数字は書かれていない）
///  - `'o5'` / `'e3'` … その守りを持つ敵。体力は 1
///  - `'o5:2'` … 守り 5・体力 2 の敵
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
      final parts = s.substring(1).split(':');
      final ward = parts.first.isEmpty ? null : int.parse(parts.first);
      board.grid[r][c] = Tile(
        id: id++,
        isOdd: s[0] == 'o',
        ward: ward,
        hp: parts.length > 1 ? int.parse(parts[1]) : 1,
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

  group('守り', () {
    List<List<String>> layout() => [
      ['o', 'e5', 'o'],
      ['e', 'o', 'e'],
    ];

    test('威力が守りに届かないと弾かれて無傷で残る', () {
      final board = boardOf(layout());
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      // 威力 3 では守り 5 に届かない。
      expect(board.damageAt(const Cell(0, 1), 3), 0);
      expect(board.clearMaskFor(path), [true, false, true]);
      // マナのマスは消えるので、チェインとしては成立する。
      expect(board.isValidPath(path), isTrue);

      final result = board.applyPath(path);
      expect(result.felled, 0);
      expect(result.damages, [0, 0, 0]);
      final foe = board.tileAt(const Cell(0, 1));
      expect(foe, isNotNull);
      expect(foe!.hp, 1, reason: '弾かれたので体力は減らない');
      expect(board.tileAt(const Cell(0, 0)), isNull);
      expect(board.tileAt(const Cell(0, 2)), isNull);
    });

    test('守りを上回れば討ち取れる', () {
      final board = boardOf(layout());
      // e o e5 o e の5枚。敵を真ん中に巻き込む。
      const path = [Cell(1, 0), Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 2)];
      expect(board.isConnected(path), isTrue);
      expect(board.clearMaskFor(path).every((x) => x), isTrue);

      final result = board.applyPath(path);
      expect(result.felled, 1);
      expect(result.power, 5);
      expect(board.remainingFoes, 0);
    });

    test('守りを1上回るごとに1ダメージ', () {
      final tile = Tile(id: 0, isOdd: true, ward: 5, hp: 3);
      expect(tile.damageFrom(4), 0);
      expect(tile.damageFrom(5), 1);
      expect(tile.damageFrom(7), 3);
      // 体力3を一撃で削り切るには威力7が要る。
      expect(tile.powerToFell, 7);
      // 傷をつけるだけなら守りちょうどで足りる。
      expect(tile.powerToHurt, 5);
    });

    test('何も起きないチェインは成立しない', () {
      // 3枚とも守り 5 の敵なので、誰にも傷がつかない。
      final board = boardOf([
        ['o5', 'e5', 'o5'],
      ]);
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      expect(board.isConnected(path), isTrue);
      expect(board.isValidPath(path), isFalse);
    });

    test('敵は補充で降ってこない', () {
      final board = boardOf([
        ['o3', 'e', 'o'],
        ['e', 'o', 'e'],
        ['o', 'e', 'o'],
      ]);
      expect(board.remainingFoes, 1);
      board.applyPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
      board.applyGravity();
      board.refill();
      // 盤面は埋め戻されるが、敵は1体も増えない。
      expect(board.remainingFoes, 0);
      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          expect(board.grid[r][c], isNotNull);
        }
      }
    });
  });

  group('体力', () {
    test('削り切れなければ傷ついてその場に残る', () {
      final board = boardOf([
        ['o', 'e3:3', 'o'],
        ['e', 'o', 'e'],
      ]);
      // 威力3なら守り3を1上回る……ではなく、ちょうど1ダメージ。
      final result = board.applyPath(const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
      ]);
      expect(result.damages[1], 1);
      expect(result.felled, 0);
      final foe = board.tileAt(const Cell(0, 1))!;
      expect(foe.hp, 2);
      expect(foe.maxHp, 3, reason: '最大体力は減らない。減り具合の表示に使う');
      expect(foe.ward, 3);
    });

    test('傷しかつかないチェインでも成立する', () {
      // 3枚とも守り3・体力3の敵。誰も討てないが、全員に傷はつく。
      final board = boardOf([
        ['o3:3', 'e3:3', 'o3:3'],
      ]);
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      expect(board.isValidPath(path), isTrue);
      final result = board.applyPath(path);
      expect(result.felled, 0);
      expect(result.damages, [1, 1, 1]);
      expect(board.remainingFoes, 3);
      expect(board.totalFoeHp, 6);
    });

    test('体力1の敵は、体力を持たなかった頃と同じ挙動になる', () {
      for (var ward = Board.minWard; ward <= Board.maxWard; ward++) {
        final tile = Tile(id: 0, isOdd: true, ward: ward);
        for (var power = 1; power <= 12; power++) {
          expect(
            tile.damageFrom(power) >= tile.hp,
            power >= ward,
            reason: 'ward=$ward power=$power',
          );
        }
      }
    });
  });

  group('威力の補正', () {
    test('補正を足した威力で判定される', () {
      final board = boardOf([
        ['o', 'e4', 'o'],
        ['e', 'o', 'e'],
      ]);
      const path = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      // 枚数そのままの威力 3 では届かない。
      expect(board.clearMaskFor(path), [true, false, true]);
      // 補正で 4 になれば討てる。
      expect(board.clearMaskFor(path, power: 4), [true, true, true]);

      final result = board.applyPath(path, power: 4);
      expect(result.power, 4);
      expect(result.felled, 1);
      expect(result.gained, Board.scoreFor(4, 1));
    });
  });

  group('鎖の外からの追撃', () {
    test('守りを無視して盤面の敵すべてを削る', () {
      final board = boardOf([
        ['o8', 'e3:2', 'o'],
        ['e', 'o', 'e'],
      ]);
      final fallen = board.strike(1);
      // 守り8・体力1の敵は落ちる。守りは関係しない。
      expect(fallen.length, 1);
      expect(fallen.first.cell, const Cell(0, 0));
      expect(fallen.first.ward, 8);
      // 体力2の敵は傷ついて残る。
      expect(board.tileAt(const Cell(0, 1))!.hp, 1);
      expect(board.remainingFoes, 1);
    });

    test('敵が居なければ何も起きない', () {
      final board = boardOf([
        ['o', 'e'],
      ]);
      expect(board.strike(3), isEmpty);
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

    test('ヒントは敵を討てる手を優先する', () {
      final withFoe = boardOf([
        ['o', 'e3', 'o'],
        ['e', 'o', 'e'],
        ['o', 'e', 'o'],
      ]);
      final hint = withFoe.findHint();
      expect(hint, contains(const Cell(0, 1)));
      expect(hint.length, greaterThanOrEqualTo(3));
    });

    test('討てない敵でも、傷をつけられる手があればそれを出す', () {
      // 守り3・体力5。一撃で討つには威力7が要るが、盤面は6マスしかない。
      final tough = boardOf([
        ['o', 'e3:5', 'o'],
        ['e', 'o', 'e'],
      ]);
      expect(tough.canFell(const Cell(0, 1)), isFalse);
      expect(tough.findHint(), contains(const Cell(0, 1)));
    });

    test('討てない敵は canFell が false', () {
      // 守り8だが盤面が6マスしかないので、どう繋いでも届かない。
      final tight = boardOf([
        ['o', 'e8', 'o'],
        ['e', 'o', 'e'],
      ]);
      expect(tight.canFell(const Cell(0, 1)), isFalse);
    });
  });

  group('階層の数値', () {
    test('手数は敵の体力の合計から決まる', () {
      expect(Board.movesFor(1), 5);
      expect(Board.movesFor(3), 11);
      expect(Board.movesFor(5), 17);
    });

    test('威力が高いほど点が伸びる', () {
      expect(Board.scoreFor(4, 0), greaterThan(Board.scoreFor(3, 0)));
      expect(Board.scoreFor(6, 0), greaterThan(Board.scoreFor(4, 0)));
    });

    test('敵を討つと加点される', () {
      expect(Board.scoreFor(3, 1), greaterThan(Board.scoreFor(3, 0)));
    });

    test('討ち漏らした敵の反撃は守りの合計', () {
      final board = boardOf([
        ['o5', 'e', 'o3:2'],
        ['e', 'o', 'e'],
      ]);
      expect(board.foeThreat, 8);
      expect(board.totalFoeHp, 3);
    });
  });

  group('生成した盤面', () {
    test('開幕から手があり、敵が指定の数だけ置かれる', () {
      for (var seed = 0; seed < 30; seed++) {
        final board = Board(rng: Random(seed));
        board.buildStage(foeCount: 3, wardCap: 6);
        expect(board.remainingFoes, 3, reason: 'seed=$seed');
        expect(board.hasAnyChain(), isTrue, reason: 'seed=$seed');
        for (final cell in board.foeCells) {
          final foe = board.tileAt(cell)!;
          expect(foe.ward, greaterThanOrEqualTo(Board.minWard));
          expect(foe.ward, lessThanOrEqualTo(6));
          expect(foe.hp, 1, reason: '既定では体力1の敵しか置かない');
        }
      }
    });

    test('体力を許すと、守りの厚い敵には積まれない', () {
      for (var seed = 0; seed < 40; seed++) {
        final board = Board(rng: Random(seed));
        board.buildStage(foeCount: 5, wardCap: Board.maxWard, maxFoeHp: 3);
        expect(board.remainingFoes, 5, reason: 'seed=$seed');
        for (final cell in board.foeCells) {
          final foe = board.tileAt(cell)!;
          expect(foe.hp, inInclusiveRange(1, 3));
          if (foe.ward! >= Board.maxWard - 1) {
            expect(foe.hp, 1, reason: '守りが厚い敵に体力は積まない');
          }
        }
        expect(board.totalFoeHp, greaterThanOrEqualTo(5));
      }
    });
  });
}
