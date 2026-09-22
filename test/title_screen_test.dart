import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/ui/title_screen.dart';

void main() {
  testWidgets('題と一言、始める口が出る', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onStart: () {})));
    await tester.pump();

    expect(find.text('氷炎の鎖'), findsOneWidget);
    expect(find.text('FROSTFIRE CHAIN'), findsOneWidget);
    expect(find.text('同じ色を避けてつなぎ、防御を破って敵を倒す'), findsOneWidget);
    expect(find.text('はじめる'), findsOneWidget);
  });

  testWidgets('押すと始まる', (tester) async {
    var started = 0;
    await tester.pumpWidget(
      MaterialApp(home: TitleScreen(onStart: () => started++)),
    );
    await tester.pump();

    await tester.tap(find.text('はじめる'));
    expect(started, 1);
  });

  testWidgets('地が画面いっぱいに広がる', (tester) async {
    // Stack を既定の loose のままにすると、大きさが題とボタンの Column に
    // 合わせて決まり、地が画面の中ほどの細い帯にしかならない。
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onStart: () {})));
    await tester.pump();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getSize(find.byKey(const ValueKey('title-backdrop'))),
      screen,
    );
  });

  testWidgets('鎖が編まれる絵が走り続けても落ちない', (tester) async {
    // 題の上のマスは順に灯って繋がり、消えてまた繰り返す。repeat なので
    // pumpAndSettle は使えない。1周ぶん描いて例外が出ないことだけ見る。
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onStart: () {})));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}
