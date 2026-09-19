import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/progress.dart';

void main() {
  test('始まりは焔ひとりで、魔晶は無い', () {
    final progress = Progress();
    expect(progress.owned, {MageKind.ember});
    expect(progress.party, [MageKind.ember]);
    expect(progress.shards, 0);
    expect(progress.canRoll, isFalse);
  });

  test('書いて読み直すと同じ記録になる', () {
    final progress = Progress(
      owned: {MageKind.ember, MageKind.storm, MageKind.gale},
      cleared: {'cavern'},
      party: [MageKind.storm, MageKind.ember],
      shards: 27,
    );

    final back = Progress.decode(progress.encode());
    expect(back.owned, progress.owned);
    expect(back.cleared, progress.cleared);
    expect(back.party, progress.party);
    expect(back.shards, 27);
  });

  test('壊れた保存は捨てて、まっさらな記録になる', () {
    for (final raw in [null, '', 'not json', '[1,2,3]', '{"owned":5}']) {
      final progress = Progress.decode(raw);
      expect(progress.owned, {MageKind.ember}, reason: raw ?? 'null');
      expect(progress.party, [MageKind.ember]);
      expect(progress.shards, 0);
    }
  });

  test('持っていない魔導士や重複は、読むときに編成から落ちる', () {
    final progress = Progress.decode(
      '{"owned":["ember"],"party":["storm","ember","ember"],"shards":-5}',
    );
    expect(progress.party, [MageKind.ember], reason: '所持していない storm は落ちる');
    expect(progress.shards, 0, reason: '負の魔晶は 0 に丸める');
  });

  test('知らない名前が入っていても落ちない', () {
    final progress = Progress.decode(
      '{"owned":["ember","ghost"],"cleared":["nowhere",7],"party":["ghost"]}',
    );
    expect(progress.owned, {MageKind.ember});
    expect(progress.cleared, {'nowhere'});
    expect(progress.party, [MageKind.ember]);
  });

  group('魔晶', () {
    test('初回の踏破は厚く、2回目からは薄い', () {
      final progress = Progress();
      expect(progress.recordClear('cavern'), Progress.firstClearReward);
      expect(progress.shards, Progress.firstClearReward);

      expect(progress.recordClear('cavern'), Progress.repeatClearReward);
      expect(
        progress.shards,
        Progress.firstClearReward + Progress.repeatClearReward,
      );
      expect(progress.hasCleared('cavern'), isTrue);
      expect(progress.hasCleared('lair'), isFalse);
    });

    test('失敗しても降りた階層のぶんは残る', () {
      final progress = Progress();
      expect(progress.recordFailure(4), 4);
      expect(progress.shards, 4);
    });
  });

  group('ガチャ', () {
    test('値段が足りなければ引けない', () {
      final progress = Progress(shards: Progress.gachaCost - 1);
      expect(progress.canRoll, isFalse);
      expect(progress.roll(Random(1)), isNull);
      expect(progress.shards, Progress.gachaCost - 1, reason: '減らない');
    });

    test('引くと未所持から1人増えて、値段を払う', () {
      final progress = Progress(shards: Progress.gachaCost);
      final mage = progress.roll(Random(1));

      expect(mage, isNotNull);
      expect(mage!.kind, isNot(MageKind.ember), reason: '未所持からしか出ない');
      expect(progress.owned, contains(mage.kind));
      expect(progress.shards, 0);
      // 枠が空いていればそのまま編成に入る。
      expect(progress.party, contains(mage.kind));
    });

    test('全員揃えば引けなくなる', () {
      final progress = Progress(
        owned: {for (final m in Mage.roster) m.kind},
        shards: 999,
      );
      expect(progress.unowned, isEmpty);
      expect(progress.canRoll, isFalse);
      expect(progress.roll(Random(1)), isNull);
      expect(progress.shards, 999);
    });

    test('引き続ければ名簿は必ず全部揃う', () {
      final progress = Progress(shards: Progress.gachaCost * 100);
      final rng = Random(7);
      while (progress.canRoll) {
        progress.roll(rng);
      }
      expect(progress.owned.length, Mage.roster.length);
    });

    test('枠が埋まっていれば、引いた魔導士は編成に入らない', () {
      final progress = Progress(shards: Progress.gachaCost * 10);
      final rng = Random(3);
      while (progress.party.length < Progress.partySlots && progress.canRoll) {
        progress.roll(rng);
      }
      expect(progress.party.length, Progress.partySlots);

      final mage = progress.roll(rng);
      expect(mage, isNotNull);
      expect(progress.party.length, Progress.partySlots);
      expect(progress.party, isNot(contains(mage!.kind)));
    });
  });

  group('編成', () {
    test('枠のぶんまで入れられ、溢れたら入らない', () {
      final progress = Progress(
        owned: {for (final m in Mage.roster) m.kind},
      );
      progress.toggleParty(MageKind.rime);
      progress.toggleParty(MageKind.storm);
      expect(progress.party.length, Progress.partySlots);

      progress.toggleParty(MageKind.gale);
      expect(progress.party.length, Progress.partySlots, reason: '溢れた人は入らない');
      expect(progress.party, isNot(contains(MageKind.gale)));
    });

    test('入っている人をもう一度押すと外れる', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.rime},
        party: [MageKind.ember, MageKind.rime],
      );
      progress.toggleParty(MageKind.rime);
      expect(progress.party, [MageKind.ember]);
    });

    test('最後の1人は外せない', () {
      final progress = Progress();
      progress.toggleParty(MageKind.ember);
      expect(progress.party, [MageKind.ember]);
    });

    test('持っていない魔導士は編成に入らない', () {
      final progress = Progress();
      progress.toggleParty(MageKind.storm);
      expect(progress.party, [MageKind.ember]);
    });

    test('編成から一党の顔ぶれが出る', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.storm},
        party: [MageKind.storm, MageKind.ember],
      );
      expect(progress.partyMages, [Mage.storm, Mage.ember]);
    });
  });

  test('手元の箱は書いたものをそのまま読み直す', () async {
    final store = MemoryProgressStore();
    final progress = await store.load();
    expect(progress.owned, {MageKind.ember});

    progress.shards = 42;
    progress.owned.add(MageKind.aegis);
    await store.save(progress);

    final back = await store.load();
    expect(back.shards, 42);
    expect(back.owned, {MageKind.ember, MageKind.aegis});
  });
}
