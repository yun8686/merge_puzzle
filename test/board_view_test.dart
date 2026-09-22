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
      board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.red : Phase.blue);
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

/// 赤と青の2相だけの一党。この2色なら「直前1枚と違う」＝交互で、
/// 相を入れる前の盤面と規則も手触りも変わらない。市松の盤面を
/// 決め打ちで置くテストは、この2相を前提にしている。
const twoPhases = [Mage.squireRed, Mage.squireBlue];

/// 同じ2相でも、従者ではなく焔と氷雨を連れた一党。従者の印は '赤' '青' で
/// 相の呼び名とぶつかるので、印と相の数を別々に読みたいときはこちら。
/// 焔が居るぶん、赤を3枚以上継いだ鎖には威力が1乗る。
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
const threePhases = [Mage.squireRed, Mage.squireBlue, Mage.squireViolet];

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
    // 赤が5枚あるので焔の補正が乗り、表示される威力は10になる。
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
        controller.board.grid[r][c] = Tile(id: id++, phase: Phase.red);
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

  testWidgets('アプリを開くとタイトルが出て、押すと拠点に入る', (tester) async {
    await tester.pumpWidget(const ParityChainApp());
    await tester.pump();

    expect(find.text('氷炎の鎖'), findsOneWidget);
    expect(find.text('はじめる'), findsOneWidget);
    expect(find.text('ダンジョン'), findsNothing, reason: 'まだ拠点は出ない');

    await tester.tap(find.text('はじめる'));
    await tester.pump();
    // 入れ替えの尺。
    await tester.pump(const Duration(milliseconds: 500));
    // 記録の読み込みの時間切れぶん。保存が使えない環境でも落ちないこと
    // （テストには shared_preferences のプラグインが居ないので、毎回この
    // 経路を通る）。タイトルには repeat のアニメがあるので pumpAndSettle は
    // 使えない――止まらないまま待ち続けることになる。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('ダンジョン'), findsOneWidget);
    expect(find.text('氷炎の鎖'), findsNothing);
    // まっさらな記録なので、初回の稽古場が拠点の上に乗る。
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.text('とばす'), findsOneWidget);
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
    // 残りの敵。手数の制限は無いので、盤面の上に出る数はこれだけ。
    expect(find.text('FOES'), findsOneWidget);
    // 盤面に敷かれた相の比率。呼び名ではなくマスと同じ色で出ていること。
    expect(swatchOf(Phase.red), findsOneWidget);
    expect(swatchOf(Phase.blue), findsOneWidget);
    expect(swatchOf(Phase.violet), findsNothing, reason: '連れていない相');
    expect(find.text(Phase.red.label), findsNothing, reason: '漢字は出さない');
    // 階層をまたいで残る一党。連れてきた顔ぶれが姿で並ぶ。
    expect(find.text('PARTY'), findsOneWidget);
    expect(portraitOf(MageKind.ember), findsOneWidget);
    expect(portraitOf(MageKind.rime), findsOneWidget);
    expect(portraitOf(MageKind.storm), findsNothing, reason: '連れていない');
  });

  testWidgets('一党の姿を押すと能力が開き、連れている全員を見比べられる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          controller: GameController(rng: Random(1), roster: emberPair),
        ),
      ),
    );
    await tester.pump();

    // 潜っている最中に能力を確かめる道はここしか無い（名簿は拠点にある）。
    expect(find.text(Mage.ember.passiveEffect), findsNothing, reason: '押すまでは出ない');

    await tester.tap(find.byKey(const ValueKey('party-ember')));
    await tester.pump();
    expect(find.text(Mage.ember.name), findsOneWidget);
    expect(find.text(Mage.ember.passiveEffect), findsOneWidget);

    // 閉じて開き直さずに、もう1人へ移れる。
    await tester.tap(find.byKey(const ValueKey('sheet-rime')));
    await tester.pump();
    expect(find.text(Mage.rime.passiveEffect), findsOneWidget);
    expect(find.text(Mage.ember.passiveEffect), findsNothing);

    await tester.tap(find.text('閉じる'));
    await tester.pump();
    expect(find.text(Mage.rime.passiveEffect), findsNothing);
  });

  testWidgets('風の札から先読みを使うと、盤面にお手本が出る', (tester) async {
    // 札が縦に伸びるので、はみ出して押せなくならないよう画面を広く取る。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = GameController(
      rng: Random(3),
      roster: const [Mage.gale, Mage.squireBlue],
    );
    paintCheckerboard(controller.board);
    // 隅の敵を薄くして、3枚でも届くようにする。
    final corner = controller.board.grid[7][5]!;
    controller.board.grid[7][5] = Tile(
      id: corner.id,
      phase: corner.phase,
      ward: 3,
    );

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('hint-path')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('party-gale')));
    await tester.pump();
    expect(find.text('先読み'), findsOneWidget);

    await tester.tap(find.text('使う'));
    await tester.pump();

    // 札は閉じ、盤面に道が出る。指は repeat で回るので pumpAndSettle は使えない。
    expect(find.text('先読み'), findsNothing);
    expect(controller.hintPath, isNotEmpty);
    expect(find.byKey(const ValueKey('hint-path')), findsOneWidget);

    // 2回目は押せない。潜り1本に1回だけ。
    await tester.tap(find.byKey(const ValueKey('party-gale')));
    await tester.pump();
    expect(find.text('使う'), findsNothing);
    expect(find.text('この探索ではもう使った'), findsOneWidget);
  });

  testWidgets('先読みが空振りすると、札は開いたままで回数も減らない', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = GameController(
      rng: Random(3),
      roster: const [Mage.gale, Mage.squireBlue],
    );
    // 1色で塗り潰すと3枚も繋がらない。届く道がどこにも無い盤面。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: Phase.red);
      }
    }
    controller.board.grid[0][1] = Tile(id: id++, phase: Phase.red, ward: 3);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('party-gale')));
    await tester.pump();
    await tester.tap(find.text('使う'));
    await tester.pump();

    // 札は開いたまま、なぜ何も起きなかったかを言う。
    expect(find.text('先読み'), findsOneWidget, reason: '閉じない');
    expect(find.textContaining('どのルートも敵に届かなかった'), findsOneWidget);
    expect(find.byKey(const ValueKey('hint-path')), findsNothing);
    // 減っていないので、もう一度押せる。
    expect(find.text('使う'), findsOneWidget);
    expect(controller.party.canUse(MageKind.gale), isTrue);
  });

  testWidgets('延焼を使うと、盤面の下の決まりが入れ替わる', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = GameController(
      rng: Random(3),
      roster: const [Mage.blaze, Mage.squireBlue],
    );
    paintCheckerboard(controller.board);
    // 上の行を赤で揃える。緩めれば継げるが、普段は継げない並び。
    for (var c = 0; c < 3; c++) {
      final base = controller.board.grid[0][c]!;
      controller.board.grid[0][c] = Tile(id: base.id, phase: Phase.red);
    }

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.text('同じ色を続けずに、なぞってつなぐ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('party-blaze')));
    await tester.pump();
    await tester.tap(find.text('使う'));
    await tester.pump(const Duration(milliseconds: 300));

    // 盤面の外で言わないと、押したのに何も起きていないように見える。
    expect(controller.board.spreadPhase, Phase.red);
    expect(find.textContaining('延焼中'), findsOneWidget);
    expect(find.text('同じ色を続けずに、なぞってつなぐ'), findsNothing);
  });

  testWidgets('陥落画面に討ち漏らした敵が5体並ぶ', (tester) async {
    final controller = newController(7);
    // 1色で塗り潰して手詰まりにする。**階層を落とすのはこの形だけ**で、
    // 手数の制限が無くなってからは他に落とし方が無い。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: Phase.red);
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

    controller.isSettling = true;
    controller.settle();
    controller.strike();
    expect(controller.phase, GamePhase.floorLost);
    // 反撃は守りの合計。
    expect(controller.lastBacklash, 26);

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: controller)),
    );
    await tester.pump();

    // 5体ぶんの姿と呼び名が出ること。溢れれば RenderFlex が例外を投げるので、
    // 実機を見られなくても並びが収まっているかはここで分かる。
    expect(find.text('残った敵'), findsOneWidget);
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

  testWidgets('階層を制圧すると戦果が出て、押せば次の階層に進む', (tester) async {
    final controller = newController(5);
    // 威力3で討てる敵を1体だけ置く。1手で制圧できる。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.red : Phase.blue);
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

    // 討ち果たした敵の姿と呼び名。守り3は小鬼。
    expect(find.text('倒した敵'), findsOneWidget);
    expect(find.text(foeNameFor(Board.minWard)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FoeChip),
        matching: find.byType(FoePortrait),
      ),
      findsOneWidget,
    );

    // **ここでは何も選ばせない。** 道中で増えるものは無く、体力もそのまま
    // 持ち越す。押せば次の階層が始まるだけ。
    final hpBefore = controller.party.hp;
    final maxHpBefore = controller.party.maxHp;
    final next = find.text('B2F へ降りる');
    expect(next, findsOneWidget);
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
    await tester.pump();

    expect(controller.floor, 2);
    expect(controller.party.hp, hpBefore);
    expect(controller.party.maxHp, maxHpBefore);
    expect(controller.party.members.length, twoPhases.length);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('お手本の指が道を辿る', (tester) async {
    final controller = newController(1);
    paintCheckerboard(controller.board);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              // 外側で包まない。お手本は手が止まってから出るので、外側の
              // 描き直しに頼ると盤面に出したものが描かれない。BoardView が
              // 自分で controller を購読していることを、ここで見ている。
              child: BoardView(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.showHint();
    expect(controller.hintPath.length, greaterThanOrEqualTo(3));
    await tester.pump();

    // 指はタイルより後に積む。先に積むと不透明なタイルに隠れて出てこない。
    final stack = tester
        .widgetList<Stack>(find.byType(Stack))
        .firstWhere(
          (s) => s.children.any((w) => w.key == const ValueKey('hint-path')),
        );
    final kids = stack.children;
    final hintAt = kids.indexWhere((w) => w.key == const ValueKey('hint-path'));
    final lastTile = kids.lastIndexWhere(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('tile-'),
    );
    expect(hintAt, greaterThan(0));
    expect(lastTile, greaterThan(0));
    expect(hintAt, greaterThan(lastTile));

    // 指は繰り返し道を辿る。止まらないので pumpAndSettle は使えない。
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(tester.takeException(), isNull);

    // 消せば止まる。
    controller.clearHint();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
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
    expect(controller.isStriking, isTrue, reason: '詰んでから間を置いて殴られる');
    expect(controller.party.hp, hpBefore, reason: 'まだ殴られていない');
    controller.strike();
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

  testWidgets('中断は確かめてから、拠点へ戻す', (tester) async {
    final controller = newController(3);
    DungeonOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          controller: controller,
          onFinished: (o) => outcome = o,
        ),
      ),
    );
    await tester.pump();

    // **押してすぐには帰さない。** 取り返しが付かない側なので一度訊く。
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();
    expect(find.text('中断する'), findsOneWidget);
    expect(find.text('B${controller.floor}F'), findsWidgets);
    expect(outcome, isNull);

    // 続ければ盤面に戻る。
    await tester.tap(find.text('続ける'));
    await tester.pump();
    expect(find.text('中断する'), findsNothing);
    expect(outcome, isNull);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();
    await tester.tap(find.text('中断して拠点へ'));
    await tester.pump();

    // 討ち果たしてはいないので、失敗として拠点に返す。
    expect(outcome, isNotNull);
    expect(outcome!.cleared, isFalse);
    expect(outcome!.floor, controller.floor);
    expect(outcome!.dungeonId, controller.dungeon.id);
  });

  testWidgets('戻る先が無ければ中断の札は出ない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: newController(3))),
    );
    await tester.pump();

    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('制圧の画面は、最後の敵を討ってから少し待って出る', (tester) async {
    final controller = newController(5);
    // 威力3で討てる敵を1体だけ置く。1手で制圧できる。
    var id = 0;
    for (var r = 0; r < controller.board.rows; r++) {
      for (var c = 0; c < controller.board.cols; c++) {
        controller.board.grid[r][c] = Tile(id: id++, phase: (r + c).isEven ? Phase.red : Phase.blue);
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
    expect(find.text('B2F へ降りる'), findsNothing);

    // 目の前で討ち果たす。
    controller.beginPath(const Cell(0, 0));
    controller.extendPath(const Cell(0, 1));
    controller.extendPath(const Cell(0, 2));
    controller.commitPath();
    controller.settle();
    await tester.pump();

    // 局面は制圧に移っているが、まだ盤面を覆わない。
    expect(controller.phase, GamePhase.stageCleared);
    expect(find.text('B2F へ降りる'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('B2F へ降りる'), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('B2F へ降りる'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
