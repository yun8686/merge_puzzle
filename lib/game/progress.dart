import 'dart:convert';
import 'dart:math';

import 'party.dart';
import 'phase.dart';

/// ダンジョンをまたいで残る記録。所持している魔導士・踏破したダンジョン・
/// 魔晶・いまの編成。**これが唯一の永続状態**で、盤面も一党も持ち越さない。
///
/// 盤面もダンジョンも読まない。踏破したかどうかは id の文字列でしか持たない
/// ので、ダンジョンを増やしても消しても、ここは壊れない。
class Progress {
  Progress({
    Set<MageKind>? owned,
    Set<String>? cleared,
    List<MageKind>? party,
    this.shards = 0,
  }) : // 従者は常に居る。ここが欠けると編成が組めなくなる。
       owned = <MageKind>{
         ...?owned,
         for (final m in Mage.squires) m.kind,
       },
       cleared = cleared ?? <String>{},
       party = party ?? <MageKind>[for (final m in Mage.squires) m.kind];

  /// 連れていける人数。ガチャで増えても、同時に出せるのはここまで。
  static const int partySlots = 3;

  /// ガチャ1回の値段。
  static const int gachaCost = 10;

  /// 初めて踏破したときの魔晶。
  static const int firstClearReward = 10;

  /// 2回目以降の踏破。周回しても増えはするが、初回ほどではない。
  static const int repeatClearReward = 3;

  /// 所持している魔導士。始まりは相を1つずつ持つ従者3人。
  final Set<MageKind> owned;

  /// 踏破したダンジョンの id。
  final Set<String> cleared;

  /// いまの編成。先頭から順に連れていく。[partySlots] を超えない。
  final List<MageKind> party;

  /// 魔晶。ガチャを引く元手。
  int shards;

  /// まだ持っていない魔導士。ガチャはここから引く。
  /// 従者は最初から居るので、引く対象は [Mage.summonable] だけ。
  List<Mage> get unowned =>
      [for (final m in Mage.summonable) if (!owned.contains(m.kind)) m];

  /// 引ける状態か。値段が足りていて、まだ引く相手が居ること。
  bool get canRoll => shards >= gachaCost && unowned.isNotEmpty;

  /// 編成に入っている魔導士。順番は編成した順。
  List<Mage> get partyMages => [
    for (final kind in party)
      if (owned.contains(kind)) Mage.of(kind),
  ];

  bool hasCleared(String dungeonId) => cleared.contains(dungeonId);

  /// 踏破したときに入る魔晶。初回だけ厚い。
  int rewardFor(String dungeonId) =>
      hasCleared(dungeonId) ? repeatClearReward : firstClearReward;

  /// 踏破を記録して、入った魔晶を返す。
  int recordClear(String dungeonId) {
    final gained = rewardFor(dungeonId);
    cleared.add(dungeonId);
    shards += gained;
    return gained;
  }

  /// 失敗しても、降りた階層のぶんだけは持ち帰る。
  /// 全部無駄にすると、負けた後に何も残らず続ける気が失せる。
  int recordFailure(int reachedFloor) {
    final gained = reachedFloor.clamp(0, 99);
    shards += gained;
    return gained;
  }

  /// ガチャを1回引く。引けなければ null。
  ///
  /// **未所持からしか引かない。** ロースターが7人しか居ないので、重複を出すと
  /// すぐ「何も増えない引き」ばかりになる。実質はランダムな解放順。
  Mage? roll(Random rng) {
    if (!canRoll) return null;
    shards -= gachaCost;
    final pool = unowned;
    final mage = pool[rng.nextInt(pool.length)];
    owned.add(mage.kind);
    // 枠が空いていれば、引いた人はそのまま編成に入れておく。
    // 引いたのに使われないまま、という一手間を省く。
    if (party.length < partySlots) party.add(mage.kind);
    return mage;
  }

  /// 連れていく相。盤面に敷かれる色。
  List<Phase> get partyPhases {
    final seen = <Phase>[];
    for (final mage in partyMages) {
      if (!seen.contains(mage.phase)) seen.add(mage.phase);
    }
    return seen;
  }

  /// 編成として成り立っているか。
  ///
  /// **相が1種類だけの編成は組めない。** 同じ相は続けて継げないので、
  /// 1色の盤面では鎖が1枚も編めず、ダンジョンに入った瞬間に手詰まりになる。
  /// 枠の数や人数ではなく、ここだけが編成の縛り。
  static const int minPhases = 2;

  bool get partyIsValid => partyPhases.length >= minPhases;

