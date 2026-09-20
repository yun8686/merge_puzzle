import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/phase.dart';
import 'package:parity_chain/main.dart';
import 'package:parity_chain/ui/board_view.dart';
import 'package:parity_chain/ui/foe_art.dart';
import 'package:parity_chain/ui/game_screen.dart';
import 'package:parity_chain/ui/mage_art.dart';
import 'package:parity_chain/ui/theme.dart';

/// 盤面を奇数・偶数の市松模様で塗りつぶす。どの方向にも繋がる状態。
///
/// 隅に、届かない守りの敵を1体置いておく。これが無いと最初のチェインで
/// 敵が尽きて階層クリアになり、演出の確認ができない。
void paintCheckerboard(Board board) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.heat : Phase.cold);
    }
  }
  final corner = board.grid[board.rows - 1][board.cols - 1]!;
  board.grid[board.rows - 1][board.cols - 1] = Tile(
    id: corner.id,
    phase: corner.phase,
    ward: Board.maxWard,
  );
}

GameController newController(int seed) =>
    GameController(rng: Random(seed), roster: twoPhases);

/// 熱と冷の2相だけの一党。この2色なら「直前1枚と違う」＝交互で、
/// 相を入れる前の盤面と規則も手触りも変わらない。市松の盤面を
/// 決め打ちで置くテストは、この2相を前提にしている。
const twoPhases = [Mage.squireHeat, Mage.squireCold];

/// 同じ2相でも、従者ではなく焔と氷雨を連れた一党。従者の印は '熱' '冷' で
/// 相の呼び名とぶつかるので、印と相の数を別々に読みたいときはこちら。
/// 焔が居るぶん、熱を3枚以上継いだ鎖には威力が1乗る。
const emberPair = [Mage.ember, Mage.rime];

/// 盤面の相の見本。漢字ではなくマスと同じ色なので、型で探す。
Finder swatchOf(Phase phase) => find.byWidgetPredicate(
  (w) => w is PhaseSwatch && w.phase == phase,
);

/// 一党の帯に並ぶ魔導士の姿。印の文字ではなく絵になったので、型で探す。
Finder portraitOf(MageKind kind) => find.byWidgetPredicate(
  (w) => w is MagePortrait && w.kind == kind,
);

/// 3相の一党。雷は3色の盤面でしか落ちないので、その確認はこちらで。
const threePhases = [Mage.squireHeat, Mage.squireCold, Mage.squireBolt];

/// 盤面を3相の斜め縞に塗る。相は (r + c) を 3 で割った余りで決まるので、
/// 右・下へ1歩ずつ進むかぎり「直前2枚と違う」を満たし続ける。隅には
/// 届かない守りの敵を置く（市松のときと同じ理由）。
void paintPrism(Board board) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      board.grid[r][c] = Tile(id: id++, phase: Phase.values[(r + c) % 3]);
    }
  }
  final corner = board.grid[board.rows - 1][board.cols - 1]!;
  board.grid[board.rows - 1][board.cols - 1] = Tile(
    id: corner.id,
    phase: corner.phase,
    ward: Board.maxWard,
  );
}

