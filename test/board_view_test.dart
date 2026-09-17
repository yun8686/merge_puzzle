import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/main.dart';
import 'package:parity_chain/ui/board_view.dart';

/// 盤面を奇数・偶数の市松模様で塗りつぶす。どの方向にも繋がる状態。
void paintCheckerboard(Board board) {
  var id = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      board.grid[r][c] = Tile(id: id++, value: (r + c).isEven ? 1 : 2);
    }
  }
}

void main() {
  testWidgets('なぞるとチェインが成立して点が入る', (tester) async {
    final controller = GameController(board: Board(rng: Random(1)));
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

  testWidgets('偶奇が同じマスへは伸びない', (tester) async {
    final controller = GameController(board: Board(rng: Random(2)));
    // 全部奇数にすると、どこへも繋がらない。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, value: 1);
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

  testWidgets('アプリが起動してスコアが表示される', (tester) async {
    await tester.pumpWidget(const ParityChainApp());
    await tester.pump();

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('BEST'), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
  });
}
