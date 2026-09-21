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

/// 盤面の代わり。**押して使う力が何を頼んだかだけ数える。**
///
/// `party.dart` は盤面を読まないので、力の試験に盤面は要らない。
class _FakeStage implements ActiveStage {
  int revealed = 0;

  /// 延焼を頼まれた相。頼まれていなければ null。
  Phase? spreadTo;

  /// 舞台が「できた」と答えるか。
  bool answer = true;

  @override
  bool revealBestRoute() {
    revealed++;
    return answer;
  }

  @override
  bool spread(Phase phase) {
    spreadTo = phase;
    return answer;
  }
}

void main() {
  group('スキルの書き方', () {
    test('説明文は条件と効き目から作られる', () {
      // 手で書いた文ではないので、数値を変えれば文も動く。
      expect(Mage.ember.passiveEffect, '赤を3枚以上継いだ鎖は威力 +1');
      expect(Mage.blaze.passiveEffect, '赤を5枚以上継いだ鎖は威力 +2');
      expect(Mage.gale.passiveEffect, '7枚以上継いだ鎖を編んだ手は反撃を受けない');
      expect(Mage.rime.passiveEffect, '青を3枚以上継いだ鎖で体力を 3 戻す');
      expect(Mage.frost.passiveEffect, '青から継ぎ始めた鎖は威力 +1');
      expect(Mage.storm.passiveEffect, '3色を含む8枚以上継いだ鎖は階層の敵すべてに 1 ダメージ');
      expect(Mage.aegis.passiveEffect, '受ける痛手が半分になる');
    });

    test('説明文には効き目の数値もそのまま出る', () {
      // 定数を動かしたのに文が古いまま、という食い違いが起きない。
      expect(Mage.rime.passiveEffect, contains('体力を $rimeMend 戻す'));
    });

    test('説明文には条件の枚数がそのまま出る', () {
      // 定数を動かしたのに文が古いまま、という食い違いが起きない。
      expect(Mage.ember.passiveEffect, contains('$emberSame枚'));
      expect(Mage.blaze.passiveEffect, contains('$blazeSame枚'));
      expect(Mage.rime.passiveEffect, contains('$rimeSame枚'));
      expect(Mage.gale.passiveEffect, contains('$galeChain枚'));
      expect(Mage.storm.passiveEffect, contains('$stormChain枚'));
    });

    test('アクティブスキルは、条件と効き目の組とは別に持つ', () {
      // 鎖を見ないので [Passive] には収まらない。
      expect(Mage.gale.active, isA<Foresee>());
      expect(Mage.gale.active!.name, '先読み');
      expect(Mage.blaze.active, isA<Spread>());
      expect(Mage.blaze.active!.name, '延焼');
      const withActive = {MageKind.gale, MageKind.blaze};
      for (final mage in Mage.roster) {
        if (withActive.contains(mage.kind)) continue;
        expect(mage.active, isNull, reason: mage.name);
      }
    });

    test('スキルには名前がある。名前だけは手で付ける', () {
      // 効き目の文は組から作れるが、名前はそこからは出てこない。
      // 呼び名が無いと、画面でも会話でも「風のあれ」としか指せない。
      expect(Mage.blaze.passiveName, '業火');
      expect(Mage.aegis.passiveName, '鉄壁');
      expect(Mage.gale.activeName, '先読み');
      expect(Mage.blaze.activeName, '延焼');
      expect(Mage.squireRed.passiveName, isNull, reason: '従者は持たない');
      expect(Mage.ember.activeName, isNull, reason: '持たない者は null');
    });

    test('アクティブスキルの説明にも、持ち主の相が入る', () {
      // 力の側は誰のものかを知らない。相を受け取るから、同じ力を別の相の
      // 魔導士に持たせても文が付いてくる。
      expect(Mage.blaze.activeEffect, '次の1本だけ、赤どうしを継げるようになる');
      expect(
        const Spread().describe(Phase.blue),
        '次の1本だけ、青どうしを継げるようになる',
      );
      expect(Mage.ember.activeEffect, isNull, reason: '持たない者は null');
    });

    test('従者はスキルを持たない', () {
      for (final squire in Mage.squires) {
        expect(squire.passive, isNull, reason: squire.name);
        expect(squire.passiveEffect, '特殊な力は持たない');
      }
    });

    test('招ける7人は全員がパッシブスキルを持つ', () {
      for (final mage in Mage.summonable) {
        expect(mage.passive, isNotNull, reason: mage.name);
        expect(mage.passiveEffect, isNot('特殊な力は持たない'), reason: mage.name);
      }
    });
  });

  group('条件', () {
    test('自分の相の枚数', () {
      const trigger = SamePhase(3);
      expect(trigger.met(Phase.red, tally(length: 5, counts: {Phase.red: 3})), isTrue);
      expect(trigger.met(Phase.red, tally(length: 5, counts: {Phase.red: 2})), isFalse);
      // 見るのは自分の相だけ。他の相が何枚あっても関係しない。
      expect(
        trigger.met(Phase.blue, tally(length: 9, counts: {Phase.red: 9})),
        isFalse,
      );
    });

    test('鎖の長さ', () {
      const trigger = ChainLength(7);
      expect(trigger.met(Phase.violet, tally(length: 7)), isTrue);
      expect(trigger.met(Phase.violet, tally(length: 6)), isFalse);
    });

    test('継ぎ始めた相', () {
      const trigger = StartsWith();
      expect(trigger.met(Phase.blue, tally(length: 2, startPhase: Phase.blue)), isTrue);
      expect(trigger.met(Phase.blue, tally(length: 2, startPhase: Phase.red)), isFalse);
      expect(trigger.met(Phase.blue, ChainTally.none), isFalse, reason: '空の鎖');
    });

    test('常に効く条件は空の鎖でも通る', () {
      expect(const Always().met(Phase.violet, ChainTally.none), isTrue);
    });

    test('含んでいる相の種類数', () {
      const trigger = DistinctPhases(3);
      expect(
        trigger.met(
          Phase.violet,
          tally(length: 9, counts: {Phase.red: 3, Phase.blue: 3, Phase.violet: 3}),
        ),
        isTrue,
      );
      // 2色の盤面ではどう編んでも3色にならない。
      expect(
        trigger.met(
          Phase.violet,
          tally(length: 12, counts: {Phase.red: 6, Phase.blue: 6}),
        ),
        isFalse,
      );
      // 0枚の相は数えない。
      expect(
        trigger.met(
          Phase.violet,
          tally(length: 9, counts: {Phase.red: 5, Phase.blue: 4, Phase.violet: 0}),
        ),
        isFalse,
      );
    });

    test('重ねた条件は全部そろって初めて通る', () {
      const trigger = Every([DistinctPhases(3), ChainLength(8)]);
      const threeColors = {Phase.red: 3, Phase.blue: 3, Phase.violet: 2};
      expect(trigger.met(Phase.violet, tally(length: 8, counts: threeColors)), isTrue);
      expect(
        trigger.met(Phase.violet, tally(length: 7, counts: threeColors)),
        isFalse,
        reason: '枚数が足りない',
      );
      expect(
        trigger.met(
          Phase.violet,
          tally(length: 12, counts: {Phase.red: 6, Phase.blue: 6}),
        ),
        isFalse,
        reason: '色が足りない',
      );
    });
  });

  group('名簿の見張り', () {
    // 名簿が100人に増えると、並べ忘れや重複は目で追えない。ここで捕まえる。

    test('MageKind はちょうど1度ずつ名簿に並ぶ', () {
      final kinds = [for (final mage in Mage.roster) mage.kind];
      expect(kinds.toSet().length, kinds.length, reason: '重複しない');
      expect(kinds.toSet(), MageKind.values.toSet(), reason: '並べ忘れが無い');
      for (final kind in MageKind.values) {
        expect(Mage.of(kind).kind, kind, reason: kind.name);
      }
    });

    test('従者と招ける面々で名簿を割り切る', () {
      // squires / summonable は roster から割っているので、別々に並べた
      // ことによる食い違い（所持しているのにガチャにも出る）は起きない。
      expect(
        Mage.squires.length + Mage.summonable.length,
        Mage.roster.length,
      );
      expect({...Mage.squires, ...Mage.summonable}, Mage.roster.toSet());
      for (final mage in Mage.squires) {
        expect(mage.starting, isTrue, reason: mage.name);
      }
      for (final mage in Mage.summonable) {
        expect(mage.starting, isFalse, reason: mage.name);
      }
    });

    test('名前は重ならない。札の上では名前でしか見分けられない', () {
      final names = [for (final mage in Mage.roster) mage.name];
      expect(names.toSet().length, names.length);
    });

    test('スキルには全部名前が付いていて、重ならない', () {
      // 100人に増えると、名前の付け忘れも被りも目で追えない。
      final skills = <String>[];
      for (final mage in Mage.roster) {
        if (mage.passive case final passive?) {
          expect(passive.name, isNotEmpty, reason: mage.name);
          skills.add(passive.name);
        }
        if (mage.active case final active?) {
          expect(active.name, isNotEmpty, reason: mage.name);
          skills.add(active.name);
        }
      }
      expect(skills.toSet().length, skills.length, reason: '被らない');
      // 魔導士の名前ともぶつからない。札に並ぶので、同じだと読めない。
      for (final mage in Mage.roster) {
        expect(skills, isNot(contains(mage.name)), reason: mage.name);
      }
    });

    test('体力は 30〜45 に収める', () {
      // 強い能力に厚い体力を重ねると、その1人を入れるだけの編成になる。
      for (final mage in Mage.roster) {
        expect(mage.hp, inInclusiveRange(30, 45), reason: mage.name);
      }
    });

    test('従者は相を1つずつ持つ。始まりの盤面が1色にならない', () {
      expect(
        Mage.squires.map((m) => m.phase).toSet().length,
        Mage.squires.length,
      );
    });
  });

  group('押して使う力', () {
    test('舞台の動詞を呼ぶだけ。盤面は要らない', () {
      // **呼ぶ側に「この力ならこうする」は無い。** 力を増やしても
      // `GameController.useActive` は変わらない。
      final stage = _FakeStage();
      expect(const Foresee().cast(stage, Phase.red), isTrue);
      expect(stage.revealed, 1);
      expect(stage.spreadTo, isNull, reason: '先読みは決まりを緩めない');

      // 延焼は自分の相を渡すだけ。どう緩めるかは盤面の側の仕事。
      expect(const Spread().cast(stage, Phase.red), isTrue);
      expect(stage.spreadTo, Phase.red);

      stage.answer = false;
      expect(
        const Foresee().cast(stage, Phase.red),
        isFalse,
        reason: '何も起きなければ false。呼んだ側は回数を減らさない',
      );
      expect(const Spread().cast(stage, Phase.red), isFalse);
    });

    test('潜り1本に1回だけ。使い切ったら戻らない', () {
      final party = partyOf([Mage.gale, Mage.rime]);
      expect(party.usesLeft(MageKind.gale), Party.activeUses);
      expect(party.canUse(MageKind.gale), isTrue);

      expect(party.spendUse(MageKind.gale), isTrue);
      expect(party.usesLeft(MageKind.gale), 0);
      expect(party.canUse(MageKind.gale), isFalse);
      expect(party.spendUse(MageKind.gale), isFalse, reason: '2回目は通らない');
    });

    test('力を持たない者と、連れていない者は使えない', () {
      final party = partyOf([Mage.gale, Mage.rime]);
      expect(party.canUse(MageKind.rime), isFalse, reason: '持っていない');
      expect(party.canUse(MageKind.storm), isFalse, reason: '連れていない');
      expect(party.activeOf(MageKind.storm), isNull);
    });

    test('組み直せば戻る。潜るたびに一党は組み直される', () {
      final spent = Party.of(const [Mage.gale, Mage.rime]);
      spent.spendUse(MageKind.gale);
      expect(spent.canUse(MageKind.gale), isFalse);

      final fresh = Party.of(const [Mage.gale, Mage.rime]);
      expect(fresh.canUse(MageKind.gale), isTrue);
    });
  });

  group('効き目の集計', () {
    test('威力は応えた全員ぶんが足し合わされる', () {
      final party = partyOf([Mage.ember, Mage.blaze]);
      // 赤3枚では焔だけ。
      expect(
        party.powerBonusFor(tally(length: 5, counts: {Phase.red: 3})),
        1,
      );
      // 赤5枚で烈火も乗る。+1 と +2 で +3。
      expect(
        party.powerBonusFor(tally(length: 9, counts: {Phase.red: 5})),
        3,
      );
    });

    test('相の違う威力補正も同じ足し算に入る', () {
      final party = partyOf([Mage.ember, Mage.frost]);
      final chain = tally(
        length: 6,
        counts: {Phase.red: 3, Phase.blue: 3},
        startPhase: Phase.blue,
      );
      expect(party.powerBonusFor(chain), 2, reason: '焔 +1・霜 +1');
    });

    test('居ない魔導士のぶんは乗らない', () {
      final party = partyOf([Mage.squireRed, Mage.squireBlue]);
      expect(
        party.powerBonusFor(tally(length: 9, counts: {Phase.red: 5})),
        0,
      );
      expect(party.evadesFor(tally(length: 9)), isFalse);
      expect(
        party.boltFor(
          tally(length: 9, counts: {Phase.red: 3, Phase.blue: 3, Phase.violet: 3}),
        ),
        0,
      );
      expect(party.healFor(tally(length: 9, counts: {Phase.blue: 5})), 0);
    });

    test('反撃・体力・雷も同じ形で数える', () {
      final party = partyOf([Mage.gale, Mage.rime, Mage.storm]);
      expect(party.evadesFor(tally(length: galeChain)), isTrue);
      expect(party.evadesFor(tally(length: galeChain - 1)), isFalse);
      expect(
        party.healFor(tally(length: 6, counts: {Phase.blue: rimeSame})),
        rimeMend,
      );
      const threeColors = {Phase.red: 3, Phase.blue: 3, Phase.violet: 2};
      expect(party.boltFor(tally(length: stormChain, counts: threeColors)), 1);
      expect(
        party.boltFor(tally(length: stormChain - 1, counts: threeColors)),
        0,
        reason: '枚数で見る',
      );
      expect(
        party.boltFor(
          tally(length: 12, counts: {Phase.red: 6, Phase.blue: 6}),
        ),
        0,
        reason: '2色の盤面では落ちない',
      );
    });

    test('盾は鎖と関係なく効く', () {
      // 毎ターンの反撃にも、階層を落としたときの痛手にも同じものが通る。
      expect(partyOf([Mage.aegis]).damageFor(9), 5, reason: '切り上げて半分');
      expect(partyOf([Mage.squireRed]).damageFor(9), 9);
    });
  });
}
