import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/board.dart';
import 'package:parity_chain/game/game_controller.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/ui/board_view.dart';
import 'package:parity_chain/ui/tutorial.dart';

import 'home_screen_test.dart' show openBase;

/// 稽古場と同じ顔ぶれ・同じ階層で組む。差し込めるので、どの稽古まで進んだ
/// ところからでも見られる。
GameController newController() => GameController(
  rng: Random(4),
  dungeon: TutorialScreen.dungeon,
  roster: const [Mage.squireRed, Mage.squireBlue],
);

/// いま決められている道をそのままなぞって離す。盤面が詰んで、反撃まで済む。
void traceRoute(GameController c) {
  final route = List<Cell>.of(c.lockedPath);
  c.beginPath(route.first);
  for (final cell in route.skip(1)) {
    c.extendPath(cell);
  }
  c.commitPath();
  c.settle();
  c.strike();
}

/// 盤面に残っている、体力を持つ敵（＝体力の稽古の教材）。
Cell? toughFoe(Board board) {
  for (final at in board.foeCells) {
    if (board.tileAt(at)!.maxHp > 1) return at;
  }
  return null;
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
  testWidgets('本物の盤面と、なぞる道が用意されている', (tester) async {
    final controller = newController();
    await open(tester, controller);

    expect(find.byType(BoardView), findsOneWidget, reason: '本物の盤面');
    expect(find.textContaining('光っている道を3枚なぞろう'), findsOneWidget);
    // 下の目盛りは盤面の画面と同じ読み方。
    expect(find.text('体力'), findsOneWidget);
    expect(find.text('敵'), findsOneWidget);

    // 道は決まっていて、お手本はその道そのもの。
    expect(controller.lockedPath.length, 3);
    expect(controller.hintPath, controller.lockedPath);
  });

  testWidgets('決めた道の外はなぞれない', (tester) async {
    final controller = newController();
    await open(tester, controller);
    final route = controller.lockedPath;

    // 始まりも1つに決まっている。
    controller.beginPath(const Cell(0, 0));
    expect(controller.path, isEmpty);

    controller.beginPath(route.first);
    expect(controller.path.length, 1);

    // 隣で、相も繋がるマスでも、道から外れていれば継げない。
    final off = Cell(route.first.row - 1, route.first.col);
    expect(controller.extendPath(off), isFalse);
    expect(controller.isCandidate(off), isFalse);
    expect(controller.path.length, 1);

    // 次の1マスだけが継げる。
    expect(controller.isCandidate(route[1]), isTrue);
    expect(controller.extendPath(route[1]), isTrue);
  });

  testWidgets('途中で離しても何も起きない', (tester) async {
    final controller = newController();
    await open(tester, controller);

    controller.beginPath(controller.lockedPath.first);
    controller.extendPath(controller.lockedPath[1]);
    expect(controller.commitPath(), isNull);

    expect(controller.path, isEmpty);
    expect(controller.chains, 0, reason: '鎖も増えない');
  });

  testWidgets('なぞり切ると次の稽古に移る', (tester) async {
    final controller = newController();
    await open(tester, controller);

    traceRoute(controller);
    await tester.pump();

    expect(find.textContaining('光っている道を3枚なぞろう'), findsNothing);
    expect(find.textContaining('6枚つないでみよう'), findsOneWidget);
    expect(controller.lockedPath.length, 6);
    // 片付いた手応えが一度だけ出る。
    expect(find.text('できた'), findsOneWidget);
  });

  testWidgets('まとめて当てる稽古では、2体を通る道が出る', (tester) async {
    final controller = newController();
    await open(tester, controller);

    // 鎖を編む → 長いほど強い → 守りを破る。
    for (var i = 0; i < 3; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    expect(find.textContaining('2体を通る道をなぞろう'), findsOneWidget);
    final onRoute = controller.lockedPath
        .where((c) => controller.board.tileAt(c)!.isFoe)
        .length;
    expect(onRoute, 2, reason: '道が敵を2体通っている');
    // この稽古に体力持ちは混ぜない。片方だけ残ると、なぜ残ったのか分からない。
    expect(toughFoe(controller.board), isNull);

    // 3つ目の稽古までに1体討っているので、増えたぶんを数える。
    final felled = controller.felledWards.length;
    traceRoute(controller);
    await tester.pump();

    // 2体とも討ち取れる。体力の話は、次の稽古で1体だけを相手にする。
    expect(controller.felledWards.length - felled, 2);
    expect(find.textContaining('体力が2ある'), findsOneWidget);
  });

  testWidgets('体力のある敵は、1体だけを相手に分けて教える', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 4; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    // 体力2の敵と、盤面を空にしないための控えだけ。道は体力持ちを通る。
    final tough = toughFoe(controller.board);
    expect(tough, isNotNull);
    expect(controller.board.tileAt(tough!)!.hp, 2);
    expect(controller.lockedPath, contains(tough));
    final route = List.of(controller.lockedPath);

    // 1本目は守りを破るが、削り切れない。
    traceRoute(controller);
    await tester.pump();

    final hurt = toughFoe(controller.board);
    expect(hurt, isNotNull);
    expect(controller.board.tileAt(hurt!)!.hp, 1, reason: '傷が残る');
    expect(find.textContaining('与えたダメージはそのまま残る'), findsOneWidget);
    // 次の道は形が違う。同じなのは道ではなく、当てる敵のほう。
    expect(controller.lockedPath, contains(hurt));
    expect(controller.lockedPath, isNot(route));

    final felled = controller.felledWards.length;
    traceRoute(controller);
    await tester.pump();

    // 2本目で討ち切れる。次の稽古が始まっているので、盤面ではなく戦果を見る。
    expect(controller.felledWards.length - felled, 1, reason: '削り切った');
    expect(controller.felledWards, contains(TutorialScreen.toughWard));
    expect(find.textContaining('一撃で倒そう'), findsOneWidget);
  });

  testWidgets('威力が守りを上回れば、体力2でも一撃で討てる', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 6; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    expect(find.textContaining('一撃で倒そう'), findsOneWidget);
    final tough = toughFoe(controller.board);
    expect(tough, isNotNull);
    expect(controller.board.tileAt(tough!)!.hp, 2, reason: '傷のない体力2');
    // 守り5に威力6。上回った2つぶんが削れて、体力2がそのまま尽きる。
    expect(controller.lockedPath.length, 6);
    expect(controller.lockedPath, contains(tough));

    final felled = controller.felledWards.length;
    traceRoute(controller);
    await tester.pump();

    expect(controller.felledWards.length - felled, 1);
    expect(toughFoe(controller.board), isNull, reason: '1本で討ち切った');
  });

  testWidgets('通しでなぞると終いの言葉が出る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 8; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    expect(controller.remainingFoes, 0);
    expect(find.text('ひととおり覚えた'), findsOneWidget);
    expect(find.textContaining('連れていった魔導士で決まる'), findsOneWidget);
    // 盤面では試せない話も言い添えてから送り出す。
    expect(find.textContaining('体力は持ち越し'), findsOneWidget);
    expect(find.text('拠点へ'), findsOneWidget);

    // 覚えたことが順に並ぶ。あっさり閉じると何も残らない。
    for (final label in [
      'チェインをつなぐ',
      '長いほど強い',
      '防御を破る',
      'まとめて当てる',
      '体力のある敵',
      '削り切る',
      '一撃で倒す',
      '毎ターンの反撃',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // 出そろうまで描き続けても例外が出ないこと。
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('お手本の指は、なぞっている間だけ引っ込む', (tester) async {
    final controller = newController();
    await open(tester, controller);
    expect(controller.hintPath, isNotEmpty);

    controller.beginPath(controller.lockedPath.first);
    expect(controller.hintPath, isEmpty);

    // 離せば戻る。稽古場は覚えるための場所なので、待たせない。
    controller.cancelPath();
    expect(controller.hintPath, controller.lockedPath);
  });

  testWidgets('なぞると、いまの威力と敵の守りが並ぶ', (tester) async {
    final controller = newController();
    await open(tester, controller);
    // 守りを破る稽古まで進める。道の終わりが守り3の敵。
    for (var i = 0; i < 2; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    // 敵を通す前は威力だけ。
    controller.beginPath(controller.lockedPath.first);
    controller.extendPath(controller.lockedPath[1]);
    await tester.pump();
    expect(find.text('威力'), findsOneWidget);
    expect(find.text('防御'), findsNothing);

    // 敵のマスまで継ぐと、その守りと、届いているかが並ぶ。
    controller.extendPath(controller.lockedPath[2]);
    await tester.pump();
    expect(find.text('防御'), findsOneWidget);
    expect(controller.power, 3);
    expect(find.text('倒せる'), findsOneWidget);
  });

  testWidgets('威力が守りに届かないうちは、あと何枚かを言う', (tester) async {
    final controller = newController();
    await open(tester, controller);
    // まとめて当てる稽古。道の1枚目が守り3の敵。
    for (var i = 0; i < 3; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    controller.beginPath(controller.lockedPath.first);
    await tester.pump();

    expect(find.text('あと 2 枚で届く'), findsOneWidget);
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
