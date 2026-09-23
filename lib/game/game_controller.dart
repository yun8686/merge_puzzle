import 'dart:math';

import 'package:flutter/foundation.dart';

import 'board.dart';
import 'dungeon.dart';
import 'phase.dart';
import 'party.dart';

/// 階層の決着。
///
///  - [stageCleared] … その階層の敵を討ち果たした。そのまま次の階層へ
///  - [dungeonCleared] … 最下層まで討ち果たした。ダンジョンの踏破
///  - [defeated] … 反撃で一党の体力が尽きた。このダンジョンは失敗
///
/// **負けは体力が尽きたときだけ。** 手詰まりで階層を落とす決着もあったが、
/// 盤面の運で負けるのは理不尽なので、今は盤面を敷き直して続ける
/// （[Board.reshuffle]、README 第23段階）。
enum GamePhase { playing, stageCleared, dungeonCleared, defeated }

/// アクティブスキルを使った結果。
///
/// **[missed] と [unavailable] を分けるのは、言うことが違うから。**
/// 使えないのは編成や場面の話で、届かなかったのは盤面の話。同じ「使えません」
/// にまとめると、どちらを直せばいいのか分からない。
enum ActiveResult {
  /// 通った。回数を1つ使った。
  done,

  /// そもそも使えない。連れていない・力を持たない・もう使った・盤面が動いて
  /// いる。画面は札を出さないので、普通はここに来ない。
  unavailable,

  /// 使えたが、効く先が無かった。**回数は減らさない。**
  ///
  /// 潜り1本に1回しかない札を、「どこにも届かない」と知るためだけに
  /// 使わせない。何も起きなかったのだから、何も減らない。
  missed,
}

