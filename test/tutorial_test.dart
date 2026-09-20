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

/// 稽古場と同じ顔ぶれ・同じ階層で組む。差し込めるので、どの稽古まで進んだ
/// ところからでも見られる。
GameController newController() => GameController(
  rng: Random(4),
  dungeon: TutorialScreen.dungeon,
  roster: const [Mage.squireHeat, Mage.squireCold],
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

/// 盤面に残っている、守りの厚い敵（＝盤面を崩す稽古の教材）。
Cell? thickFoe(Board board) {
  for (final at in board.foeCells) {
    if (board.tileAt(at)!.ward == TutorialScreen.thickWard) return at;
  }
  return null;
}

/// 3色の稽古場と同じ顔ぶれ・同じ階層で組む。
GameController prismController() => GameController(
  rng: Random(4),
  dungeon: TutorialScreen.prismDungeon,
  roster: TutorialScreen.rosterFor(TutorialCourse.prism),
);

/// いま決められている道が通る相。**2色で編む道か、3色を巡る道か**が分かる。
Set<Phase> phasesOnRoute(GameController c) => {
  for (final cell in c.lockedPath) c.board.tileAt(cell)!.phase,
};

Future<void> openPrism(WidgetTester tester, GameController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TutorialScreen(
        onDone: () {},
        controller: controller,
        course: TutorialCourse.prism,
      ),
    ),
  );
  await tester.pump();
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
    expect(find.text('残り手数'), findsOneWidget);

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
    final moves = controller.movesLeft;

    controller.beginPath(controller.lockedPath.first);
    controller.extendPath(controller.lockedPath[1]);
    expect(controller.commitPath(), isNull);

    expect(controller.path, isEmpty);
    expect(controller.chains, 0);
    expect(controller.movesLeft, moves, reason: '手数も減らない');
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
    expect(find.textContaining('体力を2つ持っている'), findsOneWidget);
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
    expect(find.textContaining('つけた傷はそのまま残る'), findsOneWidget);
    // 次の道は形が違う。同じなのは道ではなく、当てる敵のほう。
    expect(controller.lockedPath, contains(hurt));
    expect(controller.lockedPath, isNot(route));

    final felled = controller.felledWards.length;
    traceRoute(controller);
    await tester.pump();

    // 2本目で討ち切れる。次の稽古が始まっているので、盤面ではなく戦果を見る。
    expect(controller.felledWards.length - felled, 1, reason: '削り切った');
    expect(controller.felledWards, contains(TutorialScreen.toughWard));
    expect(find.textContaining('一撃で討とう'), findsOneWidget);
  });

  testWidgets('威力が守りを上回れば、体力2でも一撃で討てる', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 6; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    expect(find.textContaining('一撃で討とう'), findsOneWidget);
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

  testWidgets('届かない鎖でも、消せば並びが変わって届くようになる', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 7; i++) {
      traceRoute(controller);
      await tester.pump();
    }

    // 守り8。3枚では弾かれる。
    expect(find.textContaining('いまの道では届かない'), findsOneWidget);
    final thick = thickFoe(controller.board);
    expect(thick, isNotNull);
    expect(controller.lockedPath.length, 3);
    expect(controller.lockedPath, contains(thick));

    final felled = controller.felledWards.length;
    traceRoute(controller);
    await tester.pump();

    // 敵は無傷のまま残り、通したマナだけが消えている。
    final still = thickFoe(controller.board);
    expect(still, isNotNull, reason: '弾かれたので残る');
    expect(controller.felledWards.length, felled);

    // 次の稽古では、同じ敵に8枚で届く。
    expect(find.textContaining('今度は8枚つなげる'), findsOneWidget);
    expect(controller.lockedPath.length, 8);
    expect(controller.lockedPath, contains(still));

    traceRoute(controller);
    await tester.pump();

    expect(thickFoe(controller.board), isNull, reason: '討ち取った');
    expect(controller.felledWards, contains(TutorialScreen.thickWard));
  });

  testWidgets('通しでなぞると終いの言葉が出る', (tester) async {
    final controller = newController();
    await open(tester, controller);
    for (var i = 0; i < 10; i++) {
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
      '鎖を編む',
      '長いほど強い',
      '守りを破る',
      'まとめて当てる',
      '体力のある敵',
      '削り切る',
      '一撃で討つ',
      '届かないとき',
      '並びを変えて討つ',
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
    expect(find.text('守り'), findsNothing);

    // 敵のマスまで継ぐと、その守りと、届いているかが並ぶ。
    controller.extendPath(controller.lockedPath[2]);
    await tester.pump();
    expect(find.text('守り'), findsOneWidget);
    expect(controller.power, 3);
    expect(find.text('討ち取れる'), findsOneWidget);
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

  group('3色の稽古', () {
    testWidgets('2色で編む道から始まる', (tester) async {
      final controller = prismController();
      await openPrism(tester, controller);

      expect(controller.board.phases.length, 3, reason: '盤面は3色');
      expect(find.textContaining('使う相が2つだけなら'), findsOneWidget);
      // 道は3色の盤面の上を、2色だけで往復する。
      expect(controller.lockedPath.length, 5);
      expect(phasesOnRoute(controller).length, 2);

      traceRoute(controller);
      await tester.pump();
      expect(controller.chains, 1, reason: '交互で成立する');
    });

    testWidgets('3つ目を踏む道は、3色を順に巡る', (tester) async {
      final controller = prismController();
      await openPrism(tester, controller);
      traceRoute(controller);
      await tester.pump();

      expect(find.textContaining('直前2枚と同じ相は継げない'), findsOneWidget);
      expect(controller.lockedPath.length, 6);
      expect(phasesOnRoute(controller).length, 3);

      traceRoute(controller);
      await tester.pump();
      expect(controller.chains, 2, reason: '巡回で成立する');
    });

    testWidgets('7枚で厚い守りを破って終わる', (tester) async {
      final controller = prismController();
      await openPrism(tester, controller);
      for (var i = 0; i < 2; i++) {
        traceRoute(controller);
        await tester.pump();
      }

      expect(find.textContaining('守り6の敵を討ち取ろう'), findsOneWidget);
      expect(controller.lockedPath.length, 7);
      expect(phasesOnRoute(controller).length, 3);

      traceRoute(controller);
      await tester.pump();

      expect(controller.felledWards, contains(6));
      expect(controller.remainingFoes, 0);
      // 締めは3色の話だけ。潜り方や編成の話はここでは出さない。
      expect(find.text('3色を覚えた'), findsOneWidget);
      expect(find.textContaining('雷の魔導士は、3色の盤面でだけ'), findsOneWidget);
      expect(find.textContaining('体力は持ち越し'), findsNothing);
    });
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