  /// [kind] を編成から外せるか。外した結果が1色になるなら外せない。
  bool canDrop(MageKind kind) {
    if (!party.contains(kind)) return false;
    final rest = [
      for (final k in party)
        if (k != kind) k,
    ];
    if (rest.isEmpty) return false;
    final seen = <Phase>{};
    for (final k in rest) {
      seen.add(Mage.of(k).phase);
    }
    return seen.length >= minPhases;
  }

  /// 編成に入れる／外す。入っていれば外し、入っていなければ入れる。
  /// 枠が埋まっているとき、外すと1色になってしまうときは何もしない。
  void toggleParty(MageKind kind) {
    if (!owned.contains(kind)) return;
    if (party.contains(kind)) {
      if (!canDrop(kind)) return;
      party.remove(kind);
      return;
    }
    if (party.length >= partySlots) return;
    party.add(kind);
  }

  Map<String, Object?> toJson() => {
    'owned': [for (final k in owned) k.name],
    'cleared': cleared.toList(),
    'party': [for (final k in party) k.name],
    'shards': shards,
  };

  static Progress fromJson(Map<String, Object?> json) {
    final owned = _kinds(json['owned']).toSet();
    // 従者は常に居る。ここを空にすると編成が組めなくなる。
    owned.addAll([for (final m in Mage.squires) m.kind]);
    // 持っていない魔導士と重複は落とす。保存が古くても編成が壊れないように。
    final party = <MageKind>[];
    for (final kind in _kinds(json['party'])) {
      if (!owned.contains(kind) || party.contains(kind)) continue;
      if (party.length >= partySlots) break;
      party.add(kind);
    }
    _repair(party, owned);
    return Progress(
      owned: owned,
      cleared: {
        for (final v in _list(json['cleared']))
          if (v is String) v,
      },
      party: party,
      shards: switch (json['shards']) {
        final int n => n < 0 ? 0 : n,
        _ => 0,
      },
    );
  }

  /// 読んだ編成を、成り立つ形に直す。
  ///
  /// 相が1種類しか無い記録（相を入れる前に保存されたもの、手で書き換えた
  /// もの）でも拠点が開けるように、足りない相を所持している中から補う。
  /// 補えなければ従者を足す。従者は必ず持っているので、必ず直る。
  static void _repair(List<MageKind> party, Set<MageKind> owned) {
    Set<Phase> phasesOf(List<MageKind> ks) => {
      for (final k in ks) Mage.of(k).phase,
    };
    if (party.isNotEmpty && phasesOf(party).length >= minPhases) return;
    for (final mage in [...Mage.squires, ...Mage.summonable]) {
      if (party.length >= partySlots) break;
      if (phasesOf(party).length >= minPhases && party.isNotEmpty) break;
      if (!owned.contains(mage.kind) || party.contains(mage.kind)) continue;
      if (party.isNotEmpty && phasesOf(party).contains(mage.phase)) continue;
      party.add(mage.kind);
    }
    // それでも足りなければ、従者で埋める（従者は常に所持している扱い）。
    for (final mage in Mage.squires) {
      if (phasesOf(party).length >= minPhases) break;
      if (party.contains(mage.kind)) continue;
      owned.add(mage.kind);
      party.add(mage.kind);
    }
  }

  /// 保存の値は何が入っているか分からない。並びでなければ空として扱う。
  static List<Object?> _list(Object? raw) =>
      raw is List<Object?> ? raw : const <Object?>[];

  static List<MageKind> _kinds(Object? raw) => [
    for (final v in _list(raw))
      if (v is String)
        for (final k in MageKind.values)
          if (k.name == v) k,
  ];

  String encode() => jsonEncode(toJson());

  /// 壊れた文字列は黙って捨てて、まっさらな記録を返す。
  /// 保存が読めないだけで遊べなくなるのは割に合わない。
  static Progress decode(String? raw) {
    if (raw == null || raw.isEmpty) return Progress();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return Progress();
      return fromJson(json);
    } on FormatException {
      return Progress();
    }
  }
}

/// 記録の置き場所。実体は端末の保存領域だが、テストは手元の箱で差し替える。
abstract class ProgressStore {
  Future<Progress> load();
  Future<void> save(Progress progress);
}

/// 何も残さない置き場所。テストと、保存が使えない環境の受け皿。
class MemoryProgressStore implements ProgressStore {
  MemoryProgressStore([this._raw]);

  String? _raw;

  @override
  Future<Progress> load() async => Progress.decode(_raw);

  @override
  Future<void> save(Progress progress) async {
    _raw = progress.encode();
  }
}
