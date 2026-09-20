"""1本の潜りで浴びる痛手を見積もる。

**痛手＝生きている敵の攻撃力の合計 × その階層に使った手数。** 敵は毎ターン
殴ってくるので、階層あたりの痛手は「どれだけ手間取ったか」で決まる。討ち取れば
その敵のぶんは止まるので、**早く討つほど安い**。

階層の中身は `lib/game/dungeon.dart` をそのまま読む（手で書き写すと、階層を
いじったときに黙って古くなる）。攻撃力も守りから同じ式で出す
（`Board.attackFor`：守り3〜5が1、6〜8が2）。

手数は2通りで見積もる。**実際はこの間に収まる。**

- **ゆるい**（README 第9段階の見立て）… その階層の手数（`Board.movesFor` ＝
  体力の合計 × 3 + 2）の6割を使う。手探りで打つ人の側
- **きつい**（最短）… 体力の合計ぶんの鎖 ＋ 立て直しの2手。1本で1点ずつ削る
  勘定なので、これより速くは討てない

どちらも「敵は順に落ちるので、平均して攻撃力の半分が生きている」とみなす。

    python3 tools/sim/damage.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIN_WARD = 3


def attack_for(ward: int) -> int:
    """`Board.attackFor` と同じ式。守り3〜5が1、6〜8が2。"""
    return 1 + (ward - MIN_WARD) // 3


def moves_for(total_hp: int) -> int:
    """`Board.movesFor` と同じ式。"""
    return total_hp * 3 + 2


def parse_foe(args: str) -> tuple[int, int, int]:
    """`FoeSpec(6, hp: 3)` の中身から (守り, 体力, 攻撃力) を作る。"""
    ward = int(re.match(r"\s*(\d+)", args).group(1))
    hp = int(m.group(1)) if (m := re.search(r"hp:\s*(\d+)", args)) else 1
    atk = int(m.group(1)) if (m := re.search(r"atk:\s*(\d+)", args)) else attack_for(ward)
    return ward, hp, atk


def parse_dungeons(source: str):
    """`dungeon.dart` から（名前, 階層）を読む。階層は敵の並びと手数。"""
    out = []
    for chunk in re.split(r"static const \w+ = Dungeon\(", source)[1:]:
        chunk = chunk.split("\n  );")[0]
        name = re.search(r"name: '([^']*)'", chunk).group(1)
        floors = []
        for spec in re.finditer(r"FloorSpec\(\s*(\[.*?\])\s*(?:,\s*moves:\s*(\d+))?\s*,?\s*\)", chunk, re.S):
            foes = [parse_foe(a) for a in re.findall(r"FoeSpec\(([^)]*)\)", spec.group(1))]
            floors.append((foes, int(spec.group(2)) if spec.group(2) else None))
        out.append((name, floors))
    return out


def parse_mages(source: str) -> list[tuple[str, int]]:
    """`party.dart` から（魔導士の名前, 体力）を読む。

    一党の体力は**連れていく顔ぶれの合計**なので、初期体力という1つの数字は
    もう無い。名簿を読んで、組み方ごとの厚さを出す。
    """
    squire = int(re.search(r"squireHp = (\d+)", source).group(1))
    out = []
    for m in re.finditer(
        r"Mage\._\(\s*MageKind\.\w+,\s*Phase\.\w+,\s*'([^']*)',\s*(\w+)",
        source,
    ):
        hp = squire if m.group(2) == "squireHp" else int(m.group(2))
        out.append((m.group(1), hp))
    return out


def main() -> int:
    dungeons = parse_dungeons((ROOT / "lib/game/dungeon.dart").read_text())
    mages = parse_mages((ROOT / "lib/game/party.dart").read_text())

    print("名簿の体力")
    for name, hp in mages:
        print(f"   {name} {hp}")
    hps = sorted((hp for _, hp in mages), reverse=True)
    print("\n一党の体力＝連れていく顔ぶれの合計")
    print(f"   始まりの2人（従者2人） {mages[0][1] + mages[1][1]}")
    print(f"   3人で厚いほう         {sum(hps[:3])}")
    print(f"   3人で薄いほう         {sum(hps[-3:])}")
    print()
    print("| ダンジョン | ゆるい（手数の6割） | きつい（最短） |")
    print("|---|---|---|")
    totals = []
    for name, floors in dungeons:
        loose = tight = 0.0
        rows = []
        for foes, moves in floors:
            total_hp = sum(f[1] for f in foes)
            limit = moves if moves is not None else moves_for(total_hp)
            half = sum(f[2] for f in foes) / 2
            a = round(limit * 0.6) * half
            b = (total_hp + 2) * half
            loose += a
            tight += b
            rows.append((total_hp, limit, half * 2, a, b))
        totals.append((name, loose, tight, rows))
        print(f"| {name} | {loose:.0f} | {tight:.0f} |")

    print()
    for name, loose, tight, rows in totals:
        print(f"== {name}  ゆるい {loose:.0f} / きつい {tight:.0f}")
        for i, (total_hp, limit, full, a, b) in enumerate(rows, 1):
            print(
                f"   B{i}F 体力計 {total_hp}  手数 {limit}  攻撃力の合計 {full:.0f}"
                f"  → {a:.0f} / {b:.0f}"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
