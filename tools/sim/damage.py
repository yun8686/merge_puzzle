"""1本の潜りで浴びる痛手を見積もる。

**痛手＝生きている敵の攻撃力の合計 × その階層に使った手数。** 敵は毎ターン
殴ってくるので、階層あたりの痛手は「どれだけ手間取ったか」で決まる。討ち取れば
その敵のぶんは止まるので、**早く討つほど安い**。

階層の中身は `lib/game/dungeon.dart` を、名簿は `lib/game/roster.dart` をそのまま
読む（手で書き写すと、いじったときに黙って古くなる）。攻撃力も守りから同じ式で出す
（`Board.attackFor`：守り3〜5が1、6〜8が2）。

**手数に制限は無い。** 上限が無いぶん、浴びる痛手は「どう打つか」でしか
決まらないので、2通りで挟む。

- **ゆるい**（手探りで打つ人）… 体力の合計 × 3 + 2 の6割を使う。この
  ×3+2 は手数の制限があった頃の上限で、シミュレーションで「敵の周辺を
  崩して周囲を入れ替える打ち方」のクリア率が 78〜93% になる値として
  測ったもの。制限をやめたので**上限ではなく見立て**になったが、手探りで
  打つ人の手数としてはそのまま使える
- **きつい**（最短）… 体力の合計ぶんの鎖 ＋ 立て直しの2手。1本で1点ずつ削る
  勘定なので、これより速くは討てない

どちらも「敵は順に落ちるので、平均して攻撃力の半分が生きている」とみなす。
制限が無いので**ゆるい側は天井ではない**。手間取ればいくらでも上に行く
――その代わり、そこで払うのは体力だけになった。

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


def loose_moves(total_hp: int) -> int:
    """手探りで打つ人の手数の見立て。

    手数の制限があった頃の上限の式（体力の合計 × 3 + 2）をそのまま使う。
    ゲームの側からは消えたので、いまはこの見積もりの中にしか無い。
    """
    return total_hp * 3 + 2


def parse_foe(args: str) -> tuple[int, int, int]:
    """`FoeSpec(6, hp: 3)` の中身から (守り, 体力, 攻撃力) を作る。"""
    ward = int(re.match(r"\s*(\d+)", args).group(1))
    hp = int(m.group(1)) if (m := re.search(r"hp:\s*(\d+)", args)) else 1
    atk = int(m.group(1)) if (m := re.search(r"atk:\s*(\d+)", args)) else attack_for(ward)
    return ward, hp, atk


def parse_dungeons(source: str):
    """`dungeon.dart` から（名前, 階層）を読む。階層は敵の並び。"""
    out = []
    for chunk in re.split(r"static const \w+ = Dungeon\(", source)[1:]:
        chunk = chunk.split("\n  );")[0]
        name = re.search(r"name: '([^']*)'", chunk).group(1)
        floors = []
        for spec in re.finditer(r"FloorSpec\(\s*(\[.*?\])\s*,?\s*\)", chunk, re.S):
            floors.append([parse_foe(a) for a in re.findall(r"FoeSpec\(([^)]*)\)", spec.group(1))])
        out.append((name, floors))
    return out


def parse_mages(source: str) -> list[tuple[str, int]]:
    """`roster.dart` から（魔導士の名前, 体力）を読む。

    一党の体力は**連れていく顔ぶれの合計**なので、初期体力という1つの数字は
    もう無い。名簿を読んで、組み方ごとの厚さを出す。
    """
    squire = int(re.search(r"squireHp = (\d+)", source).group(1))
    out = []
    for m in re.finditer(
        r"Mage\._\(\s*kind:\s*MageKind\.\w+,"
        r"\s*phase:\s*Phase\.\w+,"
        r"\s*name:\s*'([^']*)',"
        r"\s*hp:\s*(\w+)",
        source,
    ):
        hp = squire if m.group(2) == "squireHp" else int(m.group(2))
        out.append((m.group(1), hp))
    return out


def main() -> int:
    dungeons = parse_dungeons((ROOT / "lib/game/dungeon.dart").read_text())
    mages = parse_mages((ROOT / "lib/game/roster.dart").read_text())

    print("名簿の体力")
    for name, hp in mages:
        print(f"   {name} {hp}")
    hps = sorted((hp for _, hp in mages), reverse=True)
    print("\n一党の体力＝連れていく顔ぶれの合計")
    print(f"   始まりの2人（従者2人） {mages[0][1] + mages[1][1]}")
    print(f"   3人で厚いほう         {sum(hps[:3])}")
    print(f"   3人で薄いほう         {sum(hps[-3:])}")
    print()
    print("| ダンジョン | ゆるい（手探り） | きつい（最短） |")
    print("|---|---|---|")
    totals = []
    for name, floors in dungeons:
        loose = tight = 0.0
        rows = []
        for foes in floors:
            total_hp = sum(f[1] for f in foes)
            guess = loose_moves(total_hp)
            half = sum(f[2] for f in foes) / 2
            a = round(guess * 0.6) * half
            b = (total_hp + 2) * half
            loose += a
            tight += b
            rows.append((total_hp, guess, half * 2, a, b))
        totals.append((name, loose, tight, rows))
        print(f"| {name} | {loose:.0f} | {tight:.0f} |")

    print()
    for name, loose, tight, rows in totals:
        print(f"== {name}  ゆるい {loose:.0f} / きつい {tight:.0f}")
        for i, (total_hp, guess, full, a, b) in enumerate(rows, 1):
            print(
                f"   B{i}F 体力計 {total_hp}  手数の見立て {guess}"
                f"  攻撃力の合計 {full:.0f}  → {a:.0f} / {b:.0f}"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
