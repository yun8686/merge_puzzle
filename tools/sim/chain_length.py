"""継ぎ方の決まりの難易度を測る。

**難易度＝ランダムに置いた敵1体のマスを通る最長パスの平均。**

敵を討つには敵マスを通る鎖が要り、その鎖の威力は枚数で決まる。だから
「その敵にどれだけ通せるか」がそのまま難易度になる。

盤面は通常どおり 8行×6列＝48マス（`Board(rows: 8, cols: 6)`）。隣接は上下左右
だけ（`Board._adjacent` は Manhattan 距離 1）。相は均等に敷く（階層の初期盤面を
作る `_fillInitial` が `_spawn(even: true)` を使うため）。

12 枚で打ち切る。守りの上限は 8 で、威力 9 あればどの敵も討てる。12 枚まで
届けば討ち切れるので、それ以上の長さはゲームの上で差にならない。打ち切りを
上げると長い鎖を編める決まりほど値が伸び続け、比較にならなくなる。

    python3 tools/sim/chain_length.py          # 既定（12枚で打ち切り）
    python3 tools/sim/chain_length.py 16       # 打ち切りを変える

## 測り方を間違えた話

最初は「継げる隣マスの割合」で測った。これは当てにならない。3色の盤面では
巡回でも2色の交互でも次に置ける相は1種類（盤面の 1/3）で、局所的には同じ
だから差が出ない。ところが**鎖ごとに良い方を選べること自体が長さを押し上げる**
ので、最長パスで測ると差が出る。README 第8段階に経緯がある。
"""
import random
import statistics
import sys
from collections import deque

ROWS, COLS = 8, 6
BOARDS = 2000
SEEDS = [1, 2, 3, 4, 5]
BUDGET = 300000  # 1マスあたりの展開上限。深追いしすぎないための保険


def neighbors(r, c):
    if r > 0:
        yield (r - 1, c)
    if r < ROWS - 1:
        yield (r + 1, c)
    if c > 0:
        yield (r, c - 1)
    if c < COLS - 1:
        yield (r, c + 1)


class Chain:
    """相の並びと、決まりを満たしているかの状態。前後どちらにも伸ばせる。

    判定は差分で回す。並び全体を毎回組み直すと DFS が遅すぎる。
    `verify()` が、並び全体で判定する実装と一致することを確かめている。

    kind:
      'old'    巡回のみ … 直前 N-1 枚と違う（第7段階）
      'user'   2色の交互 or 巡回 … いまの決まり（第8段階）
      'new'    どの N+1 枚にも N 色 … 一度入れて戻した案
      'loose'  隣と違えばよい … 素直な一般化
      'spread' いまの決まり or 1色だけ … 烈火の延焼（第17段階）
      'free'   色を見ない … **いまの決まり**（第22段階）
    """

    def __init__(self, first, N, kind):
        self.N, self.kind, self.w = N, kind, max(1, N - 1)
        self.seq = deque([first])
        self.count = [0] * N
        self.count[first] = 1
        self.distinct = 1
        self.cycle_ok = True  # 巡回の決まりを全位置で満たしているか
        self.doubled = False  # 同じ相が隣り合ったことがあるか（延焼だけ）

    def _side(self, k, at_front):
        return list(self.seq)[:k] if at_front else list(self.seq)[-k:]

    def can_push(self, p, at_front):
        # いまの決まり：色を見ない。隣り合っていればつながる。
        if self.kind == 'free':
            return True
        # 延焼：1色だけで編んでいるあいだは、同じ相をいくらでも続けられる。
        if self.kind == 'spread' and self.distinct == 1 and p == self.seq[0]:
            return True
        # 一度でも同じ相を隣り合わせたら、混ぜた並びは元の決まりを満たせない。
        if self.doubled:
            return False
        if p == (self.seq[0] if at_front else self.seq[-1]):
            return False
        if self.kind == 'loose':
            return True
        if self.kind == 'new':
            side = self._side(self.N, at_front)
            return len(side) < self.N or len(set(side + [p])) >= self.N
        new_cycle = self.cycle_ok and p not in self._side(self.w, at_front)
        if self.kind == 'old':
            return new_cycle
        # 'user' と 'spread'：2色だけなら交互で通る。3色目に触れたら巡回が要る。
        new_distinct = self.distinct + (1 if self.count[p] == 0 else 0)
        return new_distinct <= 2 or new_cycle

    def push(self, p, at_front):
        saved = (self.cycle_ok, self.distinct, self.doubled)
        self.doubled = self.doubled or p == (
            self.seq[0] if at_front else self.seq[-1]
        )
        self.cycle_ok = self.cycle_ok and p not in self._side(self.w, at_front)
        if self.count[p] == 0:
            self.distinct += 1
        self.count[p] += 1
        self.seq.appendleft(p) if at_front else self.seq.append(p)
        return saved

    def pop(self, at_front, saved):
        p = self.seq.popleft() if at_front else self.seq.pop()
        self.count[p] -= 1
        self.cycle_ok, self.distinct, self.doubled = saved


