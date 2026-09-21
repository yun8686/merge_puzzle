import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/dungeon.dart';
import '../game/game_controller.dart';
import '../game/party.dart';
import '../game/phase.dart';
import '../game/progress.dart';
import 'foe_art.dart';
import 'game_screen.dart';
import 'mage_art.dart';
import 'tutorial.dart';
import 'theme.dart';

/// 拠点。潜る前と潜ったあとに戻ってくる場所。
///
/// ここが記録（[Progress]）を持つ唯一の場所で、盤面の画面は記録を知らない。
/// ダンジョンに入るときは「どのダンジョンを、誰を連れて」だけを渡し、
/// 帰ってきたら [DungeonOutcome] を受け取って魔晶を足し、保存する。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.banner});

  final ProgressStore store;

  /// 上の帯の下に出す一言。**いまは試用（`?all`）のときだけ**。
  ///
  /// 試用は端末の保存を読まないので、出さないと「記録が消えた」ように
  /// 見える。渡さなければ何も出ない。
  final String? banner;

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

  /// 遊び方を出しているか。初回と、上の帯から呼ばれたとき。
  bool _teaching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 3色の稽古を出しているあいだ、潜るのを待たせておく約束。
  /// 通し終えた（かとばした）ら完了して、そのまま潜る。
  Completer<void>? _prismDone;

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
    setState(() {
      _progress = progress;
      // 初回だけ遊び方を通す。読み込んでから決めるので、タイトルは記録を
      // 読まなくて済む。
      _teaching = !progress.taughtTutorial;
    });
  }

  /// 遊び方を通し終えた。印を付けて、二度目からは出さない。
  void _taught() {
    final progress = _progress;
    setState(() => _teaching = false);
    if (progress == null || progress.taughtTutorial) return;
    progress.taughtTutorial = true;
    _save();
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

  /// 初めて3色で潜るときだけ、先に3色の稽古を通す。
  ///
  /// 相が2つの間は継ぎ方が「交互」1本で、2色だった頃と何も変わらない。
  /// 3つ目を入れて初めて巡回の決まりが効きはじめるので、**その形で潜る
  /// 直前**に一度だけ出す。拠点で編成を組んだ時点では出さない――組み替えて
  /// いる最中に覆いかぶさると、何をしていたのか分からなくなる。
  Future<void> _teachPrism() {
    final done = Completer<void>();
    setState(() => _prismDone = done);
    return done.future;
  }

  void _prismTaught() {
    final done = _prismDone;
    final progress = _progress;
    setState(() => _prismDone = null);
    if (progress != null && !progress.taughtPrism) {
      progress.taughtPrism = true;
      _save();
    }
    done?.complete();
  }

  /// ダンジョンに潜って、帰ってくるまで。
  Future<void> _dive(Dungeon dungeon) async {
    final progress = _progress;
    if (progress == null) return;
    setState(() {
      _drawn = null;
      _spoils = null;
    });

    if (!progress.taughtPrism &&
        progress.partyPhaseCount >= Progress.prismPhases) {
      await _teachPrism();
    }
    // 稽古を挟んだぶん、潜る前にもう一度確かめる。
    if (!mounted) return;

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
      // 地は画面いっぱいに敷く。loose のままだと Stack の大きさが中身に
      // 合わせて決まり、地が中ほどの帯にしかならない。
      body: Stack(
        fit: StackFit.expand,
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
                    banner: widget.banner,
                    tab: _tab,
                    drawn: _drawn,
                    spoils: _spoils,
                    onTab: (tab) => setState(() => _tab = tab),
                    onRoll: _roll,
                    onToggle: _toggle,
                    onDive: _dive,
                    onTeach: () => setState(() => _teaching = true),
                  ),
          ),
          if (_teaching && progress != null)
            TutorialScreen(onDone: _taught),
          if (_prismDone != null)
            TutorialScreen(
              course: TutorialCourse.prism,
              onDone: _prismTaught,
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
    required this.banner,
    required this.tab,
    required this.drawn,
    required this.spoils,
    required this.onTab,
    required this.onRoll,
    required this.onToggle,
    required this.onDive,
    required this.onTeach,
  });

  final Progress progress;

  /// 上の帯の下に出す一言。無ければ出さない。
  final String? banner;

  final _Tab tab;
  final Mage? drawn;
  final String? spoils;
  final void Function(_Tab) onTab;
  final VoidCallback onRoll;
  final void Function(MageKind) onToggle;
  final void Function(Dungeon) onDive;

  /// 遊び方をもう一度開く。
  final VoidCallback onTeach;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusStrip(progress: progress, onTeach: onTeach),
        if (banner != null) _Banner(text: banner!),
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

