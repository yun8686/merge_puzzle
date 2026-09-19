import 'dart:math';

import 'package:flutter/material.dart';

import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/progress.dart';
import 'foe_art.dart';
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

/// 拠点の三つの面。下の帯で行き来する。
enum _Tab { dungeons, party, gacha }

class _HomeScreenState extends State<HomeScreen> {
  Progress? _progress;
  final Random _rng = Random();
  _Tab _tab = _Tab.dungeons;

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
                    tab: _tab,
                    drawn: _drawn,
                    spoils: _spoils,
                    onTab: (tab) => setState(() => _tab = tab),
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


/// 拠点の骨組み。上に帯、下にタブ、その間が面ごとの中身。
///
/// 縦に全部並べていたのをやめ、面を三つに割った。並べると「いま何ができるか」が
/// 埋もれるうえ、下にあるダンジョンまで毎回スクロールすることになる。
class _Base extends StatelessWidget {
  const _Base({
    required this.progress,
    required this.tab,
    required this.drawn,
    required this.spoils,
    required this.onTab,
    required this.onRoll,
    required this.onToggle,
    required this.onDive,
  });

  final Progress progress;
  final _Tab tab;
  final Mage? drawn;
  final String? spoils;
  final void Function(_Tab) onTab;
  final VoidCallback onRoll;
  final void Function(MageKind) onToggle;
  final void Function(Dungeon) onDive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusStrip(progress: progress),
        Expanded(
          child: switch (tab) {
            _Tab.dungeons => _DungeonTab(
              progress: progress,
              spoils: spoils,
              onDive: onDive,
              onParty: () => onTab(_Tab.party),
            ),
            _Tab.party => _PartyTab(progress: progress, onToggle: onToggle),
            _Tab.gacha => _GachaTab(
              progress: progress,
              drawn: drawn,
              onRoll: onRoll,
            ),
          },
        ),
        _TabBar(current: tab, onTab: onTab),
      ],
    );
  }
}

/// 上の帯。どの面に居ても、名乗りと魔晶だけは常に見えている。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.surface, Palette.boardBg],
        ),
        border: Border(bottom: BorderSide(color: Palette.panelBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [
                  Palette.oddA,
                  Palette.oddB,
                  Palette.evenB,
                  Palette.evenA,
                ],
              ).createShader(rect),
              child: Text(
                'FROSTFIRE CHAIN',
                style: AppFont.number(
                  13,
                  color: Colors.white,
                ).copyWith(letterSpacing: 3),
              ),
            ),
            const Spacer(),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Palette.boardBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Palette.gold.withValues(alpha: 0.45),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('魔晶', style: AppFont.label(9, color: Palette.textDim)),
                    const SizedBox(width: 7),
                    Text(
                      '${progress.shards}',
                      style: AppFont.number(15, color: Palette.gold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下のタブ。面は三つしかないので、並べて全部見せる。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onTab});

  final _Tab current;
  final void Function(_Tab) onTab;

  static const _items = <(_Tab, IconData, String)>[
    (_Tab.dungeons, Icons.terrain, 'ダンジョン'),
    (_Tab.party, Icons.groups, '一党'),
    (_Tab.gacha, Icons.auto_awesome, 'ガチャ'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.surface, Palette.background],
        ),
        border: Border(top: BorderSide(color: Palette.panelBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (tab, icon, label) in _items)
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTab(tab),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: tab != current
                            ? null
                            : LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Palette.evenA.withValues(alpha: 0.16),
                                  Colors.transparent,
                                ],
                              ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 9, 0, 11),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: tab == current
                                  ? Palette.evenA
                                  : Palette.textDim,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: AppFont.label(
                                10,
                                color: tab == current
                                    ? Palette.evenA
                                    : Palette.textDim,
                              ),
                            ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: AppFont.label(11, color: Palette.textMuted)),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: AppFont.number(13, color: Palette.textDim)),
        ],
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

/// 魔導士の印。丸の中に一文字。編成の枠でも名簿でも同じ顔を使う。
class _Sigil extends StatelessWidget {
  const _Sigil({
    required this.mage,
    required this.size,
    this.owned = true,
  });

