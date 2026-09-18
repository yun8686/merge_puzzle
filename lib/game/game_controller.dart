import 'package:flutter/foundation.dart';

import 'board.dart';

enum GamePhase { playing, stageCleared, failed }

/// 盤面の上に乗る「遊び」の状態管理。
///
/// ステージ制。目標ブロックを全部消せばクリア、手数を使い切れば失敗。
class GameController extends ChangeNotifier {
  GameController({Board Function()? createBoard, int startStage = 1})
      : _createBoard = createBoard ?? Board.new {
    _startStage(startStage);
  }

  final Board Function() _createBoard;

  late Board board;

  /// 1から始まるステージ番号。進むほど目標が増え、数字も大きくなる。
  late int stage;

  /// このステージに残っている手数。
  late int movesLeft;

  final List<Cell> path = <Cell>[];
  int score = 0;
  int best = 0;
  int bestChain = 0;
  GamePhase phase = GamePhase.playing;

  /// 直近に補充されたブロックの id。降ってくる演出に使う。
  Set<int> freshTileIds = <int>{};

  List<Cell> hintPath = <Cell>[];

  /// いまの盤面ではどう繋いでも消せない目標ブロック。
  ///
  /// 盤面が変わるたびに計算し直す。毎フレーム引き直すと無駄なので、
  /// 手が進んだときだけ更新して結果を持っておく。
  Set<Cell> unclearableTargets = <Cell>{};

  void _refreshUnclearable() {
    unclearableTargets = <Cell>{
      for (final cell in board.targetCells)
        if (!board.canClearTarget(cell)) cell,
    };
  }

  /// 消した直後、重力と補充を当てるまでの間。なぞった順に1枚ずつ消える様子を
  /// 見せたいので、その間は盤面を凍らせて穴が開いたままにしておく。
  bool isSettling = false;

  /// このステージに置く目標ブロックの数。5個で頭打ち。
  static int targetCountFor(int stage) => stage.clamp(1, 5);

  /// このステージの目標ブロックに書ける数字の上限。
  /// 序盤は小さい数字しか出ないので、ルールを覚えるうちは詰まらない。
  static int maxRequiredFor(int stage) =>
      (Board.minRequired + stage).clamp(Board.minRequired + 1, Board.maxRequired);

  /// このステージの手数。目標数から決まるが、6面以降は1面ごとに1手ずつ削る。
  static int moveLimitFor(int stage) {
    final targets = targetCountFor(stage);
    final base = Board.movesFor(targets);
    final squeeze = stage > 5 ? stage - 5 : 0;
    return (base - squeeze).clamp(targets * 2, base);
  }

  void _startStage(int n) {
    stage = n;
    board = _createBoard();
    board.buildStage(
      targetCount: targetCountFor(n),
      maxRequiredLength: maxRequiredFor(n),
    );
    movesLeft = moveLimitFor(n);
    _refreshUnclearable();
    path.clear();
    hintPath = const [];
    freshTileIds = const <int>{};
    isSettling = false;
    phase = GamePhase.playing;
  }

  /// クリアして次のステージへ。
  void nextStage() {
    _startStage(stage + 1);
    notifyListeners();
  }

  /// 最初からやり直す。スコアも戻す。
  void restart() {
    score = 0;
    bestChain = 0;
    _startStage(1);
    notifyListeners();
  }

  bool get isTracing => path.isNotEmpty;

  /// いま指を受け付けるか。演出中は触らせない。
  bool get acceptsInput => phase == GamePhase.playing && !isSettling;

  /// 盤面に残っている目標ブロックの数。
  int get remainingTargets => board.remainingTargets;

  /// なぞり中のチェイン長。
  int get pathLength => path.length;

  /// 今離したらチェインが成立するか。
  bool get pathIsValid => board.isValidPath(path);

  /// 成立まであと何枚必要か（長さが足りているときは 0）。
  int get missingTiles =>
      (Board.minPathLength - path.length).clamp(0, Board.minPathLength);

  /// 今離したら入る点数。
  int get pendingScore => pathIsValid
      ? Board.scoreFor(path.length, _pendingClearedTargets)
      : 0;

  int get _pendingClearedTargets {
    var n = 0;
    for (final c in path) {
      final t = board.tileAt(c);
      if (t != null && t.isTarget && board.clearsAt(c, path.length)) n++;
    }
    return n;
  }

  /// なぞり中、パス上の目標ブロックのうち、まだ長さが足りないものについて
  /// 「あと何枚伸ばせば1つ消えるか」の最小値。足りているか、目標を巻き込んで
  /// いなければ 0。
  int get tilesToNextTarget {
    var best = 0;
    for (final c in path) {
      final t = board.tileAt(c);
      if (t == null || !t.isTarget) continue;
      final need = t.requiredLength! - path.length;
      if (need > 0 && (best == 0 || need < best)) best = need;
    }
    return best;
  }

  /// 今離したら消える目標ブロックの数。
  int get pendingClearedTargets => _pendingClearedTargets;

  bool isSelected(Cell c) => path.contains(c);

  /// なぞり中、[c] の目標ブロックが今の長さで消えるか。
  /// パスに入っていない目標ブロックには関係しない。
  bool willClear(Cell c) => path.contains(c) && board.clearsAt(c, path.length);

  /// [c] の目標ブロックが、いまの盤面ではどう繋いでも消せないか。
  bool isUnclearable(Cell c) => unclearableTargets.contains(c);

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
    if (!board.isValidPath(path)) {
      cancelPath();
      return null;
    }
    final result = board.applyPath(List.of(path));
    path.clear();
    score += result.gained;
    movesLeft--;
    if (score > best) best = score;
    if (result.length > bestChain) bestChain = result.length;

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
    _refreshUnclearable();

    if (board.remainingTargets == 0) {
      phase = GamePhase.stageCleared;
    } else if (movesLeft <= 0) {
      phase = GamePhase.failed;
    } else if (!board.hasAnyChain()) {
      phase = GamePhase.failed;
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
