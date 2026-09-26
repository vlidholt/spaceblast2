import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/ui/game_shell.dart';
import 'game/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  runApp(const SpaceBlastApp());
}

class SpaceBlastApp extends StatelessWidget {
  const SpaceBlastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Space Blast',
      debugShowCheckedModeBanner: false,
      color: SbColors.background,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: SbText.family,
        scaffoldBackgroundColor: SbColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SbColors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const Scaffold(body: GameShell()),
    );
  }
}
