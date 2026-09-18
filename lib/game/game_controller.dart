import 'package:flutter/foundation.dart';

import 'board.dart';

enum GamePhase { playing, gameOver }

/// 盤面の上に乗る「遊び」の状態管理。なぞり中のパス、スコア、ゲームオーバー判定。
class GameController extends ChangeNotifier {
  GameController({Board? board}) : board = board ?? Board() {
    this.board.fillInitial();
  }

  final Board board;

  final List<Cell> path = <Cell>[];
  int score = 0;
  int best = 0;
  int bestChain = 0;
  GamePhase phase = GamePhase.playing;

  /// 直近に補充されたタイルの id。降ってくる演出に使う。
  Set<int> freshTileIds = <int>{};

  List<Cell> hintPath = <Cell>[];

  /// 消した直後、重力と補充を当てるまでの間。なぞった順に1枚ずつ消える様子を
  /// 見せたいので、その間は盤面を凍らせて穴が開いたままにしておく。
  bool isSettling = false;

  bool get isTracing => path.isNotEmpty;

  /// いま指を受け付けるか。演出中は触らせない。
  bool get acceptsInput => phase == GamePhase.playing && !isSettling;

  /// なぞり中のパスの合計値。
  int get pathTotal => board.totalOf(path);

  /// いま成立に必要な合計値。
  int get requiredTotal => board.requiredTotal;

  /// 今離したらチェインが成立するか。
  bool get pathIsValid =>
      path.length >= Board.minPathLength && pathTotal >= requiredTotal;

  /// 成立まであと何枚必要か（合計値が足りているときは 0）。
  int get missingTiles =>
      (Board.minPathLength - path.length).clamp(0, Board.minPathLength);

  /// 成立まであといくつ合計値が足りないか。
  int get missingTotal => (requiredTotal - pathTotal).clamp(0, requiredTotal);

  /// 今離したら入る点数。
  int get pendingScore =>
      pathIsValid ? Board.scoreFor(pathTotal, path.length) : 0;

  bool isSelected(Cell c) => path.contains(c);

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

  /// 指を離した。成立していればタイルを消すところまで進める。
  ///
  /// 重力と補充はここでは当てない。消した瞬間に盤面を詰めてしまうと、
  /// なぞった順に弾ける演出の上から新しいタイルが降ってきて、順番が読めない。
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
    if (score > best) best = score;
    if (result.length > bestChain) bestChain = result.length;

    freshTileIds = const <int>{};
    isSettling = true;
    notifyListeners();
    return result;
  }

  /// 消える演出が終わった。重力で詰めて補充し、次の手があるか判定する。
  void settle() {
    if (!isSettling) return;
    isSettling = false;

    board.applyGravity();
    freshTileIds = board.refill();

    if (!board.hasAnyPath()) {
      phase = GamePhase.gameOver;
    }
    notifyListeners();
  }

  void showHint() {
    if (!acceptsInput) return;
    hintPath = board.findBestPath();
    notifyListeners();
  }

  void clearHint() {
    if (hintPath.isEmpty) return;
    hintPath = const [];
    notifyListeners();
  }
}
