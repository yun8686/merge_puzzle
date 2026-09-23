import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/phase.dart';

/// 決め打ちの盤面を作る。
///
///  - `'o'` / `'e'` / `'b'` … 赤 / 青 / 紫のマナ（数字は書かれていない）
///  - `'o5'` / `'e3'` … その守りを持つ敵。体力は 1
///  - `'o5:2'` … 守り 5・体力 2 の敵
///  - `'.'` … 空マス
Board boardOf(List<List<String>> spec) {
  // 記号に 'b' が出てくる盤面だけ、紫の相も入っているものとして組む。
  final hasBolt = spec.any((row) => row.any((s) => s.startsWith('b')));
  final board = Board(
    rows: spec.length,
    cols: spec.first.length,
    phases: hasBolt
        ? const [Phase.red, Phase.blue, Phase.violet]
        : const [Phase.red, Phase.blue],
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
        phase: switch (s[0]) {
          'o' => Phase.red,
          'b' => Phase.violet,
          _ => Phase.blue,
        },
        ward: ward,
        hp: parts.length > 1 ? int.parse(parts[1]) : 1,
      );
    }
  }
  return board;
}

/// 盤面の相を 'o' / 'e' / 'b' / '.' で書き出す。重力の確認用。
List<List<String>> dump(Board b) => [
  for (var r = 0; r < b.rows; r++)
    [
      for (var c = 0; c < b.cols; c++)
        if (b.grid[r][c] == null)
          '.'
        else
          switch (b.grid[r][c]!.phase) {
            Phase.red => 'o',
            Phase.blue => 'e',
            Phase.violet => 'b',
          },
    ],
];