void main() {
  testWidgets('なぞるとチェインが成立して点が入る', (tester) async {
    final controller = newController(1);
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );

    // 300x400 に 6列x8行 なのでセルは 50px、原点は左上。
    final origin = tester.getTopLeft(find.byType(BoardView));
    Offset centerOf(int row, int col) =>
        origin + Offset((col + 0.5) * 50, (row + 0.5) * 50);

    final gesture = await tester.startGesture(centerOf(0, 0));
    await tester.pump();
    await gesture.moveTo(centerOf(0, 1));
    await tester.pump();
    await gesture.moveTo(centerOf(0, 2));
    await tester.pump();

    expect(controller.path.length, 3);

    await gesture.up();
    await tester.pump();

    expect(controller.score, greaterThan(0));
    expect(controller.path, isEmpty);

    // 演出のアニメーションが最後まで走りきること。
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('長い鎖でもスコア表示は作り直されない', (tester) async {
    final controller = GameController(rng: Random(3), roster: emberPair);
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(BoardView));
    Offset centerOf(int row, int col) =>
        origin + Offset((col + 0.5) * 50, (row + 0.5) * 50);

    // 上段を右へ6マス、下段を左へ3マスなぞって9枚の鎖にする。
    // 熱が5枚あるので焔の補正が乗り、表示される威力は10になる。
    final gesture = await tester.startGesture(centerOf(0, 0));
    await tester.pump();
    for (var col = 1; col < 6; col++) {
      await gesture.moveTo(centerOf(0, col));
      await tester.pump();
    }
    for (var col = 5; col >= 3; col--) {
      await gesture.moveTo(centerOf(1, col));
      await tester.pump();
    }
    expect(controller.path.length, 9);

    await gesture.up();
    await tester.pump();

    expect(find.text('POWER 10'), findsOneWidget);
    final popup = tester.element(find.text('POWER 10'));

    // 消えるタイルが1枚ずつ片付く間、スコア表示の要素が作り直されると
    // アニメーションが頭から流れ直し、同じ表示が何度も出てしまう。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('POWER 10'), findsOneWidget);
      expect(identical(tester.element(find.text('POWER 10')), popup), isTrue);
    }

    // 850ms のアニメーションが終われば、繰り返さずに消えること。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('POWER 10'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('消え終わるまで盤面は止まったままで、あとから詰まる', (tester) async {
    final controller = newController(4);
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(BoardView));
    Offset centerOf(int row, int col) =>
        origin + Offset((col + 0.5) * 50, (row + 0.5) * 50);

    final gesture = await tester.startGesture(centerOf(0, 0));
    await tester.pump();
    for (var col = 1; col < 6; col++) {
      await gesture.moveTo(centerOf(0, col));
      await tester.pump();
    }
    final cleared = List.of(controller.path);
    await gesture.up();
    await tester.pump();

    // 消えた直後。盤面には穴が開いたままで、まだ詰まっていない。
    expect(controller.isSettling, isTrue);
    for (final c in cleared) {
      expect(controller.board.tileAt(c), isNull);
    }

    // なぞった順に弾けている最中も、盤面は止まったまま。
    // 間隔を詰めても壊れないよう、余裕を持った時刻で見る。
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.isSettling,
      isTrue,
      reason: '演出の途中で詰めると、弾ける順番が新しいタイルに埋もれる',
    );

    // 弾け終われば詰めて補充する。
    await tester.pump(const Duration(milliseconds: 800));
    expect(controller.isSettling, isFalse);
    final board = controller.board;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        expect(board.grid[r][c], isNotNull);
      }
    }

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('偶奇が同じマスへは伸びない', (tester) async {
    final controller = newController(2);
    // 全部奇数にすると、どこへも繋がらない。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: Phase.heat);
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(BoardView));
    final gesture = await tester.startGesture(origin + const Offset(25, 25));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(75, 25));
    await tester.pump();

    expect(controller.path.length, 1);

    await gesture.up();
    await tester.pump();
    expect(controller.score, 0);
  });

  testWidgets('アプリが起動する', (tester) async {
    // 拠点が出る。保存が使えない環境でも落ちないこと（テストには
    // shared_preferences のプラグインが居ないので、毎回この経路を通る）。
    await tester.pumpWidget(const ParityChainApp());
    await tester.pumpAndSettle();
    expect(find.text('ダンジョン'), findsOneWidget);
  });

  testWidgets('盤面の画面に階層と敵の数が表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          controller: GameController(rng: Random(1), roster: emberPair),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('DEPTH'), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
    // 残りターンと残りの敵。階層の進行がそのまま出ていること。
    expect(find.text('TURNS'), findsOneWidget);
    expect(find.text('FOES'), findsOneWidget);
    // 盤面に敷かれた相の比率。呼び名ではなくマスと同じ色で出ていること。
    expect(swatchOf(Phase.heat), findsOneWidget);
    expect(swatchOf(Phase.cold), findsOneWidget);
    expect(swatchOf(Phase.bolt), findsNothing, reason: '連れていない相');
    expect(find.text(Phase.heat.label), findsNothing, reason: '漢字は出さない');
    // 階層をまたいで残る一党。連れてきた顔ぶれが姿で並ぶ。
    expect(find.text('PARTY'), findsOneWidget);
    expect(portraitOf(MageKind.ember), findsOneWidget);
    expect(portraitOf(MageKind.rime), findsOneWidget);
    expect(portraitOf(MageKind.storm), findsNothing, reason: '連れていない');
  });

  testWidgets('陥落画面に討ち漏らした敵が5体並ぶ', (tester) async {
    final controller = newController(7);
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.heat : Phase.cold);
      }
    }
    // 守りを散らして最下段に並べる。重力で動かないので位置が読める。
    const wards = [3, 4, 5, 6, 8];
    for (var i = 0; i < wards.length; i++) {
      final base = controller.board.grid[7][i]!;
      controller.board.grid[7][i] = Tile(
        id: base.id,
        phase: base.phase,
        ward: wards[i],
      );
    }

    controller.movesLeft = 1;
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    expect(controller.phase, GamePhase.floorLost);
    // 反撃は守りの合計。
    expect(controller.lastBacklash, 26);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    // 5体ぶんの姿と呼び名が出ること。溢れれば RenderFlex が例外を投げるので、
    // 実機を見られなくても並びが収まっているかはここで分かる。
    expect(find.text('討ち漏らした'), findsOneWidget);
    // 盤面の敵マスにも姿が出るので、札の中だけを数える。
    expect(
      find.descendant(
        of: find.byType(FoeChip),
        matching: find.byType(FoePortrait),
      ),
      findsNWidgets(wards.length),
    );
    for (final ward in wards) {
      expect(find.text(foeNameFor(ward)), findsOneWidget, reason: '守り$ward');
    }
    expect(find.text('-26'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('階層を制圧すると祝福を選ばされ、選ぶと次の階層に進む', (tester) async {
    final controller = newController(5);
    // 威力3で討てる敵を1体だけ置く。1手で制圧できる。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.heat : Phase.cold);
      }
    }
    final target = controller.board.grid[0][1]!;
    controller.board.grid[0][1] = Tile(
      id: target.id,
      phase: target.phase,
      ward: Board.minWard,
    );

    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    expect(controller.phase, GamePhase.stageCleared);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('祝福を1つ選ぶ'), findsOneWidget);
    expect(find.text('癒やし'), findsOneWidget);
    expect(find.text('加護'), findsOneWidget);
    expect(find.text('同行'), findsNothing, reason: '仲間は道中で増えない');
    // 討ち果たした敵の姿と呼び名。守り3は小鬼。
    expect(find.text('討ち果たした'), findsOneWidget);
    expect(find.text(foeNameFor(Board.minWard)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FoeChip),
        matching: find.byType(FoePortrait),
      ),
      findsOneWidget,
    );

    // 祝福で仲間は増えない。増えるのは体力と最大体力だけ。
    final maxHpBefore = controller.party.maxHp;
    await tester.ensureVisible(find.text('加護'));
    await tester.pump();
    await tester.tap(find.text('加護'));
    await tester.pump();

    expect(controller.floor, 2);
    expect(controller.party.maxHp, maxHpBefore + Party.vigorGain);
    expect(controller.party.members.length, twoPhases.length);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('盤面の敵マスに、姿と守りの数字が出る', (tester) async {
    final controller = newController(1);
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 敵は隅の1体だけ。姿が封印の中に入り、守りの数字は別に読める。
    expect(
      find.descendant(
        of: find.byType(BoardView),
        matching: find.byType(FoePortrait),
      ),
      findsOneWidget,
    );
    expect(find.text('${Board.maxWard}'), findsOneWidget);
  });


  testWidgets('雷が落ちる鎖でも、演出は最後まで走りきる', (tester) async {
    final controller = GameController(rng: Random(3), roster: threePhases);
    paintPrism(controller.board);
    controller.party.members.add(Mage.storm);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(BoardView));
    Offset centerOf(int row, int col) =>
        origin + Offset((col + 0.5) * 50, (row + 0.5) * 50);

    // 上段を右へ6枚、そこから下へ3枚で9枚。3色の盤面で8枚以上なので
    // 雷が落ちる。折り返すと相が戻って繋がらないので、曲がったら下へ降りる。
    final gesture = await tester.startGesture(centerOf(0, 0));
    await tester.pump();
    for (var col = 1; col < 6; col++) {
      await gesture.moveTo(centerOf(0, col));
      await tester.pump();
    }
    for (var row = 1; row <= 3; row++) {
      await gesture.moveTo(centerOf(row, 5));
      await tester.pump();
    }
    expect(controller.path.length, 9);

    await gesture.up();
    await tester.pump();

    // 隅の敵は鎖に触れていないのに、雷で落ちている。
    expect(controller.board.remainingFoes, 0);

    // 雷は最後の1枚が弾けるのに合わせて落ちる。そこを跨いで描き切れること。
    // 実機を見られなくても、描画で例外が出ればここで落ちる。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('殴られると赤い明滅が走る', (tester) async {
    final controller = newController(1);
    // 隅に届かない守りの敵が1体残る。毎ターン殴ってくる。
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    final hpBefore = controller.party.hp;
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    await tester.pump();

    expect(controller.party.hp, lessThan(hpBefore));
    expect(controller.hitTick, 1);
    // 受けた量が帯に出る。
    expect(find.text('-${controller.lastHit}'), findsOneWidget);

    // 明滅が走りきるまで描き続けても例外が出ないこと。実機を見られなくても、
    // 描画で落ちればここで分かる。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('制圧の画面は、最後の敵を討ってから少し待って出る', (tester) async {
    final controller = newController(5);
    // 威力3で討てる敵を1体だけ置く。1手で制圧できる。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.heat : Phase.cold);
      }
    }
    final target = controller.board.grid[0][1]!;
    controller.board.grid[0][1] = Tile(
      id: target.id,
      phase: target.phase,
      ward: Board.minWard,
    );

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.text('祝福を1つ選ぶ'), findsNothing);

    // 目の前で討ち果たす。
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    await tester.pump();

    // 局面は制圧に移っているが、まだ盤面を覆わない。
    expect(controller.phase, GamePhase.stageCleared);
    expect(find.text('祝福を1つ選ぶ'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('祝福を1つ選ぶ'), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('祝福を1つ選ぶ'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
