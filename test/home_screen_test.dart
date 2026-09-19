import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/dungeon.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/progress.dart';
import 'package:parity_chain/ui/board_view.dart';
import 'package:parity_chain/ui/home_screen.dart';

/// 拠点は面によっては縦に長い。押す前に送り込む。
Future<void> tapAt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 下のタブで面を切り替える。
Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// 記録を差し込んだ拠点を開く。読み込みは非同期なので settle まで進める。
Future<MemoryProgressStore> openBase(
  WidgetTester tester, {
  Progress? progress,
}) async {
  final store = MemoryProgressStore(progress?.encode());
  // 鍵を変えないと、同じテストで開き直したときに State が使い回されて
  // initState が走らず、前の記録が残ったままになる。
  await tester.pumpWidget(
    MaterialApp(home: HomeScreen(key: UniqueKey(), store: store)),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('拠点は三つの面に分かれ、開くとダンジョンが出る', (tester) async {
    await openBase(tester);

    // 上の帯と下のタブは、どの面でも見えている。
    expect(find.text('魔晶'), findsOneWidget);
    for (final tab in ['ダンジョン', '一党', 'ガチャ']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }

    // 開いた面はダンジョン。
    for (final dungeon in Dungeons.all) {
      expect(find.text(dungeon.name), findsOneWidget);
    }
    // 連れていく顔ぶれは、挑む前にここから見える。
    expect(find.text('連れていく'), findsOneWidget);
  });

  testWidgets('一党の面に名簿が並び、持っていない魔導士は伏せてある', (tester) async {
    await openBase(tester);
    await goTab(tester, '一党');

    // 始まりは従者3人だけ。招ける7人は伏せてある。
    for (final squire in Mage.squires) {
      expect(find.text(squire.name), findsOneWidget, reason: squire.name);
    }
    expect(find.text(Mage.storm.name), findsNothing);
    expect(find.text('未所持'), findsNWidgets(Mage.summonable.length));
    expect(find.text('名簿'), findsOneWidget);
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
      await goTab(tester, 'ガチャ');
      expect(find.text('魔晶が足りない'), findsOneWidget);

      await tapAt(tester, find.text('魔晶が足りない'));
      await goTab(tester, '一党');
      expect(find.text('未所持'), findsNWidgets(Mage.summonable.length));
    });

    testWidgets('引くと魔導士が増えて、記録に残る', (tester) async {
      final store = await openBase(
        tester,
        progress: Progress(shards: Progress.gachaCost),
      );
      await goTab(tester, 'ガチャ');

      await tapAt(tester, find.text('招く　魔晶 ${Progress.gachaCost}'));

      // 引いた相手がその場に出る。
      expect(find.text('直前の招き'), findsOneWidget);

      final saved = await store.load();
      expect(saved.owned.length, Mage.squires.length + 1);
      expect(saved.shards, 0);

      // 名簿の伏せ札が1つ減っている。
      await goTab(tester, '一党');
      expect(find.text('未所持'), findsNWidgets(Mage.summonable.length - 1));
    });

    testWidgets('全員揃えば引けなくなる', (tester) async {
      await openBase(
        tester,
        progress: Progress(
          owned: {for (final m in Mage.roster) m.kind},
          shards: 999,
        ),
      );
      await goTab(tester, 'ガチャ');
      expect(find.text('全員揃った'), findsOneWidget);

      await goTab(tester, '一党');
      expect(find.text('未所持'), findsNothing);
    });
  });

  group('編成', () {
    testWidgets('押すと編成に入り、もう一度押すと外れる', (tester) async {
      // 始まりの編成そのまま。3枠目が空いている。
      final store = await openBase(
        tester,
        progress: Progress(owned: {MageKind.storm}),
      );
      await goTab(tester, '一党');
      expect(find.text('2 / ${Progress.partySlots}'), findsOneWidget);

      await tapAt(tester, find.text(Mage.storm.name));
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);
      expect((await store.load()).party, contains(MageKind.storm));

      await tapAt(tester, find.text(Mage.storm.name));
      expect(find.text('2 / ${Progress.partySlots}'), findsOneWidget);
      expect((await store.load()).party, isNot(contains(MageKind.storm)));
    });

    testWidgets('枠が埋まっていれば入らない', (tester) async {
      await openBase(
        tester,
        progress: Progress(
          owned: {MageKind.gale},
          party: [
            MageKind.squireHeat,
            MageKind.squireCold,
            MageKind.squireBolt,
          ],
        ),
      );
      await goTab(tester, '一党');
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);

      await tapAt(tester, find.text(Mage.gale.name));
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);
    });

    testWidgets('外すと1色になる人は外せない', (tester) async {
      await openBase(
        tester,
        progress: Progress(
          owned: {MageKind.ember, MageKind.blaze},
          // 焔と烈火はどちらも熱。雷の従者が抜けると1色になる。
          party: [MageKind.ember, MageKind.blaze, MageKind.squireBolt],
        ),
      );
      await goTab(tester, '一党');
      expect(find.text('3 / ${Progress.partySlots}'), findsOneWidget);

      await tapAt(tester, find.text(Mage.squireBolt.name));
      expect(
        find.text('3 / ${Progress.partySlots}'),
        findsOneWidget,
        reason: '1色になるので外せない',
      );
    });
  });
}
