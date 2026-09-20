import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/prefs_store.dart';
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
          seedColor: Palette.evenB,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      child: _started
          ? const HomeScreen(
              key: ValueKey('home'),
              store: PrefsProgressStore(),
            )
          : TitleScreen(
              key: const ValueKey('title'),
              onStart: () => setState(() => _started = true),
            ),
    );
  }
}
