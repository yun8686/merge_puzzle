import 'dart:math';

import 'phase.dart';

/// 盤面上の座標。row=0 が最上段。
class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => row * 131 + col;

  @override
  String toString() => '($row,$col)';
}

/// 1枚のブロック。id はアニメーションで同一ブロックを追跡するために使う。
///
/// マナのマスは偶奇（＝相）しか持たず、数字は書かれていない。
/// 敵だけが [ward]（守り）と [hp]（体力）を持ち、守りが盤面に数字で書かれる。
///
/// 守りは「この威力までは弾く」しきい値で、上回った分がそのままダメージになる。
/// 体力が 1 なら守りを1でも上回った時点で討ち取れるので、体力を持たなかった
/// 頃のルールと完全に同じ挙動になる。
class Tile {
  const Tile({
    required this.id,
    required this.phase,
    this.ward,
    this.hp = 1,
    int? maxHp,
    int? atk,
  }) : maxHp = maxHp ?? hp,
       _atk = atk;

  final int id;
  /// このマスの相。同じ相は近くに二度継げない。
  final Phase phase;

  /// 敵なら守り。マナのマスは null。
  final int? ward;

  /// 敵の残り体力。マナのマスでは使わない。
  final int hp;

  /// 敵の最大体力。減り具合を見せるために持っている。
  final int maxHp;

  /// 手で指定された攻撃力。省かれていれば守りの厚さから決める。
  ///
  /// [Tile] は const で作るので、ここで [Board.attackFor] を呼べない
  /// （定数式にならない）。[atk] で引くときに求める。
  final int? _atk;

  /// 敵の攻撃力。**盤面には出さない隠し値。** 毎ターン、残っている敵の
  /// 合計だけ一党の体力が削れる。
  ///
  /// マスに出ているのは守りだけで、これは鎖の長さを決める唯一の値だから
  /// 見せている。攻撃力まで並べると 40〜50px のマスが読めなくなるし、
  /// 「厚い敵ほど痛い」という対応さえ付いていれば、数字を見なくても
  /// 何ターンで落ちるかは体力バーの減り方で分かる。
  int get atk =>
      _atk ?? (ward == null ? 0 : Board.attackFor(ward!));

  bool get isFoe => ward != null;

  /// 威力 [power] の鎖がこの敵に通すダメージ。守り以下なら弾かれて 0。
  int damageFrom(int power) {
    final d = power - ward! + 1;
    return d < 0 ? 0 : d;
  }

  /// この敵に傷をつけるのに要る最低の威力。＝守り。
  int get powerToHurt => ward!;

  /// 1本の鎖で討ち取るのに要る威力。守りを1上回るごとに1ダメージなので、
  /// 残り体力のぶんだけ余分に要る。
  int get powerToFell => ward! + hp - 1;

  /// ダメージを受けて残った姿。id を引き継ぐので演出は同じブロックとして追う。
  Tile hurt(int damage) => Tile(
    id: id,
    phase: phase,
    ward: ward,
    hp: hp - damage,
    maxHp: maxHp,
    atk: _atk,
  );
}

/// 階層に置く敵1体ぶんの指定。ダンジョンの階層を手で書くのに使う。
///
/// 散らす方（[Board.buildStage] の [foeCount] 側）は「守りが厚い敵ほど体力は
/// 薄く」という縛りを掛けているが、こちらは掛けない。手で書く以上、厚い守りと
/// 厚い体力を重ねてよいのはボスだけ、という判断は書く側の責任になる。
class FoeSpec {
  const FoeSpec(this.ward, {this.hp = 1, this.atk});

  final int ward;
  final int hp;

  /// 攻撃力。省くと守りの厚さから決まる（[Board.attackFor]）。
  /// **盤面には出さない隠し値。** 手で強くしたい敵だけここで上書きする。
  final int? atk;
}

/// 鎖の外で討ち取られた敵。いまは雷の魔導士の追撃だけがこれを作る。
/// 演出に要る情報しか持たない。
class FoeFall {
  const FoeFall({required this.cell, required this.ward, required this.phase});

  final Cell cell;
  final int ward;
  /// このマスの相。同じ相は近くに二度継げない。
  final Phase phase;
}

