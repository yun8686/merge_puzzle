import 'dart:math';

import 'package:flutter/foundation.dart';

import 'board.dart';
import 'dungeon.dart';
import 'phase.dart';
import 'party.dart';

/// 階層の決着。
///
///  - [stageCleared] … その階層の敵を討ち果たした。祝福を1つ選んで次の階層へ
///  - [dungeonCleared] … 最下層まで討ち果たした。ダンジョンの踏破
///  - [floorLost] … ターン切れか手詰まり。討ち漏らした敵の反撃を受けて編み直す
///  - [defeated] … 反撃で一党の体力が尽きた。このダンジョンは失敗
enum GamePhase { playing, stageCleared, dungeonCleared, floorLost, defeated }

/// 盤面の上に乗る「遊び」の状態管理。
///
/// ダンジョン制。[dungeon] の階層を1階層目から順に降り、最下層を制圧すれば踏破。
/// 体力が尽きたらそのダンジョンは失敗で、**1階層目からやり直す**。
///
/// 一党は潜る前に決めて、道中では増えない。増えるのは体力と最大体力だけ
/// （制圧のたびの祝福）。誰を連れていくかは編成の側の判断に閉じている。
class GameController extends ChangeNotifier {
  GameController({
    Random? rng,
    Dungeon? dungeon,
    List<Mage>? roster,
    int startFloor = 1,
  }) : _rng = rng ?? Random() {
    this.dungeon = dungeon ?? Dungeons.all.first;
    _roster = List.of(roster ?? Mage.squires);
    party = _freshParty();
    _startFloor(startFloor);
  }

  /// 盤面を作る乱数。階層ごとに作り直すが、種は持ち越すので
  /// 同じ種を渡せば通しで同じ並びになる。
  final Random _rng;

  late Board board;

  /// いま潜っているダンジョン。
  late Dungeon dungeon;

  /// 連れてきた魔導士。失敗してやり直すときはここから編み直す。
  late List<Mage> _roster;

  /// 階層をまたいで持ち越す一党。
  late Party party;

  /// 1から始まる階層番号。[Dungeon.depth] まで降りれば踏破。
  late int floor;

  /// この階層に残っている手数。
  late int movesLeft;

  final List<Cell> path = <Cell>[];
  int score = 0;
  int best = 0;
  int bestChain = 0;
  GamePhase phase = GamePhase.playing;

  /// 階層を落としたときに受けた痛手。決着画面に出す。
  int lastBacklash = 0;

  /// 直近の鎖で氷雨が戻した体力。0 なら何も起きていない。
  int lastHealed = 0;

  /// この階層で討ち取った敵の守り。討った順に積む。制圧画面に姿を並べるのに使う。
  /// 敵は盤面から消えてしまうので、ここに控えておかないと何を討ったか分からない。
  final List<int> felledWards = <int>[];

  /// 直近に補充されたブロックの id。降ってくる演出に使う。
  Set<int> freshTileIds = <int>{};

  List<Cell> hintPath = <Cell>[];

  /// 消した直後、重力と補充を当てるまでの間。なぞった順に1枚ずつ消える様子を
  /// 見せたいので、その間は盤面を凍らせて穴が開いたままにしておく。
  bool isSettling = false;

  /// いまが最下層か。
  bool get isLastFloor => floor >= dungeon.depth;

  /// 連れてきた魔導士（読み取り専用）。
  List<Mage> get roster => List.unmodifiable(_roster);

  /// 潜り始めの一党。体力は毎回満タンから。
  Party _freshParty() => Party(
    members: List.of(_roster),
    hp: Party.startingHp,
    maxHp: Party.startingHp,
  );

  void _startFloor(int n) {
    floor = n.clamp(1, dungeon.depth);
    // 盤面に敷く相も比率も、連れてきた顔ぶれで決まる。
    board = Board(
      phases: party.phases,
      weights: party.phaseWeights,
      rng: _rng,
    );
    board.buildStage(foes: dungeon.floorAt(floor).foes);
    movesLeft = dungeon.floorAt(floor).moveLimit;
    path.clear();
    hintPath = const [];
    freshTileIds = const <int>{};
    isSettling = false;
    lastHealed = 0;
    felledWards.clear();
    phase = GamePhase.playing;
  }

