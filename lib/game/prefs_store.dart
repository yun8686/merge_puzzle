import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';

/// 端末の保存領域に記録を置く。web では localStorage に入る。
///
/// 読み書きに失敗しても投げない。**保存が効かないだけで遊べなくなるのは
/// 割に合わない**ので、失敗したときはまっさらな記録として扱い、書き込みは
/// 黙って捨てる。プライベートウィンドウや保存を塞いだブラウザで起きる。
class PrefsProgressStore implements ProgressStore {
  const PrefsProgressStore();

  static const String _key = 'frostfire.progress.v1';

  @override
  Future<Progress> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return Progress.decode(prefs.getString(_key));
    } on Exception {
      return Progress();
    }
  }

  @override
  Future<void> save(Progress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, progress.encode());
    } on Exception {
      // 書けないだけ。次に開いたときに最初からになるが、遊びは続けられる。
    }
  }
}