  final Mage mage;
  final double size;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.mageColor(mage.kind);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          tint.withValues(alpha: 0.16),
          Palette.background,
        ),
        border: Border.all(
          color: owned ? tint : Palette.panelBorder,
          width: 1.5,
        ),
      ),
      child: Text(
        owned ? mage.sigil : '？',
        style: TextStyle(
          color: owned ? tint : Palette.textDim,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// ダンジョンの面。挑む先を選ぶところ。
class _DungeonTab extends StatelessWidget {
  const _DungeonTab({
    required this.progress,
    required this.spoils,
    required this.onDive,
    required this.onParty,
  });

  final Progress progress;
  final String? spoils;
  final void Function(Dungeon) onDive;

  /// 一党の帯を押したとき。編成の面に送る。
  final VoidCallback onParty;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (spoils != null) ...[
                  _Notice(text: spoils!, tint: Palette.gold),
                  const SizedBox(height: 14),
                ],
                for (var i = 0; i < Dungeons.all.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DungeonCard(
                      dungeon: Dungeons.all[i],
                      cleared: progress.hasCleared(Dungeons.all[i].id),
                      // 前の1本を踏破すると開く。いきなり竜の巣に入って
                      // 何も分からないまま全滅する入り方を塞ぐため。
                      locked:
                          i > 0 &&
                          !progress.hasCleared(Dungeons.all[i - 1].id),
                      needs: i > 0 ? Dungeons.all[i - 1].name : null,
                      onTap: () => onDive(Dungeons.all[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 挑む前に「誰を連れていくか」が見えていないと、選び直しに戻る羽目になる。
        _PartyStrip(progress: progress, onTap: onParty),
      ],
    );
  }
}

/// ダンジョン1本ぶんの札。最下層の主を薄く敷いて、顔として見せる。
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
      opacity: locked ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: locked
                ? Palette.panelBorder
                : tint.withValues(alpha: 0.45),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Palette.surface, Palette.backgroundGlow],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: locked ? null : onTap,
              child: Stack(
                children: [
                  // 主の姿。札の右に大きく、沈めて敷く。
                  Positioned(
                    right: -8,
                    top: -10,
                    child: Opacity(
                      opacity: 0.35,
                      child: FoePortrait(ward: dungeon.bossWard, size: 104),
                    ),
                  ),
                  Padding(
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                locked
                                    ? '$needs を踏破すると開く'
                                    : '全 ${dungeon.depth} 階層　主は守り ${dungeon.bossWard}',
                                style: const TextStyle(
                                  color: Palette.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 9),
                              _FloorPips(
                                depth: dungeon.depth,
                                lit: cleared,
                                tint: tint,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (locked)
                          const Icon(
                            Icons.lock,
                            size: 20,
                            color: Palette.textDim,
                          )
                        else if (cleared)
                          Text(
                            '踏破',
                            style: AppFont.label(10, color: Palette.gold),
                          )
                        else
                          const Icon(
                            Icons.chevron_right,
                            size: 26,
                            color: Palette.evenA,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 階層の数だけ並ぶ目盛り。踏破すると全部灯る。
class _FloorPips extends StatelessWidget {
  const _FloorPips({
    required this.depth,
    required this.lit,
    required this.tint,
  });

  final int depth;
  final bool lit;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < depth; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 16,
            height: 4,
            decoration: BoxDecoration(
              color: lit ? tint : Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

/// 連れていく顔ぶれの帯。押すと編成の面に移る。
class _PartyStrip extends StatelessWidget {
  const _PartyStrip({required this.progress, required this.onTap});

  final Progress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.boardBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 12),
          child: Row(
            children: [
              Text('連れていく', style: AppFont.label(10)),
              const SizedBox(width: 12),
              for (final mage in progress.partyMages) ...[
                _Sigil(mage: mage, size: 30),
                const SizedBox(width: 7),
              ],
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Palette.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一党の面。上に連れていく枠、下に名簿。
class _PartyTab extends StatelessWidget {
  const _PartyTab({required this.progress, required this.onToggle});

  final Progress progress;
  final void Function(MageKind) onToggle;

  @override
  Widget build(BuildContext context) {
    final party = progress.partyMages;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            label: '連れていく',
            trailing: '${progress.party.length} / ${Progress.partySlots}',
          ),
          Row(
            children: [
              for (var i = 0; i < Progress.partySlots; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _PartySlot(
                    mage: i < party.length ? party[i] : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          const _SectionLabel(label: '名簿'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: [
              for (final mage in Mage.roster)
                _MageCard(
                  mage: mage,
                  owned: progress.owned.contains(mage.kind),
                  inParty: progress.party.contains(mage.kind),
                  full: progress.party.length >= Progress.partySlots,
                  onTap: () => onToggle(mage.kind),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 連れていく枠1つ。空いていれば破線の丸だけ置く。
class _PartySlot extends StatelessWidget {
  const _PartySlot({required this.mage});

  final Mage? mage;

  @override
  Widget build(BuildContext context) {
    final mage = this.mage;
    final tint = mage == null
        ? Palette.panelBorder
        : Palette.mageColor(mage.kind);
    return AspectRatio(
      aspectRatio: 0.88,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: mage == null
              ? Palette.panel
              : Color.alphaBlend(
                  tint.withValues(alpha: 0.10),
                  Palette.surface,
                ),
          border: mage == null
              ? Palette.panelBorder
              : tint.withValues(alpha: 0.55),
          radius: 14,
        ),
        child: Center(
          child: mage == null
              ? Text(
                  '空き',
                  style: AppFont.label(9, color: Palette.textDim),
                )
              : _Sigil(mage: mage, size: 46),
        ),
      ),
    );
  }
}

/// 名簿の1枚。押すと編成に入れ替わる。
class _MageCard extends StatelessWidget {
  const _MageCard({
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
      opacity: dim ? 0.42 : 1,
      child: DecoratedBox(
        decoration: panelDecoration(
          color: inParty
              ? Color.alphaBlend(tint.withValues(alpha: 0.12), Palette.surface)
              : Palette.panel,
          border: inParty ? tint : Palette.panelBorder,
          radius: 14,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: owned ? onTap : null,
            child: Stack(
              children: [
                if (inParty)
                  Positioned(
                    top: 5,
                    right: 6,
                    child: Text(
                      '同行',
                      style: AppFont.label(8, color: tint),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Sigil(mage: mage, size: 38, owned: owned),
                      const SizedBox(height: 7),
                      Text(
                        owned ? mage.name : '未所持',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: owned
                              ? Palette.textPrimary
                              : Palette.textDim,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (owned) ...[
                        const SizedBox(height: 3),
                        Text(
                          mage.effect,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Palette.textMuted,
                            fontSize: 9,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ガチャの面。
class _GachaTab extends StatelessWidget {
  const _GachaTab({
    required this.progress,
    required this.drawn,
    required this.onRoll,
  });

  final Progress progress;
  final Mage? drawn;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    final left = progress.unowned.length;
    final all = left == 0;
    final poor = !all && progress.shards < Progress.gachaCost;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Palette.gold.withValues(alpha: 0.5)),
              gradient: RadialGradient(
                center: const Alignment(0, -1),
                radius: 1.1,
                colors: [
                  Palette.gold.withValues(alpha: 0.18),
                  Palette.panel,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Text(
                    '魔導士を招く',
                    style: AppFont.number(20, color: Palette.gold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    all
                        ? '名簿は全員揃っている'
                        : '魔晶 ${Progress.gachaCost} で、まだ見ぬ魔導士がひとり加わる\n残り $left 人',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _GachaButton(
                    label: all
                        ? '全員揃った'
                        : poor
                        ? '魔晶が足りない'
                        : '招く　魔晶 ${Progress.gachaCost}',
                    enabled: progress.canRoll,
                    onTap: onRoll,
                  ),
                ],
              ),
            ),
          ),
          if (drawn != null) ...[
            const SizedBox(height: 20),
            const _SectionLabel(label: '直前の招き'),
            _Notice(
              text: '${drawn!.name} が加わった\n${drawn!.effect}',
              tint: Palette.mageColor(drawn!.kind),
            ),
          ],
        ],
      ),
    );
  }
}

/// 招くボタン。厚みを付けて、拠点でいちばん押したくなる形にしてある。
class _GachaButton extends StatelessWidget {
  const _GachaButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE79A), Palette.gold, Color(0xFFE8A800)],
                stops: [0, 0.45, 1],
              )
            : null,
        color: enabled ? null : Palette.surface,
        border: enabled
            ? null
            : Border.all(color: Palette.panelBorder),
        boxShadow: enabled
            ? [
                const BoxShadow(
                  color: Color(0xFF8A6400),
                  offset: Offset(0, 4),
                ),
                BoxShadow(
                  color: Palette.gold.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: enabled ? const Color(0xFF1A1405) : Palette.textDim,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
