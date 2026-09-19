import 'dart:math';

import 'package:flutter/material.dart';

import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/progress.dart';
import 'game_screen.dart';
import 'theme.dart';

/// 拠点。潜る前と潜ったあとに戻ってくる場所。
///
/// ここが記録（[Progress]）を持つ唯一の場所で、盤面の画面は記録を知らない。
/// ダンジョンに入るときは「どのダンジョンを、誰を連れて」だけを渡し、
/// 帰ってきたら [DungeonOutcome] を受け取って魔晶を足し、保存する。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final ProgressStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Progress? _progress;
  final Random _rng = Random();

  /// 直前の引きの結果。引いた直後だけ出す。
  Mage? _drawn;

  /// 直前に持ち帰った魔晶。潜って帰ってきた直後だけ出す。
  String? _spoils;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 記録が読めるのを待つ上限。これを過ぎたら、まっさらな記録で拠点を開く。
  ///
  /// 投げてくるとは限らない。保存のプラグインが載っていない環境では、
  /// **返事そのものが返ってこない**ことがある。待ち続けると、ぐるぐる回る輪を
  /// 見せたまま何もできなくなるので、諦める線を引いておく。
  static const Duration _loadLimit = Duration(seconds: 3);

  Future<void> _load() async {
    Progress progress;
    try {
      progress = await widget.store
          .load()
          .timeout(_loadLimit, onTimeout: Progress.new);
    } catch (_) {
      progress = Progress();
    }
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  Future<void> _save() async {
    final progress = _progress;
    if (progress != null) await widget.store.save(progress);
  }

  void _roll() {
    final progress = _progress;
    if (progress == null || !progress.canRoll) return;
    final mage = progress.roll(_rng);
    setState(() => _drawn = mage);
    _save();
  }

  void _toggle(MageKind kind) {
    final progress = _progress;
    if (progress == null) return;
    setState(() => progress.toggleParty(kind));
    _save();
  }

  /// ダンジョンに潜って、帰ってくるまで。
  Future<void> _dive(Dungeon dungeon) async {
    final progress = _progress;
    if (progress == null) return;
    setState(() {
      _drawn = null;
      _spoils = null;
    });

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => GameScreen(
          controller: GameController(
            dungeon: dungeon,
            roster: progress.partyMages,
          ),
          onFinished: (outcome) {
            // 記録を書くのはここ。盤面の画面は結末を伝えるだけ。
            final gained = outcome.cleared
                ? progress.recordClear(outcome.dungeonId)
                : progress.recordFailure(outcome.floor);
            _spoils = outcome.cleared
                ? '${dungeon.name} を踏破した　魔晶 +$gained'
                : 'B${outcome.floor}F まで降りた　魔晶 +$gained';
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.0,
                  colors: [Palette.backgroundGlow, Palette.background],
                  stops: [0, 0.85],
                ),
              ),
            ),
          ),
          SafeArea(
            child: progress == null
                ? const Center(child: CircularProgressIndicator())
                : _Base(
                    progress: progress,
                    drawn: _drawn,
                    spoils: _spoils,
                    onRoll: _roll,
                    onToggle: _toggle,
                    onDive: _dive,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Base extends StatelessWidget {
  const _Base({
    required this.progress,
    required this.drawn,
    required this.spoils,
    required this.onRoll,
    required this.onToggle,
    required this.onDive,
  });

  final Progress progress;
  final Mage? drawn;
  final String? spoils;
  final VoidCallback onRoll;
  final void Function(MageKind) onToggle;
  final void Function(Dungeon) onDive;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Logo(),
          const SizedBox(height: 18),
          if (spoils != null) ...[
            _Notice(text: spoils!, tint: Palette.gold),
            const SizedBox(height: 12),
          ],
          _ShardBar(progress: progress, onRoll: onRoll),
          if (drawn != null) ...[
            const SizedBox(height: 10),
            _Notice(
              text: '${drawn!.name} が加わった\n${drawn!.effect}',
              tint: Palette.mageColor(drawn!.kind),
            ),
          ],
          const SizedBox(height: 22),
          _SectionLabel(
            label: '一党',
            trailing: '${progress.party.length} / ${Progress.partySlots}',
          ),
          const SizedBox(height: 10),
          for (final mage in Mage.roster)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MageRow(
                mage: mage,
                owned: progress.owned.contains(mage.kind),
                inParty: progress.party.contains(mage.kind),
                full: progress.party.length >= Progress.partySlots,
                onTap: () => onToggle(mage.kind),
              ),
            ),
          const SizedBox(height: 22),
          const _SectionLabel(label: 'ダンジョン'),
          const SizedBox(height: 10),
          for (var i = 0; i < Dungeons.all.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DungeonCard(
                dungeon: Dungeons.all[i],
                cleared: progress.hasCleared(Dungeons.all[i].id),
                // 前の1本を踏破すると開く。いきなり竜の巣に入って
                // 何も分からないまま全滅する、という入り方を塞ぐため。
                locked:
                    i > 0 && !progress.hasCleared(Dungeons.all[i - 1].id),
                needs: i > 0 ? Dungeons.all[i - 1].name : null,
                onTap: () => onDive(Dungeons.all[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Palette.oddA, Palette.oddB, Palette.evenB, Palette.evenA],
      ).createShader(rect),
      child: Text(
        'FROSTFIRE CHAIN',
        textAlign: TextAlign.center,
        style: AppFont.number(
          20,
          color: Colors.white,
        ).copyWith(letterSpacing: 5),
      ),
    );
  }
}

/// 一言の知らせ。引いた結果と、潜って持ち帰ったもの。
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tint});

  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.12), Palette.surface),
        border: tint.withValues(alpha: 0.5),
        radius: 14,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tint,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppFont.label(11, color: Palette.textMuted)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: AppFont.number(13, color: Palette.textDim)),
      ],
    );
  }
}