/// 試用の札。**普段は出ない。** 端末の保存を読まない状態だと分からないと、
/// 記録が飛んだと思われる。
class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Palette.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.gold.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppFont.label(9, color: Palette.gold),
      ),
    );
  }
}

/// 上の帯。どの面に居ても、名乗りと魔晶だけは常に見えている。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.progress, required this.onTeach});

  final Progress progress;

  /// 遊び方をもう一度開く。初回に飛ばした人と、忘れた人のため。
  final VoidCallback onTeach;

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
                  Palette.redA,
                  Palette.redB,
                  Palette.blueB,
                  Palette.blueA,
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
            IconButton(
              onPressed: onTeach,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: 'あそびかた',
              icon: const Icon(
                Icons.help_outline,
                size: 19,
                color: Palette.textDim,
              ),
            ),
            const SizedBox(width: 6),
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
                                  Palette.blueA.withValues(alpha: 0.16),
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
                                  ? Palette.blueA
                                  : Palette.textDim,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: AppFont.label(
                                10,
                                color: tab == current
                                    ? Palette.blueA
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

  /// 丸の中に姿を収める割合。1.0 にすると縁に触れる。
  static const double _portraitScale = 0.72;

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
      // 未所持は姿を伏せる。何が来るか分からないから引く意味がある。
      child: owned
          ? MagePortrait(kind: mage.kind, size: size * _portraitScale)
          : Text(
              '？',
              style: TextStyle(
                color: Palette.textDim,
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
    final tint = cleared ? Palette.gold : Palette.blueA;
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
                            color: Palette.blueA,
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
              // 一党の体力は顔ぶれの合計。潜る前に見えていないと、厚さを
              // 取るか力を取るかの判断ができない。
              Text('体力', style: AppFont.label(9, color: Palette.life)),
              const SizedBox(width: 6),
              Text(
                '${Party.poolFor(progress.partyMages)}',
                style: AppFont.number(15, color: Palette.life),
              ),
              const SizedBox(width: 10),
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
    final full = progress.party.length >= Progress.partySlots;
    // **名簿は全部組む。** 100人並べば札の数だけ姿（`CustomPaint`）が積まれる
    // ので、本当は画面に入るぶんだけ組みたい（`SliverGrid`）。それをやると
    // **画面の外の札は木から消える**ので、「名簿に何人並んでいるか」を見て
    // いる拠点のテストが軒並み書き換えになる。遅れて組むように変えるときは、
    // テストの側を「見えている札の振る舞い」と「記録の中身」に割り直すこと。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            label: '連れていく',
            trailing: '${progress.party.length} / ${Progress.partySlots}',
          ),
          for (var i = 0; i < Progress.partySlots; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PartySlot(mage: i < party.length ? party[i] : null),
          ],
          const SizedBox(height: 12),
          _PhaseNote(phases: progress.partyPhases),
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
                  key: rosterCardKey(mage.kind),
                  mage: mage,
                  owned: progress.owned.contains(mage.kind),
                  inParty: progress.party.contains(mage.kind),
                  // 押しても動かない札は沈める。枠が埋まっていて入れない人と、
                  // 外すと盤面が1色になってしまう人。
                  stuck: progress.party.contains(mage.kind)
                      ? !progress.canDrop(mage.kind)
                      : full,
                  onTap: () => onToggle(mage.kind),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 盤面に敷かれる相。編成がそのまま盤面の色になることを、ここで見せる。
///
/// **相は2種類以上でなければならない。** 同じ相は続けて継げないので、
/// 1色の盤面では鎖が1枚も編めない。だから最後の1相は外せない。
class _PhaseNote extends StatelessWidget {
  const _PhaseNote({required this.phases});

  final List<Phase> phases;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(radius: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: Row(
          children: [
            Text('盤面の相', style: AppFont.label(9)),
            const SizedBox(width: 12),
            for (final phase in phases) ...[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: PhaseSwatch(phase: phase, size: 20),
              ),
            ],
            const Spacer(),
            Text(
              phases.length < Progress.minPhases
                  ? '相が足りない'
                  : '${phases.length} 色',
              style: AppFont.number(
                12,
                color: phases.length < Progress.minPhases
                    ? Palette.danger
                    : Palette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 連れていく枠1つ。**印だけでは誰なのか読めない**ので、名前と能力と相を
/// 一緒に並べる。名簿の札を見に行かなくても、いまの編成が何をする一党なのかが
/// ここだけで分かるようにする。
///
/// 横に3つ並べると1枠あたりが狭く、名前も能力も入らない。縦に3本の帯にして、
/// 幅を能力の説明に使う。
class _PartySlot extends StatelessWidget {
  const _PartySlot({required this.mage});

  final Mage? mage;

  @override
  Widget build(BuildContext context) {
    final mage = this.mage;
    if (mage == null) {
      return DecoratedBox(
        decoration: panelDecoration(radius: 14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 14, 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.panelBorder, width: 1.5),
                ),
                // ラベルの字間（2.2）が効くと丸の中で左に寄るので、
                // ここだけ素の字で置く。
                child: const Text(
                  '＋',
                  style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text('空き', style: AppFont.label(11, color: Palette.textDim)),
              const Spacer(),
              Text(
                '名簿から選ぶ',
                style: AppFont.label(9, color: Palette.textDim),
              ),
            ],
          ),
        ),
      );
    }
    final tint = Palette.mageColor(mage.kind);
    return DecoratedBox(
      decoration: panelDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.10), Palette.surface),
        border: tint.withValues(alpha: 0.55),
        radius: 14,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 12, 11),
        child: Row(
          children: [
            _Sigil(mage: mage, size: 38),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mage.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mage.effect,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Palette.textMuted,
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                  // 押して使う力も編成の判断に乗る。**鎖に勝手に応える能力
                  // とは別物**なので、名前を前に出して別の行にする。
                  if (mage.spellEffect case final text?) ...[
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mage.spell!.label,
                          style: AppFont.label(8, color: Palette.gold),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Palette.textMuted,
                              fontSize: 9.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            PhaseSwatch(phase: mage.phase, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 名簿の札を指す鍵。
///
/// 連れていく枠にも魔導士の名前が出るので、名前だけで探すと2枚に当たる。
/// テストが「名簿の方」を指すためにここを使う。
ValueKey<String> rosterCardKey(MageKind kind) => ValueKey('roster-${kind.name}');

/// 名簿の1枚。押すと編成に入れ替わる。
class _MageCard extends StatelessWidget {
  const _MageCard({
    super.key,
    required this.mage,
    required this.owned,
    required this.inParty,
    required this.stuck,
    required this.onTap,
  });

  final Mage mage;
  final bool owned;
  final bool inParty;

  /// 押しても編成が動かないか。
  final bool stuck;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = Palette.mageColor(mage.kind);
    final dim = !owned || stuck;
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
                        // 体力は名簿ごとに違う。力のある者ほど薄いので、
                        // ここに出しておかないと編成の判断ができない。
                        //
                        // 押して使う力は**名前だけ**。札は3枚並びで狭く、
                        // 説明まで入れると行が増えて札から溢れる。中身は
                        // 連れていく枠（[_PartySlot]）で読める。
                        // 狭い端末でも溢れないよう、入らなければ縮める。
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '体力 ${mage.hp}',
                                style: AppFont.label(8, color: Palette.life),
                              ),
                              if (mage.spell case final spell?) ...[
                                const SizedBox(width: 6),
                                Text(
                                  spell.label,
                                  style: AppFont.label(8, color: Palette.gold),
                                ),
                              ],
                            ],
                          ),
                        ),
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
              text: [
                '${drawn!.name} が加わった',
                drawn!.effect,
                if (drawn!.spellEffect case final text?)
                  '${drawn!.spell!.label}（押して使う）　$text',
              ].join('\n'),
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
