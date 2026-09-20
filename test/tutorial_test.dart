import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/phase.dart';
import 'package:parity_chain/ui/board_view.dart';
import 'package:parity_chain/ui/tutorial.dart';

import 'home_screen_test.dart' show openBase;

/// 稽古場と同じ顔ぶれ・同じ階層で組む。差し込めるので、課題が進むところを
/// 盤面から直に作れる。
GameController newController() => GameController(
  rng: Random(4),
  dungeon: TutorialScreen.dungeon,
  roster: const [Mage.squireHeat, Mage.squireCold],
);

/// 盤面を市松に塗る。敵は隅に1体だけ残す（制圧扱いにならないように）。
void paintCheckerboard(Board board, {int ward = 8}) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      board.grid[r][c] = Tile(
        id: id++,
        phase: (r + c).isEven ? Phase.heat : Phase.cold,
      );
    }
  }
  final corner = board.grid[board.rows - 1][board.cols - 1]!;
  board.grid[board.rows - 1][board.cols - 1] = Tile(
    id: corner.id,
    phase: corner.phase,
    ward: ward,
  );
}

/// 市松に塗った盤面の1マスを敵にする。稽古の筋書きを作るのに使う。
void setFoe(Board board, Cell at, int ward) {
  final base = board.grid[at.row][at.col]!;
  board.grid[at.row][at.col] = Tile(id: base.id, phase: base.phase, ward: ward);
}

/// なぞって離して、盤面が詰むまで。
void play(GameController c, List<Cell> path) {
  c.beginPath(path.first);
  for (final cell in path.skip(1)) {
    c.extendPath(cell);
  }
  c.commitPath();
  c.settle();
  c.strike();
}

