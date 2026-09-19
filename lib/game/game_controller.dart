import 'package:flutter/foundation.dart';

import 'board.dart';
import 'party.dart';

/// 階層の決着。
///
///  - [stageCleared] … その階層の敵を討ち果たした。祝福を1つ選んで次の階層へ
///  - [floorLost] … ターン切れか手詰まり。討ち漏らした敵の反撃を受けて編み直す
///  - [defeated] … 反撃で一党の体力が尽きた。ここで終わり
enum GamePhase { playing, stageCleared, floorLost, defeated }

/// 盤面の上に乗る「遊び」の状態管理。
///
/// 階層制。敵を全部討てば制圧、ターンを使い切れば階層を落とす。
/// 階層をまたいで残るのは [party] だけで、盤面は毎回編み直される。
class GameController extends ChangeNotifier {
  GameController({Board Function()? createBoard, int startStage = 1})
    : _createBoard = createBoard ?? Board.new {
    party = Party.initial();
    _startStage(startStage);
  }

  final Board Function() _createBoard;

  late Board board;

  /// 階層をまたいで持ち越す一党。
  late Party party;

  /// 1から始まる階層番号。深いほど敵が増え、守りも体力も厚くなる。
  late int stage;

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

  /// この階層に置く敵の数。5体で頭打ち。
  static int foeCountFor(int stage) => stage.clamp(1, 5);

  /// この階層の敵の守りの上限。
  /// 序盤は小さい数字しか出ないので、ルールを覚えるうちは詰まらない。
  static int maxWardFor(int stage) =>
      (Board.minWard + stage).clamp(Board.minWard + 1, Board.maxWard);

  /// この階層の敵の体力の上限。深くなってから2回・3回と殴らせる。
  /// 序盤は 1 のまま＝体力を持たなかった頃と同じ手触りにしておく。
  static int maxFoeHpFor(int stage) {
    if (stage <= 2) return 1;
    if (stage <= 5) return 2;
    return 3;
  }

  /// この階層の手数。敵の体力の合計から決まるが、6階以降は1階ごとに1手ずつ削る。
  static int moveLimitFor(int stage, {int? totalFoeHp}) {
    final hp = totalFoeHp ?? foeCountFor(stage);
    final base = Board.movesFor(hp);
    final squeeze = stage > 5 ? stage - 5 : 0;
    return (base - squeeze).clamp(hp * 2, base);
  }

  void _startStage(int n) {
    stage = n;
    board = _createBoard();
    board.buildStage(
      foeCount: foeCountFor(n),
      wardCap: maxWardFor(n),
      maxFoeHp: maxFoeHpFor(n),
    );
    movesLeft = moveLimitFor(n, totalFoeHp: board.totalFoeHp);
    path.clear();
    hintPath = const [];
    freshTileIds = const <int>{};
    isSettling = false;
    lastHealed = 0;
    felledWards.clear();
    phase = GamePhase.playing;
  }

  /// 祝福を受け取って次の階層へ。
  void nextStage([Blessing? blessing]) {
    if (blessing != null) party.grant(blessing);
    _startStage(stage + 1);
    notifyListeners();
  }

  /// 落とした階層を編み直す。体力は既に減らしてあるので、ここでは触らない。
  void retryFloor() {
    _startStage(stage);
    notifyListeners();
  }

  /// 最初からやり直す。一党もスコアも戻す。
  void restart() {
    score = 0;
    bestChain = 0;
    lastBacklash = 0;
    party = Party.initial();
    _startStage(1);
    notifyListeners();
  }

  bool get isTracing => path.isNotEmpty;

  /// いま指を受け付けるか。演出中は触らせない。
  bool get acceptsInput => phase == GamePhase.playing && !isSettling;

  /// 盤面に残っている敵の数。
  int get remainingFoes => board.remainingFoes;

  /// なぞり中の枚数。
  int get pathLength => path.length;

  /// なぞり中の鎖の戦果。魔導士に渡す。
  ChainTally get _tally {
    var heat = 0;
    var frost = 0;
    for (final c in path) {
      final t = board.tileAt(c);
      if (t == null) continue;
      if (t.isOdd) {
        heat++;
      } else {
        frost++;
      }
    }
    return ChainTally(length: path.length, heat: heat, frost: frost);
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
    return board.canExtend(path.last, c);
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
    if (!board.canExtend(path.last, c)) return false;
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
    if (party.boltFor(p)) {
      // 落ちる先は、雷を落とす前に控える。討ち取れた敵は盤面から消えるので、
      // あとからでは「どこに落ちたのか」が分からなくなる。
      final struck = board.foeCells;
      result = result.withBolt(board.strike(1), struck);
    }

    for (var i = 0; i < result.cells.length; i++) {
      final ward = result.wards[i];
      if (result.cleared[i] && ward != null) felledWards.add(ward);
    }
    for (final fall in result.bolt) {
      felledWards.add(fall.ward);
    }

    score += result.gained;
    movesLeft--;
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
      phase = GamePhase.stageCleared;
    } else if (movesLeft <= 0 || !board.hasAnyChain()) {
      // 討ち漏らした敵の反撃。守りが厚い敵を残すほど高くつく。
      lastBacklash = board.foeThreat;
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
