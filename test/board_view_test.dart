import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/main.dart';
import 'package:parity_chain/ui/board_view.dart';

/// 盤面を奇数・偶数の市松模様で塗りつぶす。どの方向にも繋がる状態。
///
/// 隅に、届かない大きさの目標ブロックを1つ置いておく。これが無いと
/// 最初のチェインで目標が尽きてステージクリアになり、演出の確認ができない。
void paintCheckerboard(Board board) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      board.grid[r][c] = Tile(id: id++, isOdd: (r + c).isEven);
    }
  }
  final corner = board.grid[board.rows - 1][board.cols - 1]!;
  board.grid[board.rows - 1][board.cols - 1] = Tile(
    id: corner.id,
    isOdd: corner.isOdd,
    requiredLength: Board.maxRequired,
  );
}

GameController newController(int seed) =>
    GameController(createBoard: () => Board(rng: Random(seed)));

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
    final controller = newController(3);
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

    // 上段を右へ6マス、下段を左へ3マスなぞって9チェインにする。
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

    expect(find.text('POWER 9'), findsOneWidget);
    final popup = tester.element(find.text('POWER 9'));

    // 消えるタイルが1枚ずつ片付く間、スコア表示の要素が作り直されると
    // アニメーションが頭から流れ直し、同じ表示が何度も出てしまう。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('POWER 9'), findsOneWidget);
      expect(identical(tester.element(find.text('POWER 9')), popup), isTrue);
    }

    // 850ms のアニメーションが終われば、繰り返さずに消えること。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('POWER 9'), findsNothing);

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
        controller.board.grid[r][c] = Tile(id: id++, isOdd: true);
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

  testWidgets('アプリが起動して階層と敵の数が表示される', (tester) async {
    await tester.pumpWidget(const ParityChainApp());
    await tester.pump();

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('DEPTH'), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
    // 残りターンと残りの敵。階層の進行がそのまま出ていること。
    expect(find.text('TURNS'), findsOneWidget);
    expect(find.text('FOES'), findsOneWidget);
    // 熱と冷の比率。どちらの枚数も出ていること。
    expect(find.text('HEAT'), findsOneWidget);
    expect(find.text('FROST'), findsOneWidget);
  });
}