Future<void> open(WidgetTester tester, GameController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TutorialScreen(onDone: () {}, controller: controller),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('本物の盤面をなぞって進む', (tester) async {
    final controller = newController();
    await open(tester, controller);

    expect(find.byType(BoardView), findsOneWidget, reason: '本物の盤面');
    expect(find.textContaining('3枚つなげば鎖になる'), findsOneWidget);
    // 下の目盛りは盤面の画面と同じ読み方。
    expect(find.text('体力'), findsOneWidget);
    expect(find.text('残り手数'), findsOneWidget);
  });

  testWidgets('3枚つなぐと次の課題に移る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board);

    play(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    await tester.pump();

    expect(find.textContaining('3枚つなげば鎖になる'), findsNothing);
    expect(find.textContaining('6枚つないでみよう'), findsOneWidget);
    // 片付いた手応えが一度だけ出る。
    expect(find.text('できた'), findsOneWidget);
  });

  testWidgets('長い鎖なら課題を飛び越えて進む', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board);

    // 6枚。1つ目と2つ目の課題が同時に片付く。
    play(controller, const [
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(0, 3),
      Cell(0, 4),
      Cell(0, 5),
    ]);
    await tester.pump();

    expect(find.textContaining('守り3の敵を討ち取ろう'), findsOneWidget);
  });

  testWidgets('敵を討ち切ると終いの言葉が出る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    // 盤面から敵を消して、討ち切った状態を作る。
    paintCheckerboard(controller.board, ward: 3);

    play(controller, const [Cell(7, 3), Cell(7, 4), Cell(7, 5)]);
    await tester.pump();

    expect(controller.remainingFoes, 0);
    expect(find.text('ひととおり覚えた'), findsOneWidget);
    expect(find.textContaining('連れていった魔導士で決まる'), findsOneWidget);
    // 盤面では試せない話も言い添えてから送り出す。
    expect(find.textContaining('体力は持ち越し'), findsOneWidget);
    expect(find.text('拠点へ'), findsOneWidget);

    // 覚えたことが順に並ぶ。あっさり閉じると何も残らない。
    for (final label in [
      '鎖を編む',
      '長いほど強い',
      '守りを破る',
      'まとめて当てる',
      '削って討つ',
      '毎ターンの反撃',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // 出そろうまで描き続けても例外が出ないこと。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('開いた瞬間にお手本の指が出る', (tester) async {
    final controller = newController();
    await open(tester, controller);

    // 1手目は何をどうなぞるのかが分からない。ここで待たせない。
    expect(controller.hintPath, isNotEmpty);

    // 指が道を辿り続けても例外が出ないこと。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('なぞっている間だけ消え、離せばまた出る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board);
    await tester.pump();
    expect(controller.hintPath, isNotEmpty);

    // 自分の指と重なると読めないので、なぞっている間は引っ込む。
    controller.beginPath(const Cell(0, 0));
    expect(controller.hintPath, isEmpty);
    controller.extendPath(const Cell(0, 1));
    expect(controller.hintPath, isEmpty);

    // 離せば戻る。稽古場は覚えるための場所なので、待たせない。
    play(controller, const [Cell(0, 0), Cell(0, 1), Cell(0, 2)]);
    await tester.pump();
    expect(controller.hintPath, isNotEmpty);
  });

  testWidgets('1本の鎖で2体に当てると、まとめて当てる稽古が片付く', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board);
    // 上の段に守り3を2体。1本の鎖で両方を通せる間合い。
    setFoe(controller.board, const Cell(0, 0), 3);
    setFoe(controller.board, const Cell(0, 2), 3);
    await tester.pump();

    // 6枚で両方を通る。ここまでの課題もまとめて片付く。
    play(controller, const [
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(0, 3),
      Cell(0, 4),
      Cell(0, 5),
    ]);
    await tester.pump();

    expect(controller.lastFoesHit, 2);
    expect(find.textContaining('残りの敵も討ち取ろう'), findsOneWidget);
  });

  testWidgets('敵が1体しか残っていなければ、まとめて当てる稽古は飛ばす', (tester) async {
    final controller = newController();
    await open(tester, controller);
    // 隅に1体だけ。まとめて当てようがない。
    paintCheckerboard(controller.board);
    await tester.pump();

    play(controller, const [
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(0, 3),
      Cell(0, 4),
      Cell(0, 5),
    ]);
    // 守りを破る課題も片付けておく。
    setFoe(controller.board, const Cell(2, 0), 3);
    await tester.pump();
    play(controller, const [Cell(2, 0), Cell(2, 1), Cell(2, 2)]);
    await tester.pump();

    expect(find.textContaining('残りの敵も討ち取ろう'), findsOneWidget);
  });

  testWidgets('1本で討てない敵は、傷が残る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board);

    // まず6枚。1つ目と2つ目の課題が片付く。
    play(controller, const [
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(0, 3),
      Cell(0, 4),
      Cell(0, 5),
    ]);
    await tester.pump();

    // 削る稽古の局面を作る。隅の敵を退かし、体力2・守り5の敵を1体だけ置く。
    // 敵が1体なら「まとめて当てる」は試しようがないので畳まれ、
    // 「削って討つ」が出る。
    final corner = controller.board.grid[7][5]!;
    controller.board.grid[7][5] = Tile(id: corner.id, phase: corner.phase);
    final base = controller.board.grid[2][2]!;
    controller.board.grid[2][2] = Tile(
      id: base.id,
      phase: base.phase,
      ward: TutorialScreen.toughWard,
      hp: 2,
    );
    controller.felledWards.add(3);

    // 5枚で守り5に届く。傷は1つぶんで、まだ討ち切れない。
    play(controller, const [
      Cell(2, 0),
      Cell(2, 1),
      Cell(2, 2),
      Cell(2, 3),
      Cell(2, 4),
    ]);
    await tester.pump();

    expect(controller.felledWards, isNot(contains(TutorialScreen.toughWard)));
    expect(find.textContaining('削り切ろう'), findsOneWidget);

    // 傷は盤面に残る。同じ威力でもう一度当てれば討てる。
    final hurt = controller.board.foeCells.firstWhere(
      (c) => controller.board.tileAt(c)!.ward == TutorialScreen.toughWard,
    );
    expect(controller.board.tileAt(hurt)!.hp, 1);
  });

  testWidgets('なぞると、いまの威力と敵の守りが並ぶ', (tester) async {
    final controller = newController();
    await open(tester, controller);
    // 隅に守り3の敵を1体だけ残す。
    paintCheckerboard(controller.board, ward: 3);
    await tester.pump();

    // なぞっていない間は、数字の読み方だけを置いておく。
    expect(find.textContaining('マスの数字は敵の守り'), findsOneWidget);

    // 敵を通していない鎖では、威力だけ。
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    await tester.pump();
    expect(find.text('威力'), findsOneWidget);
    expect(find.text('守り'), findsNothing);

    // 敵のマスを通すと、その守りと、いま届いているかが並ぶ。
    controller.beginPath(const Cell(7, 3));
    controller.extendPath(const Cell(7, 4));
    await tester.pump();
    expect(find.text('守り'), findsNothing);

    controller.extendPath(const Cell(7, 5));
    await tester.pump();
    expect(find.text('守り'), findsOneWidget);
    // 従者だけの一党なので威力＝枚数。3枚で守り3に届く。
    expect(controller.power, 3);
    expect(find.text('討ち取れる'), findsOneWidget);
  });

  testWidgets('威力が守りに届かないうちは、あと何枚かを言う', (tester) async {
    final controller = newController();
    await open(tester, controller);
    paintCheckerboard(controller.board, ward: 6);
    await tester.pump();

    controller.beginPath(const Cell(7, 3));
    controller.extendPath(const Cell(7, 4));
    controller.extendPath(const Cell(7, 5));
    await tester.pump();

    expect(find.text('あと 3 枚で届く'), findsOneWidget);
  });

  testWidgets('とばせる', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(
          onDone: () => done++,
          controller: newController(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('とばす'));
    expect(done, 1);
  });

  group('拠点から出す', () {
    testWidgets('初回だけ出る', (tester) async {
      final store = await openBase(tester, taught: false);
      expect(find.byType(BoardView), findsOneWidget, reason: '稽古場が開く');

      await tester.tap(find.text('とばす'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BoardView), findsNothing);

      // 印が記録に残るので、二度目からは出ない。
      expect((await store.load()).taughtTutorial, isTrue);
    });

    testWidgets('通した記録では出ない', (tester) async {
      await openBase(tester);
      expect(find.byType(BoardView), findsNothing);
      expect(find.text('ダンジョン'), findsOneWidget);
    });

    testWidgets('上の帯からもう一度開ける', (tester) async {
      await openBase(tester);
      expect(find.byType(BoardView), findsNothing);

      await tester.tap(find.byTooltip('あそびかた'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BoardView), findsOneWidget);
    });
  });
}
