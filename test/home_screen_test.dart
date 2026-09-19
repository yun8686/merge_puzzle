import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/dungeon.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/progress.dart';
import 'package:parity_chain/ui/board_view.dart';
import 'package:parity_chain/ui/home_screen.dart';

/// 拠点は縦に長く、テストの画面には収まらない。押す前に送り込む。
Future<void> tapAt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 記録を差し込んだ拠点を開く。読み込みは非同期なので settle まで進める。
Future<MemoryProgressStore> openBase(
  WidgetTester tester, {
  Progress? progress,
}) async {
  final store = MemoryProgressStore(progress?.encode());
  await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store)));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('拠点に魔晶・一党・ダンジョンが並ぶ', (tester) async {
    await openBase(tester);

    expect(find.text('魔晶'), findsOneWidget);
    expect(find.text('一党'), findsOneWidget);
    expect(find.text('ダンジョン'), findsOneWidget);

    // 名簿は全員ぶん並ぶが、持っていない魔導士は伏せてある。
    expect(find.text(Mage.ember.name), findsOneWidget);
    expect(find.text(Mage.storm.name), findsNothing);
    expect(
      find.text('まだ見ぬ魔導士'),
      findsNWidgets(Mage.roster.length - 1),
    );

    for (final dungeon in Dungeons.all) {
      expect(find.text(dungeon.name), findsOneWidget);
    }
  });

  testWidgets('2本目から先は、前の1本を踏破するまで開かない', (tester) async {
    await openBase(tester);
    expect(
      find.text('${Dungeons.all.first.name} を踏破すると開く'),
      findsOneWidget,
    );

    // 1本目を踏破済みにすると開く。
    await openBase(
      tester,
      progress: Progress(cleared: {Dungeons.all.first.id}),
    );
    expect(find.text('踏破'), findsOneWidget);
    expect(
      find.text('${Dungeons.all.first.name} を踏破すると開く'),
      findsNothing,
    );
  });

  testWidgets('ダンジョンを選ぶと盤面が開く', (tester) async {
    await openBase(tester);

    await tapAt(tester, find.text(Dungeons.all.first.name));

    expect(find.byType(BoardView), findsOneWidget);
    expect(find.text('DEPTH'), findsOneWidget);
    expect(find.text('B1F'), findsOneWidget);
  });

  group('ガチャ', () {
    testWidgets('魔晶が足りなければ引けない', (tester) async {
      await openBase(tester, progress: Progress(shards: 1));
      expect(find.text('魔晶が足りない'), findsOneWidget);

      await tapAt(tester, find.text('魔晶が足りない'));
      expect(find.text('まだ見ぬ魔導士'), findsNWidgets(Mage.roster.length - 1));
    });

    testWidgets('引くと魔導士が増えて、記録に残る', (tester) async {
      final store = await openBase(
        tester,
        progress: Progress(shards: Progress.gachaCost),
      );

      await tapAt(tester, find.text('魔導士を招く'));

      // 伏せられた行が1つ減る。
      expect(find.text('まだ見ぬ魔導士'), findsNWidgets(Mage.roster.length - 2));
      // 魔晶は払われている。
      expect(find.text('0'), findsWidgets);

      final saved = await store.load();
      expect(saved.owned.length, 2);
      expect(saved.shards, 0);
    });

    testWidgets('全員揃えば引けなくなる', (tester) async {
      await openBase(
        tester,
        progress: Progress(
          owned: {for (final m in Mage.roster) m.kind},
          shards: 999,
        ),
      );
      expect(find.text('全員揃った'), findsOneWidget);
      expect(find.text('まだ見ぬ魔導士'), findsNothing);
    });
  });

  group('編成', () {
    testWidgets('押すと編成に入り、もう一度押すと外れる', (tester) async {
      final store = await openBase(
        tester,
        progress: Progress(
          owned: {MageKind.ember, MageKind.storm},
          party: [MageKind.ember],
        ),
      );
      expect(find.text('1 / ${Progress.partySlots}'), findsOneWidget);

      await tapAt(tester, find.text(Mage.storm.name));
      expect(find.text('2 / ${Progress.partySlots}'), findsOneWidget);
      expect((await store.load()).party, [MageKind.ember, MageKind.storm]);

      await tapAt(tester, find.text(Mage.storm.name));
      expect(find.text('1 / ${Progress.partySlots}'), findsOneWidget);
      expect((await store.load()).party, [MageKind.ember]);
    });

    testWidgets('枠が埋まっていれば入らない', (tester) async {
      final owned = {
        MageKind.ember,
        MageKind.rime,
        MageKind.storm,
        MageKind.gale,
      };
      await openBase(
        tester,
        progress: Progress(
          owned: owned,
          party: [MageKind.ember, MageKind.rime, MageKind.storm],
        ),
      );
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);

      await tapAt(tester, find.text(Mage.gale.name));
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);
    });
  });
}