void main() {
  group('パスの判定', () {
    final board = boardOf([
      ['o', 'e', 'o'],
      ['e', 'o', 'e'],
      ['o', 'e', 'o'],
    ]);

    test('相が交互で隣接していれば成立する', () {
      expect(
        board.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]),
        isTrue,
      );
    });

    test('同じ相が隣り合っていても繋げない', () {
      final same = boardOf([
        ['o', 'o', 'e'],
        ['e', 'e', 'o'],
      ]);
      expect(
        same.canExtendPath(const [Cell(0, 0)], const Cell(0, 1)),
        isFalse,
      );
      expect(
        same.canExtendPath(const [Cell(1, 0)], const Cell(1, 1)),
        isFalse,
      );
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

  group('3色の盤面の継ぎ方', () {
    // 決まりは2本立てで、鎖ごとにどちらかを選ぶ。
    //   2色の交互 … 使う相が2つだけなら、隣が違えばよい
    //   3色の巡回 … 3色目を踏んだら、直前2枚と同じ相は継げない
    //
    // 3枚目で1枚目に戻れば前者に確定し、以降その2色だけ。3色目を踏めば
    // 後者で、以降は巡回しか編めない。
    //
    // 巡回だけに縛っていた頃は3色の盤面が目に見えて詰まった（敵マスを通る
    // 最長パスの平均が 6.3 枚で、2色だった頃の 8.3 枚に届かない）。2本立てに
    // すると 7.7 枚まで戻る（README 第8段階）。
    final board = boardOf([
      ['o', 'e', 'b', 'o'],
      ['e', 'o', 'e', 'b'],
      ['o', 'b', 'o', 'e'],
    ]);

    test('3色の巡回はそのまま継げる', () {
      expect(
        board.isValidPath(const [
          Cell(0, 0),
          Cell(0, 1),
          Cell(0, 2),
          Cell(0, 3),
        ]),
        isTrue,
        reason: '赤→青→紫→赤',
      );
    });

    test('3枚目で1枚目に戻ると2色の鎖になる', () {
      // 赤→青→赤。ここで2色に確定する。
      const back = [Cell(0, 0), Cell(0, 1), Cell(1, 1)];
      expect(board.isValidPath(back), isTrue);
      expect(
        board.canExtendPath(back, const Cell(1, 2)),
        isTrue,
        reason: '(1,2) は青。2色の交互なので続けられる',
      );
    });

    test('2色に確定した鎖に3色目は継げない', () {
      const back = [Cell(0, 0), Cell(0, 1), Cell(1, 1)]; // 赤→青→赤
      expect(
        board.canExtendPath(back, const Cell(2, 1)),
        isFalse,
        reason: '(2,1) は紫。巡回に切り替わると、戻った3枚目が後から無効になる',
      );
    });

    test('3色の鎖では直前2枚と同じ相は継げない', () {
      // 赤→青→紫→赤 と来たら、次は青でなければならない。
      const ring = [Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(0, 3)];
      expect(
        board.canExtendPath(ring, const Cell(1, 3)),
        isFalse,
        reason: '(1,3) は紫。直前2枚に紫が居る',
      );
    });

    test('2色の編成では決まりが変わらない', () {
      // 相が2つなら「使う相が2つだけ」が常に成り立つので、決まりは交互1本。
      // 相を入れる前の盤面と手触りが変わらない。
      final two = boardOf([
        ['o', 'e', 'o', 'e'],
        ['e', 'o', 'e', 'o'],
      ]);
      expect(
        two.isValidPath(const [
          Cell(0, 0),
          Cell(0, 1),
          Cell(0, 2),
          Cell(0, 3),
        ]),
        isTrue,
      );
      expect(
        two.isValidPath(const [Cell(0, 0), Cell(0, 1), Cell(1, 1)]),
        isTrue,
        reason: '赤青赤。2色では巡回の決まりが効かない',
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
      final tile = Tile(id: 0, phase: Phase.red, ward: 5, hp: 3);
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
        final tile = Tile(id: 0, phase: Phase.red, ward: ward);
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

    test('相が一色の盤面では手が無い', () {
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

  group('延焼（その相だけで継ぐ）', () {
    test('立てると同じ相だけの鎖が通り、混ぜると元の決まりに戻る', () {
      final board = boardOf([
        ['o', 'o', 'o', 'e'],
        ['e', 'o', 'e', 'o'],
      ]);
      const run = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
      expect(board.isConnected(run), isFalse, reason: '普段は赤を続けられない');

      board.spreadPhase = Phase.red;
      expect(board.isConnected(run), isTrue);

      // 混ぜたら元の決まり。赤赤の重なりが残るので通らない。
      expect(
        board.isConnected([...run, const Cell(0, 3)]),
        isFalse,
        reason: '赤だけか、いつもの決まりかのどちらか',
      );
      // いつもの決まりを満たす鎖は、延焼中でもそのまま通る。
      expect(
        board.isConnected(const [Cell(0, 3), Cell(1, 3), Cell(1, 2)]),
        isTrue,
        reason: '青→赤→青',
      );
    });

    test('その相だけで3枚つながる場所があるかを見分ける', () {
      // 赤が飛び飛び。緩めても編める鎖は増えない。
      final apart = boardOf([
        ['o', 'e', 'o', 'e'],
        ['e', 'o', 'e', 'o'],
      ]);
      expect(apart.hasSamePhaseRun(Phase.red), isFalse);
      expect(apart.hasSamePhaseRun(Phase.blue), isFalse);

      // ひと繋がりに3マス。L 字でも角を曲がれるので通る。
      final run = boardOf([
        ['o', 'o', 'e', 'e'],
        ['o', 'e', 'e', 'o'],
      ]);
      expect(run.hasSamePhaseRun(Phase.red), isTrue);
    });

    test('延焼中は手詰まりの見方も変わる', () {
      // 1色で塗り潰した盤面。普段はどこへも繋げない。
      final board = boardOf([
        ['o', 'o', 'o', 'o'],
        ['o', 'o', 'o', 'o'],
      ]);
      expect(board.hasAnyChain(), isFalse);

      board.spreadPhase = Phase.red;
      expect(board.hasAnyChain(), isTrue);
    });
  });

  group('先読み（いちばん深く届く道）', () {
    test('通る敵が多いほうを採る', () {
      // 敵は2体とも守り3・体力1。1体だけ通る道より、両方通る道のほうが深い。
      final board = boardOf([
        ['o', 'e3', 'o', 'e3'],
        ['e', 'o', 'e', 'o'],
        ['o', 'e', 'o', 'e'],
        ['e', 'o', 'e', 'o'],
      ]);

      final path = board.bestStrike(powerOf: (p) => p.length);
      expect(path, contains(const Cell(0, 1)));
      expect(path, contains(const Cell(0, 3)));
      expect(board.isValidPath(path, power: path.length), isTrue);
    });

    test('威力が届かない敵しか居なければ、道は無い', () {
      // 3枚しか繋がらない盤面で守り8。弾かれるだけなので 0 点。
      final board = boardOf([
        ['o8', 'e', 'o'],
      ]);
      expect(board.bestStrike(powerOf: (p) => p.length), isEmpty);
    });

    test('敵が居なければ道は無い', () {
      final board = boardOf([
        ['o', 'e', 'o', 'e'],
        ['e', 'o', 'e', 'o'],
      ]);
      expect(board.bestStrike(powerOf: (p) => p.length), isEmpty);
    });

    test('威力の補正も数に入る', () {
      // 守り5・体力1。枚数だけでは 4 枚しか繋がらず届かないが、
      // 補正が 2 乗れば威力 6 で通る。
      final board = boardOf([
        ['o', 'e5', 'o', 'e'],
      ]);
      expect(board.bestStrike(powerOf: (p) => p.length), isEmpty);
      expect(
        board.bestStrike(powerOf: (p) => p.length + 2),
        contains(const Cell(0, 1)),
      );
    });
  });

  group('階層の数値', () {
    test('威力が高いほど点が伸びる', () {
      expect(Board.scoreFor(4, 0), greaterThan(Board.scoreFor(3, 0)));
      expect(Board.scoreFor(6, 0), greaterThan(Board.scoreFor(4, 0)));
    });

    test('敵を討つと加点される', () {
      expect(Board.scoreFor(3, 1), greaterThan(Board.scoreFor(3, 0)));
    });

    test('残っている敵の体力を合計できる', () {
      final board = boardOf([
        ['o5', 'e', 'o3:2'],
        ['e', 'o', 'e'],
      ]);
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

  group('降ってくるマナの比率', () {
    /// 空の盤面を [Board.refill] で埋めて、相ごとの枚数を数える。
    ///
    /// 初期盤面（`_fillInitial`）は比率を無視して均等に敷くので、比率が
    /// 効くのは**補充のときだけ**。数えるのはそちら。
    List<int> tally(List<Phase> phases, {List<int>? weights}) {
      final board = Board(phases: phases, weights: weights, rng: Random(7));
      final counts = List<int>.filled(phases.length, 0);
      for (var round = 0; round < 200; round++) {
        board.refill();
        for (var r = 0; r < board.rows; r++) {
          for (var c = 0; c < board.cols; c++) {
            counts[phases.indexOf(board.grid[r][c]!.phase)]++;
            board.grid[r][c] = null;
          }
        }
      }
      return counts;
    }

    test('赤と青をひとりずつなら 1:1 で降る', () {
      // 比率は「その相の魔導士が何人居るか」（`Party.phaseWeights`）。
      // 赤1人・青1人なら [1, 1]。盤面がどちらかに寄ってはいけない。
      final counts = tally(const [Phase.red, Phase.blue]);
      final total = counts[0] + counts[1];
      expect(total, 200 * 8 * 6);
      expect(counts[0] / total, closeTo(0.5, 0.02));
      expect(counts[1] / total, closeTo(0.5, 0.02));
    });

    test('同じ相を2人連れると、その相が多く降る。ただし倍までは届かない', () {
      // 真下と同じ相が降りにくい（`Board.stackDamping`）ぶん、比率は薄まる。
      // 多い側が底に溜まって下の敵に届かなくなるのを防ぐための引き換え。
      final counts = tally(const [Phase.red, Phase.blue], weights: const [2, 1]);
      final total = counts[0] + counts[1];
      expect(counts[0] / total, greaterThan(0.52));
      expect(counts[0] / total, lessThan(2 / 3 - 0.05));
    });

    test('相が3つでも、ひとりずつなら 1:1:1', () {
      final counts = tally(const [Phase.red, Phase.blue, Phase.violet]);
      final total = counts[0] + counts[1] + counts[2];
      for (final n in counts) {
        expect(n / total, closeTo(1 / 3, 0.02));
      }
    });

    test('真下と同じ相は降りにくい', () {
      // 同じ相を縦に積むと固まりができ、どの鎖も通れないまま底に沈む。
      // 均等に引けば半分は真下と同じになるところを、1/(1+6) まで下げる。
      final board = Board(rng: Random(7));
      var same = 0;
      var pairs = 0;
      for (var round = 0; round < 200; round++) {
        board.refill();
        for (var r = 0; r < board.rows - 1; r++) {
          for (var c = 0; c < board.cols; c++) {
            pairs++;
            if (board.grid[r][c]!.phase == board.grid[r + 1][c]!.phase) same++;
          }
        }
        for (final row in board.grid) {
          row.fillRange(0, row.length, null);
        }
      }
      expect(same / pairs, closeTo(1 / (1 + Board.stackDamping), 0.03));
    });
  });

  group('手詰まりの敷き直し', () {
    /// 敵を1体置いて、敵ごと全部赤で塗り潰した盤面。どこへもつなげない。
    Board deadBoard(int seed) {
      final board = Board(rng: Random(seed));
      board.buildStage(foes: const [FoeSpec(6, hp: 2)]);
      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          final t = board.grid[r][c]!;
          board.grid[r][c] =
              Tile(id: t.id, phase: Phase.red, ward: t.ward, hp: t.hp);
        }
      }
      return board;
    }

    test('敵はその場に残し、マナだけ敷き直して手を作る', () {
      for (var seed = 0; seed < 20; seed++) {
        final board = deadBoard(seed);
        expect(board.hasAnyChain(), isFalse, reason: 'seed=$seed');
        final at = board.foeCells.single;
        final foe = board.tileAt(at)!;

        final added = board.reshuffle();

        expect(board.hasAnyChain(), isTrue, reason: 'seed=$seed');
        expect(board.foeCells, [at], reason: '敵は動かない');
        expect(identical(board.tileAt(at), foe), isTrue, reason: '傷も守りもそのまま');
        expect(added.length, board.rows * board.cols - 1);
        expect(added, isNot(contains(foe.id)));
      }
    });
  });
}