/// なぞって消したときの結果。演出側はこれを見てエフェクトを出す。
class ClearResult {
  const ClearResult({
    required this.cells,
    required this.cleared,
    required this.wards,
    required this.damages,
    required this.phases,
    required this.power,
    required this.felled,
    required this.gained,
    required this.endCell,
    this.bolt = const <FoeFall>[],
    this.boltCells = const <Cell>[],
  });

  /// なぞった順のマス。
  final List<Cell> cells;

  /// [cells] と同じ並びで、そのマスが実際に消えたか。
  /// 討ち取れなかった敵だけが false になる。
  final List<bool> cleared;

  /// [cells] と同じ並びで、敵なら守り。マナのマスは null。
  final List<int?> wards;

  /// [cells] と同じ並びで、敵に通ったダメージ。マナのマスは 0。
  /// 0 なら弾かれている。
  final List<int> damages;

  /// [cells] と同じ並びの相。演出の色に使う。
  final List<Phase> phases;

  /// この鎖の威力。枚数に魔導士の補正を足したもの。
  final int power;

  /// この鎖で討ち取った敵の数。
  final int felled;

  /// この鎖で得た点数。
  final int gained;

  /// 演出をどこに出すかだけに使う、なぞり終わりのマス。
  final Cell endCell;

  /// 鎖とは別に討ち取られた敵。
  final List<FoeFall> bolt;

  /// 追撃が当たったマス。討ち取れた敵も、削っただけの敵も入る。
  /// [bolt] は討ち取れた敵しか持たないので、演出はこちらを見る。
  /// 削っただけの敵にも雷を落として見せないと、何が起きたのか伝わらない。
  final List<Cell> boltCells;

  int get length => cells.length;

  /// 鎖の外で起きた追撃を足した結果を返す。盤面ロジックは追撃を知らないので、
  /// パーティー側から後付けする。[struck] は落ちる前の敵の位置。
  ClearResult withBolt(List<FoeFall> fallen, List<Cell> struck) => ClearResult(
    cells: cells,
    cleared: cleared,
    wards: wards,
    damages: damages,
    phases: phases,
    power: power,
    felled: felled + fallen.length,
    gained: gained,
    endCell: endCell,
    bolt: List.unmodifiable(fallen),
    boltCells: List.unmodifiable(struck),
  );
}

/// 盤面ロジック。UI から独立していてテスト可能。
///
/// 盤面に出る相は [phases] で決まる。編成に含まれる相だけが敷かれるので、
/// 誰を連れていくかがそのまま盤面の色数になる。ここは相の意味を持たず、
/// [Phase] の値と数だけで話す。
///
/// ルール:
///  - 上下左右に隣接するブロックを辿ってパスを作る
///  - **色は問わない。** 隣り合っていれば、同じ色どうしでもつなげる
///  - [minPathLength] 枚以上でチェイン成立
///  - パス上のマナのマスは必ず消える
///  - 敵には「威力 − 守り + 1」のダメージが通る。守り以下なら 0 で弾かれる。
///    体力を削り切れば討ち取れ、残れば傷ついたままその場に残る
///  - 何ひとつ起きないチェイン（誰にも傷がつかない）は不成立
///  - 消えた跡は重力で詰め、上から新しいマナが降ってくる
///  - 敵は補充されない。ステージ開始時に置かれたものが全て
class Board {
  Board({
    this.rows = 8,
    this.cols = 6,
    List<Phase>? phases,
    List<int>? weights,
    Random? rng,
  }) : phases = List.unmodifiable(
         phases == null || phases.isEmpty
             ? const [Phase.red, Phase.blue]
             : phases,
       ),
       _weights = List.unmodifiable(
         _fitWeights(phases, weights),
       ),
       _rng = rng ?? Random() {
    grid = List.generate(rows, (_) => List<Tile?>.filled(cols, null));
  }

  /// 補充の比率。渡されなければ均等。長さが合わなければ均等に倒す。
  static List<int> _fitWeights(List<Phase>? phases, List<int>? weights) {
    final n = phases == null || phases.isEmpty ? 2 : phases.length;
    if (weights == null || weights.length != n) {
      return List<int>.filled(n, 1);
    }
    // 0 や負の重みが混じると、その相が一切降ってこなくなって詰む。
    return [for (final w in weights) w < 1 ? 1 : w];
  }

