/// 試すための口。**URL からしか開かない。**
///
/// `?all` を付けて開くと、名簿もダンジョンも全部開いた記録で始まる
/// （`https://yun8686.github.io/merge_puzzle/?all`）。遊ぶ側の URL は
/// 変わらないので、公開ページはそのまま。
///
/// **端末の保存は読まないし書かない。** 置き場所を `MemoryProgressStore` に
/// 差し替えるので、普段遊んでいる記録には触れないし、閉じれば残らない。
/// 記録の側に「全部開く」旗を持たせると、`Progress` が試すための都合を
/// 持ち込むうえ、**一度保存に乗ると外せなくなる**。
///
/// 読むのは `Uri.base` だけ。web では開いているページの URL で、端末の
/// アプリでは file の URL になり問い合わせは空になる――つまり**この口が
/// 開くのは web だけ**で、ストアに出しても付いてこない。
library;

import 'game/dungeon.dart';
import 'game/party.dart';
import 'game/progress.dart';

const String _key = 'all';

/// URL に `?all` が付いているか。
bool get unlockAllRequested => unlockAllIn(Uri.base);

/// [uri] が試用の口を開いているか。[Uri.base] を直に読まないので、
/// ここだけはテストから確かめられる。
bool unlockAllIn(Uri uri) {
  if (uri.queryParameters.containsKey(_key)) return true;
  // flutter web は既定で `#` 付きの URL を使うので、`#/?all` の形も拾う。
  final fragment = uri.fragment;
  if (fragment.isEmpty) return false;
  try {
    return Uri.parse(fragment).queryParameters.containsKey(_key);
  } on FormatException {
    return false;
  }
}

/// 全部開いた記録。
///
/// ダンジョンは**踏破済みにしてある**。「前の1本を踏破すると開く」決まりを
/// 外すのに、記録が持っているのが踏破の id だけだから。踏破の id を数える
/// のはここの仕事で、`Progress` は最後までダンジョンを読まない。
///
/// 稽古は通した印を付けておく。保存しない記録なので、付けないと**開くたびに
/// 拠点へ覆いかぶさる**。稽古そのものを試したいときは `?all` を外すか、
/// 上の帯の札から開けばよい。
Progress unlockedProgress() => Progress(
  owned: {for (final mage in Mage.roster) mage.kind},
  cleared: {for (final dungeon in Dungeons.all) dungeon.id},
  shards: 999,
  taughtTutorial: true,
  taughtPrism: true,
);
