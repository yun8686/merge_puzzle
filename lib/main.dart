import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dev_switch.dart';
import 'game/prefs_store.dart';
import 'game/progress.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/title_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ParityChainApp());
}

class ParityChainApp extends StatelessWidget {
  const ParityChainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '氷炎の鎖',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.blueB,
          brightness: Brightness.dark,
        ),
      ),
      home: const _Entry(),
    );
  }
}

/// タイトルと拠点の入れ替え。
///
/// Navigator で積まない。タイトルへ戻る道は無いので、積むと端末の「戻る」で
/// 拠点が消えてタイトルに落ちる。入れ替えなら、そこに戻り道は生まれない。
class _Entry extends StatefulWidget {
  const _Entry();

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  bool _started = false;

  /// 記録の置き場所。**一度だけ作る。**
  ///
  /// build のたびに作り直すと、拠点が書き戻す先が毎回別の箱になって、
  /// 試用のあいだ編成が保たれない。
  ///
  /// `?all` が付いていたら、全部開いた記録を積んだ手元の箱に差し替える
  /// （`dev_switch.dart`）。端末の保存には触らない。
  late final ProgressStore _store = unlockAllRequested
      ? MemoryProgressStore(unlockedProgress().encode())
      : const PrefsProgressStore();

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      // 既定の並べ方は loose な Stack なので、画面いっぱいの制約が子に
      // 伝わらない。どちらの画面も画面の大きさで組みたいので広げておく。
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _started
          ? HomeScreen(
              key: const ValueKey('home'),
              store: _store,
              // 試用のときだけ出す。**出さないと、記録が消えたように見える。**
              banner: unlockAllRequested ? 'お試しモード　全解放・記録は保存されない' : null,
            )
          : TitleScreen(
              key: const ValueKey('title'),
              onStart: () => setState(() => _started = true),
            ),
    );
  }
}
