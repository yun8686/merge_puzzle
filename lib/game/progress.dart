import 'dart:convert';
import 'dart:math';

import 'party.dart';

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
  }) : owned = owned ?? <MageKind>{MageKind.ember},
       cleared = cleared ?? <String>{},
       party = party ?? <MageKind>[MageKind.ember];

  /// 連れていける人数。ガチャで増えても、同時に出せるのはここまで。
  static const int partySlots = 3;

  /// ガチャ1回の値段。
  static const int gachaCost = 10;

  /// 初めて踏破したときの魔晶。
  static const int firstClearReward = 10;

  /// 2回目以降の踏破。周回しても増えはするが、初回ほどではない。
  static const int repeatClearReward = 3;

  /// 所持している魔導士。始まりは焔ひとり。
  final Set<MageKind> owned;

  /// 踏破したダンジョンの id。
  final Set<String> cleared;

  /// いまの編成。先頭から順に連れていく。[partySlots] を超えない。
  final List<MageKind> party;

  /// 魔晶。ガチャを引く元手。
  int shards;

  /// まだ持っていない魔導士。ガチャはここから引く。
  List<Mage> get unowned =>
      [for (final m in Mage.roster) if (!owned.contains(m.kind)) m];

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

  /// 編成に入れる／外す。入っていれば外し、入っていなければ入れる。
  /// 枠が埋まっているときは何もしない。最後の1人は外せない。
  void toggleParty(MageKind kind) {
    if (!owned.contains(kind)) return;
    if (party.contains(kind)) {
      if (party.length <= 1) return;
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
    if (owned.isEmpty) owned.add(MageKind.ember);
    // 持っていない魔導士と重複は落とす。保存が古くても編成が壊れないように。
    final party = <MageKind>[];
    for (final kind in _kinds(json['party'])) {
      if (!owned.contains(kind) || party.contains(kind)) continue;
      if (party.length >= partySlots) break;
      party.add(kind);
    }
    if (party.isEmpty) party.add(owned.first);
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