def longest_through(g, cell, N, kind, cap):
    """[cell] を通る最長パス。前後どちらにも伸ばす。"""
    best = 1
    budget = [BUDGET]
    seen = {cell}
    path = deque([cell])
    ch = Chain(g[cell], N, kind)

    def dfs():
        nonlocal best
        if len(path) > best:
            best = len(path)
            if best >= cap:
                return True
        budget[0] -= 1
        if budget[0] <= 0:
            return True
        for at_front in (False, True):
            end = path[0] if at_front else path[-1]
            for n in neighbors(*end):
                if n in seen or not ch.can_push(g[n], at_front):
                    continue
                saved = ch.push(g[n], at_front)
                seen.add(n)
                path.appendleft(n) if at_front else path.append(n)
                stop = dfs()
                path.popleft() if at_front else path.pop()
                seen.discard(n)
                ch.pop(at_front, saved)
                if stop:
                    return True
        return False

    dfs()
    return best


def one(N, kind, seed, cap):
    """1回ぶん。盤面を [BOARDS] 面作り、それぞれ敵1体ぶんを測る。"""
    rng = random.Random(seed)
    vals = []
    for _ in range(BOARDS):
        g = {(r, c): rng.randrange(N) for r in range(ROWS) for c in range(COLS)}
        cell = (rng.randrange(ROWS), rng.randrange(COLS))
        vals.append(longest_through(g, cell, N, kind, cap))
    return vals


def verify():
    """差分更新が、並び全体で判定する実装と一致するか総当たりで確かめる。"""

    def full_ok(seq, N, kind):
        w = max(1, N - 1)
        if kind == 'free':
            return True
        if kind == 'spread' and len(set(seq)) == 1:
            return True
        for i in range(1, len(seq)):
            if seq[i] == seq[i - 1]:
                return False
        if kind == 'loose':
            return True
        if kind == 'new':
            return all(
                len(set(seq[i - N:i + 1])) >= N for i in range(N, len(seq))
            )
        cyc = all(
            seq[i] not in seq[max(0, i - w):i] for i in range(1, len(seq))
        )
        return cyc if kind == 'old' else (len(set(seq)) <= 2 or cyc)


    rng = random.Random(7)
    bad = 0
    for kind in ('old', 'user', 'new', 'loose', 'spread', 'free'):
        for N in (2, 3):
            for _ in range(4000):
                first = rng.randrange(N)
                ch = Chain(first, N, kind)
                seq = [first]
                for _ in range(rng.randrange(1, 10)):
                    p = rng.randrange(N)
                    at_front = rng.random() < 0.5
                    nxt = ([p] + seq) if at_front else (seq + [p])
                    if full_ok(nxt, N, kind) != ch.can_push(p, at_front):
                        bad += 1
                        break
                    if ch.can_push(p, at_front):
                        ch.push(p, at_front)
                        seq = nxt
    return bad


CASES = [
    ('2相・色を見ない（いまの決まり）', 2, 'free'),
    ('3相・色を見ない（いまの決まり）', 3, 'free'),
    ('2相・交互（第6段階まで）', 2, 'old'),
    ('3相・巡回のみ（第7段階）', 3, 'old'),
    ('3相・2色の交互 or 巡回（第8〜21段階）', 3, 'user'),
    ('3相・どの4枚にも3色', 3, 'new'),
    ('3相・隣と違えばよい', 3, 'loose'),
    ('3相・いまの決まり or 1色だけ（延焼の1本）', 3, 'spread'),
    ('2相・いまの決まり or 1色だけ（延焼の1本）', 2, 'spread'),
]

if __name__ == '__main__':
    cap = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    bad = verify()
    print(f'差分更新の検算: 食い違い {bad} 件\n')
    print(f'通常盤面 {ROWS}x{COLS} = {ROWS * COLS} マス。ランダムなマスに敵を'
          f'1体置き、その敵マスを通る最長パスを測る。')
    print(f'{BOARDS} 面で1回ぶん。種を変えて {len(SEEDS)} 回繰り返す。'
          f'{cap} 枚で打ち切り。\n')
    for label, N, kind in CASES:
        runs, allv = [], []
        for seed in SEEDS:
            v = one(N, kind, seed, cap)
            runs.append(sum(v) / len(v))
            allv.extend(v)
        allv.sort()
        pct = lambda n: sum(1 for x in allv if x >= n) / len(allv)  # noqa: E731
        print(f'{label:30} 平均 {sum(runs) / len(runs):5.2f}'
              f' ± {statistics.stdev(runs):4.2f}   '
              f'中央値 {allv[len(allv) // 2]:2}  '
              f'3枚以上 {pct(3):4.0%}  5枚以上 {pct(5):4.0%}  '
              f'8枚以上 {pct(8):4.0%}', flush=True)