  /// 祝福を受け取って次の階層へ。最下層では何もしない。
  void nextFloor([Blessing? blessing]) {
    if (isLastFloor) return;
    if (blessing != null) party.grant(blessing);
    _startFloor(floor + 1);
    notifyListeners();
  }

  /// 落とした階層を編み直す。体力は既に減らしてあるので、ここでは触らない。
  void retryFloor() {
    _startFloor(floor);
    notifyListeners();
  }

  /// ダンジョンに入り直す。1階層目から、体力も満タンから。
  /// [roster] を渡すと連れていく顔ぶれも入れ替える（編成をやり直したとき）。
  void enterDungeon(Dungeon next, {List<Mage>? roster}) {
    dungeon = next;
    if (roster != null) _roster = List.of(roster);
    score = 0;
    bestChain = 0;
    lastBacklash = 0;
    party = _freshParty();
    _startFloor(1);
    notifyListeners();
  }

  /// いまのダンジョンを1階層目からやり直す。失敗したときもこれ。
  void restart() => enterDungeon(dungeon);

  bool get isTracing => path.isNotEmpty;

  /// いま指を受け付けるか。演出中は触らせない。
  bool get acceptsInput => phase == GamePhase.playing && !isSettling;

  /// 盤面に残っている敵の数。
  int get remainingFoes => board.remainingFoes;

  /// なぞり中の枚数。
  int get pathLength => path.length;

  /// なぞり中の鎖の戦果。魔導士に渡す。
  ChainTally get _tally {
    final counts = <Phase, int>{};
    for (final c in path) {
      final t = board.tileAt(c);
      if (t == null) continue;
      counts[t.phase] = (counts[t.phase] ?? 0) + 1;
    }
    return ChainTally(
      length: path.length,
      counts: counts,
      startPhase: path.isEmpty ? null : board.tileAt(path.first)?.phase,
    );
  }

  /// いまの鎖に乗っている魔導士の威力補正。
  int get powerBonus => party.powerBonusFor(_tally);

  /// いまの鎖の威力。枚数に補正を足したもの。
  int get power => path.length + powerBonus;

  /// 今離したらチェインが成立するか。
  bool get pathIsValid => board.isValidPath(path, power: power);

  /// 成立まであと何枚必要か（長さが足りているときは 0）。
  int get missingTiles =>
      (Board.minPathLength - path.length).clamp(0, Board.minPathLength);

  /// 今離したら入る点数。
  int get pendingScore =>
      pathIsValid ? Board.scoreFor(power, _pendingFelled) : 0;

  int get _pendingFelled {
    var n = 0;
    final p = power;
    for (final c in path) {
      final t = board.tileAt(c);
      if (t != null && t.isFoe && board.fells(c, p)) n++;
    }
    return n;
  }

  /// なぞり中、パス上の敵のうち、まだ威力が足りないものについて
  /// 「あと何枚伸ばせば1体討てるか」の最小値。足りているか、敵を巻き込んで
  /// いなければ 0。
  ///
  /// 1枚伸ばすと威力補正が乗ることがあり、そのときは実際にはもう1枚早く届く。
  /// 多めに言う側に倒してあるので、表示が届くと言って届かないことは無い。
  int get tilesToNextFoe {
    var best = 0;
    final p = power;
    for (final c in path) {
      final t = board.tileAt(c);
      if (t == null || !t.isFoe) continue;
      final need = t.powerToFell - p;
      if (need > 0 && (best == 0 || need < best)) best = need;
    }
    return best;
  }

  /// 今離したら討ち取れる敵の数。
  int get pendingFelled => _pendingFelled;

  bool isSelected(Cell c) => path.contains(c);

  /// なぞり中、[c] の敵が今の威力で討ち取れるか。
  /// パスに入っていない敵には関係しない。
  bool willFell(Cell c) => path.contains(c) && board.fells(c, power);

