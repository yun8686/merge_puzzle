import 'package:flutter_test/flutter_test.dart';
import 'package:parity_chain/game/party.dart';
import 'package:parity_chain/game/phase.dart';

/// 鎖1本ぶんの戦果を手で組む。盤面は要らない。
ChainTally tally({
  required int length,
  Map<Phase, int> counts = const {},
  Phase? startPhase,
}) => ChainTally(length: length, counts: counts, startPhase: startPhase);

Party partyOf(List<Mage> members) =>
    Party(members: List.of(members), hp: 30, maxHp: 30);

void main() {
  group('能力の書き方', () {
    test('説明文は条件と効き目から作られる', () {
      // 手で書いた文ではないので、数値を変えれば文も動く。
      expect(Mage.ember.effect, '熱を3枚以上継いだ鎖は威力 +1');
      expect(Mage.blaze.effect, '熱を5枚以上継いだ鎖は威力 +2');
      expect(Mage.gale.effect, '7枚以上継いだ鎖はターンを 1 返す');
      expect(Mage.rime.effect, '冷を3枚以上継いだ鎖で体力を 1 戻す');
      expect(Mage.frost.effect, '冷から継ぎ始めた鎖は威力 +1');
      expect(Mage.storm.effect, '8枚以上継いだ鎖は階層の敵すべてに 1 ダメージ');
      expect(Mage.aegis.effect, '階層を落としたときの痛手が半分になる');
    });

    test('説明文には条件の枚数がそのまま出る', () {
      // 定数を動かしたのに文が古いまま、という食い違いが起きない。
      expect(Mage.ember.effect, contains('$emberSame枚'));
      expect(Mage.blaze.effect, contains('$blazeSame枚'));
      expect(Mage.rime.effect, contains('$rimeSame枚'));
      expect(Mage.gale.effect, contains('$galeChain枚'));
      expect(Mage.storm.effect, contains('$stormChain枚'));
    });

    test('従者は能力を持たない', () {
      for (final squire in Mage.squires) {
        expect(squire.ability, isNull, reason: squire.name);
        expect(squire.effect, '特殊な力は持たない');
      }
    });

    test('招ける7人は全員が能力を持つ', () {
      for (final mage in Mage.summonable) {
        expect(mage.ability, isNotNull, reason: mage.name);
        expect(mage.effect, isNot('特殊な力は持たない'), reason: mage.name);
      }
    });
  });

  group('条件', () {
    test('自分の相の枚数', () {
      const trigger = SamePhase(3);
      expect(trigger.met(Phase.heat, tally(length: 5, counts: {Phase.heat: 3})), isTrue);
      expect(trigger.met(Phase.heat, tally(length: 5, counts: {Phase.heat: 2})), isFalse);
      // 見るのは自分の相だけ。他の相が何枚あっても関係しない。
      expect(
        trigger.met(Phase.cold, tally(length: 9, counts: {Phase.heat: 9})),
        isFalse,
      );
    });

    test('鎖の長さ', () {
      const trigger = ChainLength(7);
      expect(trigger.met(Phase.bolt, tally(length: 7)), isTrue);
      expect(trigger.met(Phase.bolt, tally(length: 6)), isFalse);
    });

    test('継ぎ始めた相', () {
      const trigger = StartsWith();
      expect(trigger.met(Phase.cold, tally(length: 2, startPhase: Phase.cold)), isTrue);
      expect(trigger.met(Phase.cold, tally(length: 2, startPhase: Phase.heat)), isFalse);
      expect(trigger.met(Phase.cold, ChainTally.none), isFalse, reason: '空の鎖');
    });

    test('常に効く条件は空の鎖でも通る', () {
      expect(const Always().met(Phase.bolt, ChainTally.none), isTrue);
    });
  });

  group('効き目の集計', () {
    test('威力は応えた全員ぶんが足し合わされる', () {
      final party = partyOf([Mage.ember, Mage.blaze]);
      // 熱3枚では焔だけ。
      expect(
        party.powerBonusFor(tally(length: 5, counts: {Phase.heat: 3})),
        1,
      );
      // 熱5枚で烈火も乗る。+1 と +2 で +3。
      expect(
        party.powerBonusFor(tally(length: 9, counts: {Phase.heat: 5})),
        3,
      );
    });

    test('相の違う威力補正も同じ足し算に入る', () {
      final party = partyOf([Mage.ember, Mage.frost]);
      final chain = tally(
        length: 6,
        counts: {Phase.heat: 3, Phase.cold: 3},
        startPhase: Phase.cold,
      );
      expect(party.powerBonusFor(chain), 2, reason: '焔 +1・霜 +1');
    });

    test('居ない魔導士のぶんは乗らない', () {
      final party = partyOf([Mage.squireHeat, Mage.squireCold]);
      expect(
        party.powerBonusFor(tally(length: 9, counts: {Phase.heat: 5})),
        0,
      );
      expect(party.turnGainFor(tally(length: 9)), 0);
      expect(party.boltFor(tally(length: 9)), 0);
      expect(party.healFor(tally(length: 9, counts: {Phase.cold: 5})), 0);
    });

    test('ターン・体力・雷も同じ形で数える', () {
      final party = partyOf([Mage.gale, Mage.rime, Mage.storm]);
      expect(party.turnGainFor(tally(length: galeChain)), 1);
      expect(party.turnGainFor(tally(length: galeChain - 1)), 0);
      expect(party.healFor(tally(length: 6, counts: {Phase.cold: rimeSame})), 1);
      expect(party.boltFor(tally(length: stormChain)), 1);
      expect(party.boltFor(tally(length: stormChain - 1)), 0, reason: '枚数で見る');
    });

    test('盾は鎖と関係なく効く', () {
      expect(partyOf([Mage.aegis]).backlashFor(9), 5, reason: '切り上げて半分');
      expect(partyOf([Mage.squireHeat]).backlashFor(9), 9);
    });
  });
}
