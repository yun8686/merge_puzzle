import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/game_screen.dart';
import 'ui/theme.dart';

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
      title: '奇偶チェイン',
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
      home: const GameScreen(),
    );
  }
}
