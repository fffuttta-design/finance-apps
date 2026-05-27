import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'data/app_mode.dart';
import 'firebase_options.dart';
import 'screens/root_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // AppMode (事業/個人) の初期化 + 旧データの移行
  await AppModeManager.instance.init();
  // Web では Firebase オプション未設定のため初期化をスキップ。
  // 実機(Android/iOS)では従来通り初期化する。
  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(const FutaFinanceApp());
}

class FutaFinanceApp extends StatelessWidget {
  const FutaFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // モード変更時にテーマ（特に scaffoldBackgroundColor）を再構築するため、
    // AppModeManager を listenable にして MaterialApp ごと rebuild する。
    return ListenableBuilder(
      listenable: AppModeManager.instance,
      builder: (context, _) {
        final mode = AppModeManager.instance.current;
        return MaterialApp(
          title: 'FutaFinance',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ja', 'JP'),
            Locale('en', 'US'),
          ],
          locale: const Locale('ja', 'JP'),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: mode.accentColor,
              brightness: Brightness.light,
            ),
            // モード別の薄背景（事業=薄紺、個人=薄オレンジ）
            scaffoldBackgroundColor: mode.backgroundTint,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF111827),
              elevation: 0,
              surfaceTintColor: Colors.white,
            ),
          ),
          home: const RootScreen(),
        );
      },
    );
  }
}