  /// チェイン成立に必要な最低枚数。
  static const int minPathLength = 3;

  /// 敵の守りに書ける数字の範囲。
  ///
  /// 下限は [minPathLength] と同じで「成立すれば必ず傷がつく」入門用。
  /// 上限 8 は、シミュレーションで成立率が保てる限界。9 以上にすると
  /// 盤面によっては通るパスが無く、運任せになる。
  static const int minWard = minPathLength;
  static const int maxWard = 8;

  /// 守り [ward] の敵の攻撃力。**盤面には出さない隠し値。**
  ///
  /// 守り 3〜5 が 1、6〜8 が 2。守りは鎖の長さを決める値なのでマスに出すが、
  /// 攻撃力まで並べると狭いマスが読めなくなる。「厚い敵ほど痛い」という
  /// 対応さえ付いていれば、数字を見せなくても手触りで伝わる。
  ///
  /// ここを上げるときは名簿の体力（[Mage.hp]）と一緒に動かすこと。毎ターン
  /// 全員ぶん削られるので、階層あたりの痛手は「攻撃力の合計 × 使った手数」で
  /// 効いてくる（README 第9段階）。
  static int attackFor(int ward) => 1 + (ward - minWard) ~/ 3;

  final int rows;
  final int cols;

  /// この盤面に出る相。編成から決まる。
  final List<Phase> phases;

  /// 補充の比率。編成の人数比を入れる。偏らせるほど、少ない側の相が
  /// 「強い鎖を編むのに要る希少な資源」になる。相が2つ・2:1 のとき、
  /// 偶奇だった頃の 65:35 とほぼ同じ手触りになる。
  final List<int> _weights;

  /// **いま延焼している相。**
  ///
  /// 色の決まりが無くなったので（README 第22段階）、**いまは立てても盤面の
  /// 振る舞いは変わらない**。烈火の「延焼」（`Spread`）がここを立て、鎖を
  /// 1本編んだところで `GameController` が下ろす、という配線だけが残して
  /// ある。決まりを入れ直すときに、緩める先としてここを読むこと。
  Phase? spreadPhase;

  final Random _rng;
  late final List<List<Tile?>> grid;
  int _nextId = 0;

  Tile? tileAt(Cell c) {
    if (c.row < 0 || c.row >= rows || c.col < 0 || c.col >= cols) return null;
    return grid[c.row][c.col];
  }

  /// マナを1枚。[even] を立てると比率を無視して均等に引く。
  Tile _spawn({bool even = false}) {
    final weights = even ? List<int>.filled(phases.length, 1) : _weights;
    var total = 0;
    for (final w in weights) {
      total += w;
    }
    var roll = _rng.nextInt(total);
    for (var i = 0; i < phases.length; i++) {
      roll -= weights[i];
      if (roll < 0) return Tile(id: _nextId++, phase: phases[i]);
    }
    return Tile(id: _nextId++, phase: phases.last);
  }

  /// ステージを1つ作る。マナを敷いてから敵を置く。
  ///
  /// [foeCount] 体の敵に、[minWard]〜[wardCap] の範囲で守りを割り振り、
  /// 体力を 1〜[maxFoeHp] から選ぶ。
  /// 階層を組む。[foes] を渡すとその通りに置き、渡さなければ
  /// [foeCount] / [wardCap] / [maxFoeHp] から適当に散らす。
  ///
  /// ダンジョンは階層を手で書くので [foes] を使う。散らす方は、決め打ちの
  /// ダンジョンを持たない遊び方（無限に潜る形）を残すために置いてある。
  void buildStage({
    int foeCount = 1,
    int wardCap = maxWard,
    int maxFoeHp = 1,
    List<FoeSpec>? foes,
  }) {
    _fillInitial();
    if (foes != null) {
      _placeGiven(foes);
    } else {
      _placeFoes(foeCount, wardCap, maxFoeHp);
    }
  }