/// 魔晶と、ガチャを引くボタン。
class _ShardBar extends StatelessWidget {
  const _ShardBar({required this.progress, required this.onRoll});

  final Progress progress;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    final all = progress.unowned.isEmpty;
    final poor = !all && progress.shards < Progress.gachaCost;
    return DecoratedBox(
      decoration: panelDecoration(radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('魔晶', style: AppFont.label(10, color: Palette.gold)),
                const SizedBox(height: 6),
                Text(
                  '${progress.shards}',
                  style: AppFont.number(26, color: Palette.gold),
                ),
              ],
            ),
            const Spacer(),
            Opacity(
              opacity: progress.canRoll ? 1 : 0.45,
              child: DecoratedBox(
                decoration: panelDecoration(
                  color: Color.alphaBlend(
                    Palette.gold.withValues(alpha: 0.14),
                    Palette.surface,
                  ),
                  border: Palette.gold.withValues(alpha: 0.55),
                  radius: 14,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: progress.canRoll ? onRoll : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            all
                                ? '全員揃った'
                                : poor
                                ? '魔晶が足りない'
                                : '魔導士を招く',
                            style: const TextStyle(
                              color: Palette.gold,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (!all) ...[
                            const SizedBox(height: 3),
                            Text(
                              '魔晶 ${Progress.gachaCost}',
                              style: AppFont.label(
                                9,
                                color: Palette.textDim,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 魔導士1人ぶんの行。持っていれば押して編成に入れ替えられる。
class _MageRow extends StatelessWidget {
  const _MageRow({
    required this.mage,
    required this.owned,
    required this.inParty,
    required this.full,
    required this.onTap,
  });

  final Mage mage;
  final bool owned;
  final bool inParty;

  /// 枠が埋まっているか。埋まっていて外にいる人は押しても入らない。
  final bool full;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.mageColor(mage.kind);
    final dim = !owned || (!inParty && full);
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: inParty
              ? Color.alphaBlend(tint.withValues(alpha: 0.12), Palette.surface)
              : Palette.panel,
          border: inParty ? tint.withValues(alpha: 0.6) : Palette.panelBorder,
          radius: 14,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: owned ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.alphaBlend(
                        tint.withValues(alpha: 0.18),
                        Palette.background,
                      ),
                      border: Border.all(
                        color: tint.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      owned ? mage.sigil : '？',
                      style: TextStyle(
                        color: tint,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          owned ? mage.name : 'まだ見ぬ魔導士',
                          style: const TextStyle(
                            color: Palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          owned ? mage.effect : '魔晶で招く',
                          style: const TextStyle(
                            color: Palette.textMuted,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (inParty) ...[
                    const SizedBox(width: 8),
                    Text('同行', style: AppFont.label(9, color: tint)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ダンジョン1本ぶんの札。
class _DungeonCard extends StatelessWidget {
  const _DungeonCard({
    required this.dungeon,
    required this.cleared,
    required this.locked,
    required this.needs,
    required this.onTap,
  });

  final Dungeon dungeon;
  final bool cleared;
  final bool locked;

  /// 開けるのに踏破が要るダンジョンの名。
  final String? needs;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = cleared ? Palette.gold : Palette.evenA;
    return Opacity(
      opacity: locked ? 0.4 : 1,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: Palette.panel,
          border: locked ? Palette.panelBorder : tint.withValues(alpha: 0.45),
          radius: 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: locked ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dungeon.name,
                          style: const TextStyle(
                            color: Palette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          locked
                              ? '$needs を踏破すると開く'
                              : '全 ${dungeon.depth} 階層',
                          style: const TextStyle(
                            color: Palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cleared)
                    Text('踏破', style: AppFont.label(10, color: Palette.gold)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
