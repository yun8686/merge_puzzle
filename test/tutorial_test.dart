import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/ui/tutorial.dart';

import 'home_screen_test.dart' show openBase;

/// 案内には repeat のアニメ（鎖が編まれる絵）が居るので pumpAndSettle は
/// 使えない。止まらないまま待ち続けることになる。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('5枚めくると終わる', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(home: TutorialOverlay(onDone: () => done++)),
    );
    await settle(tester);

    expect(find.text('鎖を編む'), findsOneWidget);

    for (final title in ['長いほど強い', '守りを破る', '敵は毎ターン殴ってくる', '編成が盤面を決める']) {
      await tester.tap(find.text('つぎへ'));
      await settle(tester);
      expect(find.text(title), findsOneWidget, reason: title);
    }

    // 最後の1枚だけ、押す口の名前が変わる。
    expect(find.text('つぎへ'), findsNothing);
    await tester.tap(find.text('はじめる'));
    expect(done, 1);
  });

  testWidgets('とばせる', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(home: TutorialOverlay(onDone: () => done++)),
    );
    await settle(tester);

    await tester.tap(find.text('とばす'));
    expect(done, 1);
  });

  group('拠点から出す', () {
    testWidgets('初回だけ出る', (tester) async {
      final store = await openBase(tester, taught: false);
      expect(find.text('鎖を編む'), findsOneWidget);

      await tester.tap(find.text('とばす'));
      await settle(tester);
      expect(find.text('鎖を編む'), findsNothing);

      // 印が記録に残るので、二度目からは出ない。
      expect((await store.load()).taughtTutorial, isTrue);
    });

    testWidgets('通した記録では出ない', (tester) async {
      await openBase(tester);
      expect(find.text('鎖を編む'), findsNothing);
      expect(find.text('ダンジョン'), findsOneWidget);
    });

    testWidgets('上の帯からもう一度開ける', (tester) async {
      await openBase(tester);
      expect(find.text('鎖を編む'), findsNothing);

      await tester.tap(find.byTooltip('あそびかた'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('鎖を編む'), findsOneWidget);
    });
  });
}
