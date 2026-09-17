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

  bool get isTracing => path.isNotEmpty;

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
    if (path.isEmpty || phase != GamePhase.playing) return false;
    if (path.contains(c)) return false;
    return board.canExtend(path.last, c);
  }

  void beginPath(Cell c) {
    if (phase != GamePhase.playing) return;
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
    if (phase != GamePhase.playing || path.isEmpty) return false;
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

  /// 指を離した。成立していれば消して、重力・補充・詰み判定まで進める。
  ClearResult? commitPath() {
    if (phase != GamePhase.playing) return null;
    if (!board.isValidPath(path)) {
      cancelPath();
      return null;
    }
    final result = board.applyPath(List.of(path));
    path.clear();
    score += result.gained;
    if (score > best) best = score;
    if (result.length > bestChain) bestChain = result.length;

    board.applyGravity();
    freshTileIds = board.refill();

    if (!board.hasAnyPath()) {
      phase = GamePhase.gameOver;
    }
    notifyListeners();
    return result;
  }

  void showHint() {
    if (phase != GamePhase.playing) return;
    hintPath = board.findBestPath();
    notifyListeners();
  }

  void clearHint() {
    if (hintPath.isEmpty) return;
    hintPath = const [];
    notifyListeners();
  }
}