/// 盤面の上に乗る「遊び」の状態管理。
///
/// ダンジョン制。[dungeon] の階層を1階層目から順に降り、最下層を制圧すれば踏破。
/// 体力が尽きたらそのダンジョンは失敗で、**1階層目からやり直す**。
///
/// 一党は潜る前に決めて、**道中では何も増えない**。体力は潜り1本を通した
/// 資源で、階層をまたいでも戻らない。誰を連れていくかは編成の側の判断に
/// 閉じている。
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

  final List<Cell> path = <Cell>[];
  int score = 0;
  int best = 0;
  int bestChain = 0;
  GamePhase phase = GamePhase.playing;

  /// 直近の鎖で氷雨が戻した体力。0 なら何も起きていない。
  int lastHealed = 0;

  /// 直近の1手で敵から受けた痛手。0 なら何も起きていない。
  int lastHit = 0;

  /// 直近の鎖が風の条件を満たして、その手の反撃を凌いだか。
  ///
  /// **[lastHit] が 0 なだけでは理由が読めない。** 討ち果たした手も 0 に
  /// なるので、凌いだことは別に持って帯に出す。
  bool lastEvaded = false;

  /// 盤面は詰み終わっていて、敵の反撃を待っている。
  ///
  /// 消した瞬間に殴られると、**自分の手と相手の手が重なって読めない**。
  /// 盤面が詰んだのを見せてから殴る。この間は手を受け付けない（殴られる前に
  /// 次の手を打たれると、反撃が起きた順が分からなくなる）。
  ///
  /// [settle] で立ち、[strike] で下りる。盤面を描く側が間を置いて呼ぶ。
  bool isStriking = false;

  /// 手詰まりで盤面を敷き直した回数。稽古場が「決めた道が盤面ごと
  /// 消えた」と知るのに使う。
  int reshuffles = 0;

  /// 直近の反撃のあとに盤面を敷き直した。なぞり始めるまで盤面の下で言う。
  ///
  /// **黙って入れ替えると、何が起きたのか分からない。** マスが全部降り直して
  /// くるので動きは見えるが、なぜそうなったのかは言わないと伝わらない。
  bool reshuffled = false;

  /// 痛手を受けた回数。**演出はこれが変わったのを見て走り出す。**
  ///
  /// 量（[lastHit]）だけを見ていると、同じ量の痛手が続けて来たときに値が
  /// 変わらず、2回目の演出が鳴らない。
  int hitTick = 0;

  /// この階層で討ち取った敵の守り。討った順に積む。制圧画面に姿を並べるのに使う。
  /// 敵は盤面から消えてしまうので、ここに控えておかないと何を討ったか分からない。
  final List<int> felledWards = <int>[];

  /// 直近に補充されたブロックの id。降ってくる演出に使う。
  Set<int> freshTileIds = <int>{};

  List<Cell> hintPath = <Cell>[];

  /// アクティブスキル（[Foresee]）が見せた道。**鎖を1本編むまで消えない。**
  ///
  /// [hintPath] はなぞり始めると引っ込む（自分の指と重なって読めない）が、
  /// 潜り1本に1回しか使えないものを、指が触れただけで失わせるのは酷い。
  /// 離せば戻す（[cancelPath]）。盤面が変わったら意味を失うので、鎖が
  /// 編まれたところで捨てる。
  List<Cell> revealedPath = const [];

  /// なぞれる道を1本に縛る。空なら自由（本番はいつも空）。
  ///
  /// **稽古場のためにある。** 決めた道の通りにしかなぞれなくなるので、
  /// 教えたい形の鎖が必ず編まれる。始まりのマスも、次に継げるマスも1つに
  /// 決まり、全部なぞり切るまで[commitPath]も通らない。
  List<Cell> lockedPath = const [];

  /// 編んだ鎖の本数。稽古場が「決めた道はもう辿られた」と知るのに使う。
  int chains = 0;

  /// 消した直後、重力と補充を当てるまでの間。なぞった順に1枚ずつ消える様子を
  /// 見せたいので、その間は盤面を凍らせて穴が開いたままにしておく。
  bool isSettling = false;

  /// いまが最下層か。
  bool get isLastFloor => floor >= dungeon.depth;

  /// 連れてきた魔導士（読み取り専用）。
  List<Mage> get roster => List.unmodifiable(_roster);

  /// 潜り始めの一党。体力は毎回満タンから。
  Party _freshParty() => Party.of(_roster);

  void _startFloor(int n) {
    floor = n.clamp(1, dungeon.depth);
    // 盤面に敷く相も比率も、連れてきた顔ぶれで決まる。
    board = Board(
      phases: party.phases,
      weights: party.phaseWeights,
      rng: _rng,
    );
    board.buildStage(foes: dungeon.floorAt(floor).foes);
    path.clear();
    hintPath = const [];
    lockedPath = const [];
    chains = 0;
    freshTileIds = const <int>{};
    isSettling = false;
    isStriking = false;
    lastHealed = 0;
    lastHit = 0;
    lastEvaded = false;
    reshuffled = false;
    revealedPath = const [];
    felledWards.clear();
    phase = GamePhase.playing;
  }

  /// 次の階層へ。最下層では何もしない。
  ///
  /// **体力はそのまま持ち越す。** 階層をまたいで戻る手立ては無い
  /// （氷雨の回復だけが鎖のたびに効く）。
  void nextFloor() {
    if (isLastFloor) return;
    _startFloor(floor + 1);
    notifyListeners();
  }

  /// ダンジョンに入り直す。1階層目から、体力も満タンから。
  /// [roster] を渡すと連れていく顔ぶれも入れ替える（編成をやり直したとき）。
  void enterDungeon(Dungeon next, {List<Mage>? roster}) {
    dungeon = next;
    if (roster != null) _roster = List.of(roster);
    score = 0;
    bestChain = 0;
    party = _freshParty();
    _startFloor(1);
    notifyListeners();
  }

  /// いまのダンジョンを1階層目からやり直す。失敗したときもこれ。
  void restart() => enterDungeon(dungeon);

  bool get isTracing => path.isNotEmpty;

  /// いま指を受け付けるか。演出中は触らせない。
  bool get acceptsInput =>
      phase == GamePhase.playing && !isSettling && !isStriking;

  /// 盤面に残っている敵の数。
  int get remainingFoes => board.remainingFoes;

  /// なぞり中の枚数。
  int get pathLength => path.length;

  /// なぞり中の鎖の戦果。魔導士に渡す。
  ChainTally get _tally => tallyOf(path);

  /// [cells] を1本の鎖として見たときの戦果。
  ///
  /// なぞり中の道だけでなく、**まだなぞっていない道**にも使う
  /// （[useActive] が候補の威力を測るのに要る）。
  ChainTally tallyOf(List<Cell> cells) {
    final counts = <Phase, int>{};
    for (final c in cells) {
      final t = board.tileAt(c);
      if (t == null) continue;
      counts[t.phase] = (counts[t.phase] ?? 0) + 1;
    }
    return ChainTally(
      length: cells.length,
      counts: counts,
      startPhase: cells.isEmpty ? null : board.tileAt(cells.first)?.phase,
    );
  }

  /// [cells] を編んだときの威力。枚数に魔導士の補正を足したもの。
  int powerOf(List<Cell> cells) =>
      cells.length + party.powerBonusFor(tallyOf(cells));

  /// アクティブスキルを使う。
  ///
  /// **回数を数えるのは [Party]。** 潜るたびに組み直されるので、
  /// 「1ダンジョンに1回」はそこに置くだけで成り立つ。
  ///
  /// **どの力かで分岐しない。** 何をするかは [Active] 自身が知っていて、
  /// ここは [ActiveStage] を渡して結果を受け取るだけ。力が100種類に増えても
  /// このメソッドは変わらない（`actives.dart`）。
  ///
  /// **空振りでは何も減らさない**（[ActiveResult.missed]）。敵に1でも届く道が
  /// 無いときに、成立するだけの道を見せてお茶を濁さない――知りたいのは
  /// 「どこを通れば効くか」であって、「どこかは繋がる」ではない。
  ActiveResult useActive(MageKind kind) {
    if (!acceptsInput) return ActiveResult.unavailable;
    final mage = party.memberOf(kind);
    final active = mage?.active;
    if (active == null || !party.canUse(kind)) return ActiveResult.unavailable;
    // 相は持ち主から渡す。力の側は誰のものかを知らない。
    if (!active.cast(_Stage(this), mage!.phase)) return ActiveResult.missed;
    party.spendUse(kind);
    notifyListeners();
    return ActiveResult.done;
  }

  /// いまの鎖に乗っている魔導士の威力補正。
  int get powerBonus => party.powerBonusFor(_tally);

  /// いまの鎖の威力。枚数に補正を足したもの。
  int get power => path.length + powerBonus;

  /// 今離したらチェインが成立するか。
  ///
  /// 道を縛っているあいだは、なぞり切るまで成立しない（[commitPath] が
  /// 通さない）。威力の色も「いま離せば鎖になる」を指したままになる。
  bool get pathIsValid {
    if (lockedPath.isNotEmpty && path.length != lockedPath.length) return false;
    return board.isValidPath(path, power: power);
  }

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
    if (lockedPath.isNotEmpty) {
      return path.length < lockedPath.length && c == lockedPath[path.length];
    }
    return board.canExtendPath(path, c);
  }

  void beginPath(Cell c) {
    if (!acceptsInput) return;
    if (board.tileAt(c) == null) return;
    // 縛られているときは、決めた道の始まりからしか引けない。
    if (lockedPath.isNotEmpty && c != lockedPath.first) return;
    hintPath = const [];
    reshuffled = false;
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
    // 縛られているときに継げるのは、決めた道の次の1マスだけ。
    if (lockedPath.isNotEmpty &&
        (path.length >= lockedPath.length || c != lockedPath[path.length])) {
      return false;
    }
    if (!board.canExtendPath(path, c)) return false;
    path.add(c);
    notifyListeners();
    return true;
  }

  void cancelPath() {
    if (path.isEmpty) return;
    path.clear();
    // 編まずに離したなら、先読みで見せた道はまだ活きている。
    if (revealedPath.isNotEmpty) hintPath = revealedPath;
    notifyListeners();
  }

  /// 指を離した。成立していればブロックを消すところまで進める。
  ///
  /// 重力と補充はここでは当てない。消した瞬間に盤面を詰めてしまうと、
  /// なぞった順に弾ける演出の上から新しいブロックが降ってきて、順番が読めない。
  /// 演出が終わったら [settle] を呼ぶこと。
  ClearResult? commitPath() {
    if (!acceptsInput) return null;
    // 縛られているときは、途中で離しても何も起きない。殴られもしない。
    // もう一度なぞればよい。
    if (lockedPath.isNotEmpty && path.length != lockedPath.length) {
      cancelPath();
      return null;
    }
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
    chains++;
    for (final fall in result.bolt) {
      felledWards.add(fall.ward);
    }

    // 盤面が変わるので、先読みで見せた道はここで捨てる。
    revealedPath = const [];
    hintPath = const [];
    // 延焼は1本きり。編んだところで決まりは元に戻る。
    board.spreadPhase = null;

    score += result.gained;
    // 風が居れば、長い鎖を編んだ手は殴られずに済む。効かせるのは毎ターンの
    // 反撃だけで、階層を落としたときの締めには効かない。
    lastEvaded = party.evadesFor(tally);
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
      // 討ち果たした手は殴られない。最後の1体を討った瞬間に反撃が来ると、
      // 制圧したのに体力が減る、という腑に落ちない目に遭う。
      lastHit = 0;
      phase = isLastFloor ? GamePhase.dungeonCleared : GamePhase.stageCleared;
      notifyListeners();
      return;
    }

    // ここでは殴らない。盤面が詰んだのを見せてから [strike] を呼ぶ。
    isStriking = true;
    notifyListeners();
  }

  /// 生き残った敵の反撃。[settle] が盤面を詰め終えてから、間を置いて呼ぶ。
  ///
  /// 討ち取れば減るので、早く討つほど後が楽になる。盾が居れば半分。
  void strike() {
    if (!isStriking) return;
    isStriking = false;

    lastHit = lastEvaded ? 0 : party.damageFor(board.foeAttack);
    party.takeDamage(lastHit);

    // 手数の制限は無く、負けるのは体力が尽きたときだけ。1手ごとに殴られる
    // ので、長居そのものが体力で値段を払っている。
    if (party.isDown) {
      phase = GamePhase.defeated;
    } else if (!board.hasAnyChain()) {
      // 手詰まり。階層は落とさず、敵を残して盤面だけ敷き直す。上乗せの
      // 痛手も無い――運で詰んだ盤面に値段を付けると、打つ手が無いまま削られる。
      freshTileIds = board.reshuffle();
      hintPath = const [];
      reshuffles++;
      reshuffled = true;
    }

    if (lastHit > 0) hitTick++;
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

/// アクティブスキルに渡す舞台。**盤面を知っているのはこちら側。**
///
/// [ActiveStage] の動詞をここで実装する。[GameController] に直に持たせないのは、
/// 力が増えて動詞が増えるたびに、進行の表向きの API まで太っていくため。
///
/// 画面の描き直しは呼び出し側（[GameController.useActive]）が1回だけ行う。
/// ここで [ChangeNotifier.notifyListeners] を呼ぶと、動詞を2つ使う力を
/// 足したときに途中の盤面が一度描かれてしまう。
class _Stage implements ActiveStage {
  const _Stage(this._game);

  final GameController _game;

  @override
  bool revealBestRoute() {
    final route = _game.board.bestStrike(powerOf: _game.powerOf);
    if (route.isEmpty) return false;
    _game.revealedPath = route;
    _game.hintPath = route;
    return true;
  }

  @override
  bool spread(Phase phase) {
    // その相だけでは3枚もつながらない盤面なら、緩めても編める鎖は増えない。
    if (!_game.board.hasSamePhaseRun(phase)) return false;
    _game.board.spreadPhase = phase;
    // 見せてあった道は、緩めた決まりの下では最善とは限らない。
    _game.revealedPath = const [];
    _game.hintPath = const [];
    return true;
  }
}