  /// なぞり中、[c] の敵に今の威力で傷がつくか。
  bool willHurt(Cell c) => path.contains(c) && board.damageAt(c, power) > 0;

  /// 次に繋げられるマスか（候補のハイライト用）。
  bool isCandidate(Cell c) {
    if (path.isEmpty || !acceptsInput) return false;
    if (path.contains(c)) return false;
    return board.canExtendPath(path, c);
  }

  void beginPath(Cell c) {
    if (!acceptsInput) return;
    if (board.tileAt(c) == null) return;
    hintPath = const [];
    path
      ..clear()
      ..add(c);
    notifyListeners();
  }

  /// なぞり中に指が [c] に乗った。伸ばせるなら伸ばし、1つ戻るなら縮める。
  /// 実際に変化したときだけ true を返す（触覚フィードバックの発火用）。
  bool extendPath(Cell c) {
    if (!acceptsInput || path.isEmpty) return false;
    if (path.length >= 2 && c == path[path.length - 2]) {
      path.removeLast();
      notifyListeners();
      return true;
    }
    if (path.contains(c)) return false;
    if (!board.canExtendPath(path, c)) return false;
    path.add(c);
    notifyListeners();
    return true;
  }

  void cancelPath() {
    if (path.isEmpty) return;
    path.clear();
    notifyListeners();
  }

  /// 指を離した。成立していればブロックを消すところまで進める。
  ///
  /// 重力と補充はここでは当てない。消した瞬間に盤面を詰めてしまうと、
  /// なぞった順に弾ける演出の上から新しいブロックが降ってきて、順番が読めない。
  /// 演出が終わったら [settle] を呼ぶこと。
  ClearResult? commitPath() {
    if (!acceptsInput) return null;
    // 戦果は盤面を崩す前に数える。
    final tally = _tally;
    final p = path.length + party.powerBonusFor(tally);
    if (!board.isValidPath(path, power: p)) {
      cancelPath();
      return null;
    }
    var result = board.applyPath(List.of(path), power: p);
    path.clear();

    lastHealed = party.heal(party.healFor(tally));
    final boltDamage = party.boltFor(tally);
    if (boltDamage > 0) {
      // 落ちる先は、雷を落とす前に控える。討ち取れた敵は盤面から消えるので、
      // あとからでは「どこに落ちたのか」が分からなくなる。
      final struck = board.foeCells;
      result = result.withBolt(board.strike(boltDamage), struck);
    }

    for (var i = 0; i < result.cells.length; i++) {
      final ward = result.wards[i];
      if (result.cleared[i] && ward != null) felledWards.add(ward);
    }
    for (final fall in result.bolt) {
      felledWards.add(fall.ward);
    }

    score += result.gained;
    // 風が居れば長い鎖でターンが戻る。使った1手より戻りが多くなることは無い。
    movesLeft += party.turnGainFor(tally) - 1;
    if (score > best) best = score;
    if (result.power > bestChain) bestChain = result.power;

    freshTileIds = const <int>{};
    isSettling = true;
    notifyListeners();
    return result;
  }

  /// 消える演出が終わった。重力で詰めて補充し、次の状態を判定する。
  void settle() {
    if (!isSettling) return;
    isSettling = false;

    board.applyGravity();
    freshTileIds = board.refill();

    if (board.remainingFoes == 0) {
      phase = isLastFloor ? GamePhase.dungeonCleared : GamePhase.stageCleared;
    } else if (movesLeft <= 0 || !board.hasAnyChain()) {
      // 討ち漏らした敵の反撃。守りが厚い敵を残すほど高くつく。
      // 盾が居れば半分に減る。
      lastBacklash = party.backlashFor(board.foeThreat);
      party.takeDamage(lastBacklash);
      phase = party.isDown ? GamePhase.defeated : GamePhase.floorLost;
    }
    notifyListeners();
  }

  void showHint() {
    if (!acceptsInput) return;
    hintPath = board.findHint();
    notifyListeners();
  }

  void clearHint() {
    if (hintPath.isEmpty) return;
    hintPath = const [];
    notifyListeners();
  }
}
