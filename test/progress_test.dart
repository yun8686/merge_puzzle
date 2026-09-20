import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/phase.dart';
import 'package:parity_chain/game/progress.dart';

void main() {
  test('始まりは従者3人を持ち、連れていくのは2人', () {
    final progress = Progress();
    expect(progress.owned, {for (final m in Mage.squires) m.kind});
    expect(progress.party, Progress.startingParty);
    expect(progress.party.length, Progress.partySlots - 1, reason: '1枠空いている');
    expect(progress.partyPhases, [Phase.heat, Phase.cold]);
    expect(progress.partyIsValid, isTrue);
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

  test('遊び方を通した印も残る', () {
    expect(Progress().taughtTutorial, isFalse, reason: '始まりは未読');
    final progress = Progress()..taughtTutorial = true;
    expect(Progress.decode(progress.encode()).taughtTutorial, isTrue);
    // 印の無い古い記録は「まだ教えていない」扱い。
    expect(Progress.decode('{"shards":3}').taughtTutorial, isFalse);
  });

  test('壊れた保存は捨てて、まっさらな記録になる', () {
    for (final raw in [null, '', 'not json', '[1,2,3]', '{"owned":5}']) {
      final progress = Progress.decode(raw);
      expect(
        progress.owned,
        containsAll([for (final m in Mage.squires) m.kind]),
        reason: raw ?? 'null',
      );
      expect(progress.partyIsValid, isTrue);
      expect(progress.shards, 0);
    }
  });

  test('持っていない魔導士や重複は、読むときに編成から落ちる', () {
    final progress = Progress.decode(
      '{"owned":["ember"],"party":["storm","ember","ember"],"shards":-5}',
    );
    expect(progress.party, contains(MageKind.ember));
    expect(progress.party, isNot(contains(MageKind.storm)), reason: '未所持');
    expect(progress.party.toSet().length, progress.party.length, reason: '重複しない');
    expect(progress.shards, 0, reason: '負の魔晶は 0 に丸める');
  });

  test('相が1種類しか無い編成は、読むときに直される', () {
    // 熱の魔導士だけを並べた記録。このままでは鎖が1枚も編めない。
    final progress = Progress.decode(
      '{"owned":["ember","blaze"],"party":["ember","blaze"]}',
    );
    expect(progress.partyIsValid, isTrue);
    expect(progress.partyPhases.length, greaterThanOrEqualTo(2));
  });

  test('知らない名前が入っていても落ちない', () {
    final progress = Progress.decode(
      '{"owned":["ember","ghost"],"cleared":["nowhere",7],"party":["ghost"]}',
    );
    expect(progress.owned, contains(MageKind.ember));
    expect(progress.owned, containsAll([for (final m in Mage.squires) m.kind]));
    expect(progress.cleared, {'nowhere'});
    expect(progress.partyIsValid, isTrue);
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
      expect(Mage.summonable, contains(mage), reason: '従者は引かれない');
      expect(progress.owned, contains(mage!.kind));
      expect(progress.shards, 0);
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
      expect(progress.unowned, isEmpty);
    });

    test('空いた枠には、引いた魔導士がそのまま入る', () {
      // 始まりの編成は2人。3枠目が空いている。
      final progress = Progress(shards: Progress.gachaCost * 10);
      expect(progress.party.length, Progress.partySlots - 1);

      final first = progress.roll(Random(3));
      expect(first, isNotNull);
      expect(progress.party, contains(first!.kind));
      expect(progress.party.length, Progress.partySlots);
    });

    test('枠が埋まっていれば、引いた魔導士は編成に入らない', () {
      final progress = Progress(
        owned: {MageKind.storm},
        party: [MageKind.squireHeat, MageKind.squireCold, MageKind.storm],
        shards: Progress.gachaCost * 10,
      );
      expect(progress.party.length, Progress.partySlots);

      final mage = progress.roll(Random(3));
      expect(mage, isNotNull);
      expect(progress.party.length, Progress.partySlots);
      expect(progress.party, isNot(contains(mage!.kind)));
    });
  });

  group('編成', () {
    test('枠が埋まっていれば入らない', () {
      final progress = Progress(
        owned: {for (final m in Mage.roster) m.kind},
        party: [MageKind.squireHeat, MageKind.squireCold, MageKind.squireBolt],
      );
      expect(progress.party.length, Progress.partySlots);

      progress.toggleParty(MageKind.gale);
      expect(progress.party.length, Progress.partySlots, reason: '溢れた人は入らない');
      expect(progress.party, isNot(contains(MageKind.gale)));
    });

    test('入っている人をもう一度押すと外れる', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.rime, MageKind.storm},
        party: [MageKind.ember, MageKind.rime, MageKind.storm],
      );
      // 熱・冷・雷。冷を外しても熱と雷が残るので外せる。
      progress.toggleParty(MageKind.rime);
      expect(progress.party, [MageKind.ember, MageKind.storm]);
    });

    test('外すと1色になる人は外せない', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.blaze, MageKind.storm},
        party: [MageKind.ember, MageKind.blaze, MageKind.storm],
      );
      // 焔と烈火はどちらも熱。雷を外すと熱だけになるので、外せない。
      expect(progress.canDrop(MageKind.storm), isFalse);
      progress.toggleParty(MageKind.storm);
      expect(progress.party, contains(MageKind.storm));

      // 熱が2人居るので、片方は外してよい。
      expect(progress.canDrop(MageKind.blaze), isTrue);
      progress.toggleParty(MageKind.blaze);
      expect(progress.party, [MageKind.ember, MageKind.storm]);
    });

    test('最後の1人は外せない', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.storm},
        party: [MageKind.ember],
      );
      progress.toggleParty(MageKind.ember);
      expect(progress.party, [MageKind.ember]);
    });

    test('持っていない魔導士は編成に入らない', () {
      final progress = Progress(party: [MageKind.squireHeat]);
      progress.toggleParty(MageKind.storm);
      expect(progress.party, [MageKind.squireHeat]);
    });

    test('編成から一党の顔ぶれが出る', () {
      final progress = Progress(
        owned: {MageKind.ember, MageKind.storm},
        party: [MageKind.storm, MageKind.ember],
      );
      expect(progress.partyMages, [Mage.storm, Mage.ember]);
      expect(progress.partyPhases, [Phase.bolt, Phase.heat]);
    });
  });

  test('手元の箱は書いたものをそのまま読み直す', () async {
    final store = MemoryProgressStore();
    final progress = await store.load();
    expect(progress.owned, {for (final m in Mage.squires) m.kind});

    progress.shards = 42;
    progress.owned.add(MageKind.aegis);
    await store.save(progress);

    final back = await store.load();
    expect(back.shards, 42);
    expect(back.owned, contains(MageKind.aegis));
  });

  test('3色の稽古を通した印も保存される', () {
    final progress = Progress();
    expect(progress.taughtPrism, isFalse);
    progress.taughtPrism = true;

    final back = Progress.fromJson(progress.toJson());
    expect(back.taughtPrism, isTrue);
    // 印が無い古い記録は「まだ教えていない」扱い。
    expect(Progress.fromJson(const {}).taughtPrism, isFalse);
  });

  test('編成の相の数を数える', () {
    final two = Progress(
      party: [MageKind.squireHeat, MageKind.squireCold],
    );
    expect(two.partyPhaseCount, 2);

    final three = Progress(
      party: [MageKind.squireHeat, MageKind.squireCold, MageKind.squireBolt],
    );
    expect(three.partyPhaseCount, Progress.prismPhases);
  });
}