  /// 指定された敵をそのまま置く。守りも体力も曲げない。
  /// 置く場所だけは毎回変える。同じ階層でも盤面は編み直されるため。
  void _placeGiven(List<FoeSpec> foes) {
    final cells = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        cells.add(Cell(r, c));
      }
    }
    cells.shuffle(_rng);
    for (var i = 0; i < foes.length && i < cells.length; i++) {
      final cell = cells[i];
      final base = grid[cell.row][cell.col]!;
      final spec = foes[i];
      grid[cell.row][cell.col] = Tile(
        id: base.id,
        phase: base.phase,
        ward: spec.ward.clamp(minWard, maxWard),
        hp: spec.hp < 1 ? 1 : spec.hp,
        atk: spec.atk,
      );
    }
  }

  /// 初期盤面は相を均等に敷く（開幕から詰んでいると理不尽なため）。
  /// 偏らせるのは補充のときだけ。
  void _fillInitial() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = _spawn(even: true);
      }
    }
    var guard = 0;
    while (!hasAnyChain() && guard++ < 50) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          grid[r][c] = _spawn(even: true);
        }
      }
    }
  }

  void _placeFoes(int count, int wardCap, int maxFoeHp) {
    final cells = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        cells.add(Cell(r, c));
      }
    }
    cells.shuffle(_rng);
    final cap = wardCap.clamp(minWard, maxWard);
    final hpCap = maxFoeHp < 1 ? 1 : maxFoeHp;
    for (final cell in cells.take(count)) {
      final base = grid[cell.row][cell.col]!;
      final ward = minWard + _rng.nextInt(cap - minWard + 1);
      // 守りが厚い敵ほど体力は薄く。両方が重なると、1本で討てないうえに
      // 削るのにも何ターンもかかる、ただ長引くだけの敵になる。
      final room = ward >= maxWard - 1 ? 1 : hpCap;
      final hp = 1 + _rng.nextInt(room);
      grid[cell.row][cell.col] =
          Tile(id: base.id, phase: base.phase, ward: ward, hp: hp);
    }
  }

  Iterable<Cell> neighborsOf(Cell c) sync* {
    if (c.row > 0) yield Cell(c.row - 1, c.col);
    if (c.row < rows - 1) yield Cell(c.row + 1, c.col);
    if (c.col > 0) yield Cell(c.row, c.col - 1);
    if (c.col < cols - 1) yield Cell(c.row, c.col + 1);
  }

  bool _adjacent(Cell a, Cell b) =>
      (a.row - b.row).abs() + (a.col - b.col).abs() == 1;

  /// [path] の末尾に [to] を継げるか。**隣り合っていて、マスがあればよい。**
  ///
  /// 色は見ない。同じ色どうしでもつなげる（README 第22段階）。
  bool canExtendPath(List<Cell> path, Cell to) {
    if (path.isEmpty) return false;
    if (!_adjacent(path.last, to)) return false;
    return tileAt(to) != null;
  }

  /// 威力 [power] の鎖が [cell] に通すダメージ。マナのマスは 0。
  int damageAt(Cell cell, int power) {
    final t = tileAt(cell);
    if (t == null || !t.isFoe) return 0;
    return t.damageFrom(power);
  }

  /// 威力 [power] の鎖で [cell] のブロックが盤面から消えるか。
  /// マナのマスは必ず消える。敵は体力を削り切ったときだけ。
  bool fells(Cell cell, int power) {
    final t = tileAt(cell);
    if (t == null) return false;
    if (!t.isFoe) return true;
    return t.damageFrom(power) >= t.hp;
  }

  /// パスを打ったとき、どのマスが消えるか。[path] と同じ並びで返す。
  /// [power] を省くと枚数そのものを威力として扱う。
  List<bool> clearMaskFor(List<Cell> path, {int? power}) {
    final p = power ?? path.length;
    return [for (final c in path) fells(c, p)];
  }

  /// パスとしての正しさ。**長さと隣接と二度通りだけ**を見る。
  ///
  /// 色は見ない（[canExtendPath]）。以前はここで「2色の交互」か
  /// 「N 色の巡回」かを並び全体について確かめていた（README 第7・第8段階）。
  bool isConnected(List<Cell> path) {
    if (path.length < minPathLength) return false;
    final seen = <Cell>{};
    for (final c in path) {
      if (tileAt(c) == null) return false;
      if (!seen.add(c)) return false;
    }
    for (var i = 1; i < path.length; i++) {
      if (!_adjacent(path[i - 1], path[i])) return false;
    }
    return true;
  }

  /// チェインとして成立するか。
  ///
  /// 何ひとつ起きないチェインは成立させない。マナのマスが1枚でも混じって
  /// いれば必ず何か消えるので、これに当たるのは「全部が弾かれる敵」という
  /// 稀な場合だけ。手数を丸損させないための例外。
  bool isValidPath(List<Cell> path, {int? power}) {
    if (!isConnected(path)) return false;
    final p = power ?? path.length;
    for (final c in path) {
      final t = tileAt(c)!;
      if (!t.isFoe || t.damageFrom(p) > 0) return true;
    }
    return false;
  }

  /// 威力 [power]、敵を [felled] 体討った鎖の得点。
  static int scoreFor(int power, int felled) {
    final multiplier = power - minPathLength + 1;
    return power * multiplier * 10 + felled * 100;
  }

  /// パスを適用する。重力と補充は呼び出し側で行う。
  /// [power] を省くと枚数そのものを威力として扱う。
  ClearResult applyPath(List<Cell> path, {int? power}) {
    final p = power ?? path.length;
    assert(isValidPath(path, power: p));
    final wards = <int?>[];
    final damages = <int>[];
    final tilePhases = <Phase>[];
    final cleared = <bool>[];
    var felled = 0;
    for (final cell in path) {
      final t = tileAt(cell)!;
      wards.add(t.ward);
      tilePhases.add(t.phase);
      if (!t.isFoe) {
        damages.add(0);
        cleared.add(true);
        continue;
      }
      final d = t.damageFrom(p);
      damages.add(d);
      final down = d >= t.hp;
      cleared.add(down);
      if (down) felled++;
    }
    for (var i = 0; i < path.length; i++) {
      final cell = path[i];
      if (cleared[i]) {
        grid[cell.row][cell.col] = null;
      } else if (damages[i] > 0) {
        grid[cell.row][cell.col] = grid[cell.row][cell.col]!.hurt(damages[i]);
      }
    }
    return ClearResult(
      cells: List.unmodifiable(path),
      cleared: List.unmodifiable(cleared),
      wards: List.unmodifiable(wards),
      damages: List.unmodifiable(damages),
      phases: List.unmodifiable(tilePhases),
      power: p,
      felled: felled,
      gained: scoreFor(p, felled),
      endCell: path.last,
    );
  }

  /// 盤面に残っている敵全員に [damage] を通す。守りは無視する。
  /// 鎖の外からの追撃用。討ち取った敵を返す。
  List<FoeFall> strike(int damage) {
    final fallen = <FoeFall>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t == null || !t.isFoe) continue;
        if (damage >= t.hp) {
          grid[r][c] = null;
          fallen.add(
            FoeFall(cell: Cell(r, c), ward: t.ward!, phase: t.phase),
          );
        } else {
          grid[r][c] = t.hurt(damage);
        }
      }
    }
    return fallen;
  }

  void applyGravity() {
    for (var c = 0; c < cols; c++) {
      var write = rows - 1;
      for (var r = rows - 1; r >= 0; r--) {
        final t = grid[r][c];
        if (t == null) continue;
        grid[r][c] = null;
        grid[write][c] = t;
        write--;
      }
    }
  }

  /// 空きマスを上から補充する。戻り値は新しく生まれたブロックの id 集合。
  /// 補充されるのはマナのマスだけ。敵は降ってこない。
  Set<int> refill() {
    final added = <int>{};
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        if (grid[r][c] == null) {
          final t = _spawn();
          grid[r][c] = t;
          added.add(t.id);
        }
      }
    }
    return added;
  }

  /// 盤面に残っている敵。
  List<Cell> get foeCells {
    final list = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (grid[r][c]?.isFoe ?? false) list.add(Cell(r, c));
      }
    }
    return list;
  }

  int get remainingFoes => foeCells.length;

  /// 残っている敵の体力の合計。この階層にあと何手かかるかの目安。
  int get totalFoeHp {
    var n = 0;
    for (final cell in foeCells) {
      n += tileAt(cell)!.hp;
    }
    return n;
  }

  /// 盤面に残っている敵の守り。決着画面に姿を並べるのに使う。
  List<int> get foeWards => [for (final c in foeCells) tileAt(c)!.ward!];

  /// 討ち漏らしたまま階層を落としたときに受ける痛手。
  /// 守りが厚い敵を残すほど高くつく。
  int get foeThreat {
    var n = 0;
    for (final cell in foeCells) {
      n += tileAt(cell)!.ward!;
    }
    return n;
  }

  /// 残っている敵が毎ターン浴びせてくるダメージの合計。
  /// **討ち取れば減る。** 早く討つほど後が楽になる。
  int get foeAttack {
    var n = 0;
    for (final cell in foeCells) {
      n += tileAt(cell)!.atk;
    }
    return n;
  }

  /// [through] を通る、長さ [need] 以上の成立パスを1本返す。無ければ空。
  ///
  /// [through] を起点に、後ろへ伸ばしてから前へ伸ばす。
  ///
  /// **色の決まりが無くなってから、枝刈りが効かなくなった**（README 第22
  /// 段階）。どの隣へも伸ばせるので、長い [need] を頼むほど深く潜る。
  /// 呼ぶ側が要る長さだけを頼むこと。
  List<Cell> findPathThrough(Cell through, int need) {
    if (tileAt(through) == null) return const [];
    final seen = <Cell>{through};
    final path = <Cell>[through];

    // 前（先頭側）へ伸ばす。ここまで来たら長さが足りているかを見る。
    bool growFront() {
      if (path.length >= need) return true;
      for (final n in neighborsOf(path.first)) {
        if (seen.contains(n) || tileAt(n) == null) continue;
        seen.add(n);
        path.insert(0, n);
        if (growFront()) return true;
        path.removeAt(0);
        seen.remove(n);
      }
      return false;
    }

    // 後ろ（末尾側）へ伸ばす。伸ばしきったところで前側に切り替える。
    bool growBack() {
      if (growFront()) return true;
      for (final n in neighborsOf(path.last)) {
        if (seen.contains(n) || tileAt(n) == null) continue;
        seen.add(n);
        path.add(n);
        if (growBack()) return true;
        path.removeLast();
        seen.remove(n);
      }
      return false;
    }

    if (!growBack()) return const [];
    final found = List<Cell>.of(path);
    return isValidPath(found) ? found : const [];
  }

  /// [cell] の敵を、いまの盤面で1本の鎖で討ち取れるか。
  ///
  /// 魔導士の威力補正は数に入れない。入れると「補正が乗る鎖が組めるか」まで
  /// 探すことになり、探索が跳ね上がる。見落とす側に倒しても、実際より
  /// 厳しく答えるだけなので嘘にはならない。
  bool canFell(Cell cell) {
    final t = tileAt(cell);
    if (t == null || !t.isFoe) return false;
    return findPathThrough(cell, t.powerToFell).isNotEmpty;
  }

  /// [phase] のマスだけで [minPathLength] 枚つながるところがあるか。
  ///
  /// **延焼が何も変えない盤面を見分けるのに使う。** その相が飛び飛びにしか
  /// 無ければ、決まりを緩めても編める鎖は1本も増えない――そこで回数を
  /// 減らさないように、立てる前に訊く。
  ///
  /// 繋がっている塊の大きさで見る。同じ相が3マス以上ひと繋がりなら、その中に
  /// 3枚の道が必ずある（木にして端から辿ればよい）。
  bool hasSamePhaseRun(Phase phase) {
    final seen = <Cell>{};
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final start = Cell(r, c);
        if (seen.contains(start) || tileAt(start)?.phase != phase) continue;
        var size = 0;
        final stack = <Cell>[start];
        seen.add(start);
        while (stack.isNotEmpty) {
          final cell = stack.removeLast();
          size++;
          if (size >= minPathLength) return true;
          for (final n in neighborsOf(cell)) {
            if (seen.contains(n) || tileAt(n)?.phase != phase) continue;
            seen.add(n);
            stack.add(n);
          }
        }
      }
    }
    return false;
  }

  /// 成立する手が1つでも残っているか。無ければ手詰まり。
  bool hasAnyChain() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (findPathThrough(Cell(r, c), minPathLength).isNotEmpty) return true;
      }
    }
    return false;
  }

  /// ヒント。討ち取れる敵があればその手を、無ければ傷をつけられる手を、
  /// それも無ければ適当な成立手を返す。
  List<Cell> findHint() {
    final foes = foeCells;
    for (final cell in foes) {
      final p = findPathThrough(cell, tileAt(cell)!.powerToFell);
      if (p.isNotEmpty) return p;
    }
    for (final cell in foes) {
      final p = findPathThrough(cell, tileAt(cell)!.powerToHurt);
      if (p.isNotEmpty) return p;
    }
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p = findPathThrough(Cell(r, c), minPathLength);
        if (p.isNotEmpty) return p;
      }
    }
    return const [];
  }

  /// いまの盤面で、**敵にいちばん深く届く道**を1本。無ければ空。
  ///
  /// 風の「先読み」（`Foresee`）が呼ぶ。数えるのは**通した痛手の合計**で、
  /// 敵1体ぶんは残り体力で頭打ちにする（討ち取ったあとの余りは捨てる）。
  /// 同じ痛手なら威力の高い（＝長い）ほうを採る。点も伸びるし、枚数で
  /// 応えるスキル（風・雷）も乗りやすい。
  ///
  /// **敵のマスを起点にして、前後へ伸ばす。** 敵を1体も通らない道は必ず 0
  /// 点なので、盤面ぜんぶから始める必要がない。階層に居る敵は数体なので、
  /// 探索はその数倍で済む。
  ///
  /// [powerOf] は道から威力を出す関数。**盤面は一党を読まない**ので、
  /// 魔導士の補正は呼び出し側から渡してもらう（`GameController`）。
  ///
  /// [maxNodes] は保険で、**敵1体あたり**の枝の数。市松の盤面はどの隣とも
  /// 継げるので枝が太く、深さだけで抑えると膨らむことがある。1体ずつに
  /// 配るのは、1体目で使い切ると2体目以降が探されないため。**打ち切っても
  /// 嘘にはならない**――そこまでで見つけた中の最善を返すだけで、実際より
  /// 控えめに答えることしかない。
  List<Cell> bestStrike({
    required int Function(List<Cell> path) powerOf,
    int maxLength = 12,
    int maxNodes = 30000,
  }) {
    var best = const <Cell>[];
    var bestDamage = 0;
    var bestPower = 0;
    var nodes = 0;

    void score(List<Cell> path) {
      if (path.length < minPathLength) return;
      final power = powerOf(path);
      var damage = 0;
      for (final c in path) {
        final t = tileAt(c)!;
        if (!t.isFoe) continue;
        final d = t.damageFrom(power);
        damage += d < t.hp ? d : t.hp;
      }
      if (damage <= 0) return;
      if (damage > bestDamage || (damage == bestDamage && power > bestPower)) {
        bestDamage = damage;
        bestPower = power;
        best = List<Cell>.of(path);
      }
    }

    for (final anchor in foeCells) {
      nodes = 0;
      final seen = <Cell>{anchor};
      final path = <Cell>[anchor];

      // 先頭側だけを伸ばす。末尾の形ひとつにつき、前の伸ばし方を全部見る。
      void growFront() {
        score(path);
        if (path.length >= maxLength || nodes >= maxNodes) return;
        for (final n in neighborsOf(path.first)) {
          if (seen.contains(n) || tileAt(n) == null) continue;
          nodes++;
          seen.add(n);
          path.insert(0, n);
          growFront();
          path.removeAt(0);
          seen.remove(n);
        }
      }

      void growBack() {
        growFront();
        if (path.length >= maxLength || nodes >= maxNodes) return;
        for (final n in neighborsOf(path.last)) {
          if (seen.contains(n) || tileAt(n) == null) continue;
          nodes++;
          seen.add(n);
          path.add(n);
          growBack();
          path.removeLast();
          seen.remove(n);
        }
      }

      growBack();
    }
    return best;
  }

  /// 盤面に残っている [phase] のマスの数。相どうしの比率を見せるのに使う。
  /// 少ない相が尽きると、長い鎖が編めなくなる。
  int countOf(Phase phase) => _count((t) => t.phase == phase);

  /// 盤面に残っているマスの数を相ごとに。[phases] と同じ並びで返す。
  List<int> get phaseCounts => [for (final p in phases) countOf(p)];

  int _count(bool Function(Tile) test) {
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final t = grid[r][c];
        if (t != null && test(t)) n++;
      }
    }
    return n;
  }

  int get tileCount => rows * cols;
}
