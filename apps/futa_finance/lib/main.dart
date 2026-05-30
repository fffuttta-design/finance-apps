import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'data/app_mode.dart';
import 'data/auth_service.dart';
import 'data/data_migration_service.dart';
import 'data/repository_provider.dart';
import 'data/ui_preferences.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/root_screen.dart';
import 'v2/theme/app_theme.dart';
import 'v2/v2_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // AppMode (事業/個人) の初期化 + 旧データの移行
  await AppModeManager.instance.init();
  // UI 表示設定（残高0隠す等）を SharedPreferences から復元
  await UiPreferences.instance.load();
  // Firebase 初期化（Web/Android 両対応、flutterfire configure 済み前提）
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Google Sign-In 初期化
  await AuthService.instance.init();
  runApp(const FutaFinanceApp());
}

class FutaFinanceApp extends StatelessWidget {
  const FutaFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // モード変更時にテーマ（特に scaffoldBackgroundColor）を再構築するため、
    // AppModeManager を listenable にして MaterialApp ごと rebuild する。
    // また UiPreferences の v1/v2 切替にも追従する。
    return ListenableBuilder(
      listenable: Listenable.merge(
          [AppModeManager.instance, UiPreferences.instance]),
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
          // v1 のテーマは MaterialApp に直接渡す（ダイアログ・スナックバー等の
          // デフォルトを担保）。v2 のときは _AuthGate の中で Theme widget で
          // 上書きするので、ここではテーマ判定をしない。
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: mode.accentColor,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: mode.backgroundTint,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF111827),
              elevation: 0,
              surfaceTintColor: Colors.white,
            ),
          ),
          home: const _AuthGate(),
        );
      },
    );
  }
}

/// 認証状態に応じて画面を切り替える Gate。
/// - 未ログイン → AuthScreen + Local Repository
/// - ログイン済み → RootScreen + Firestore Repository（初回はローカル→クラウド移行）
/// - 初期化中 → スプラッシュ
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  /// 現在のログインユーザーに対して、初回のローカル→Firestore データ移行を
  /// 実行中／完了済みかどうかのフラグ。uid 単位で1度だけ実行。
  String? _migratedUid;
  bool _migrating = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.userStream,
      builder: (context, snapshot) {
        // 初期化中（最初のイベント前）
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // 未ログイン → Local 版に戻す（次回サインインで切替）
          if (RepositoryProvider.isFirestoreActive) {
            RepositoryProvider.useLocal();
          }
          return const AuthScreen();
        }

        // ログイン済み → Firestore 版に切替（idempotent）
        RepositoryProvider.useFirestore(user.uid);

        // 初回サインイン時のローカル→Firestore移行を1回だけ実行
        if (_migratedUid != user.uid && !_migrating) {
          _migrating = true;
          DataMigrationService.migrateLocalToFirestoreIfNeeded(user.uid)
              .then((_) {
            if (!mounted) return;
            setState(() {
              _migratedUid = user.uid;
              _migrating = false;
            });
          }).catchError((e) {
            // 移行失敗してもアプリは使えるようにする
            if (!mounted) return;
            setState(() {
              _migratedUid = user.uid;
              _migrating = false;
            });
          });
          // 移行中はスプラッシュ
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('クラウド同期を準備中...'),
                ],
              ),
            ),
          );
        }
        if (_migrating) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('クラウド同期を準備中...'),
                ],
              ),
            ),
          );
        }

        // v1/v2 切替（自動 or 設定の手動値）。
        // v2 のときは V2Theme でラップして v2 配下の widget 全体に適用する。
        final width = MediaQuery.sizeOf(context).width;
        final useV2 = UiPreferences.instance.resolveUseV2(
            isWeb: kIsWeb, width: width);
        if (useV2) {
          return Theme(
            data: V2Theme.light(),
            child: const V2Root(),
          );
        }
        return const RootScreen();
      },
    );
  }
}
