import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../theme/app_theme.dart';

/// ログイン画面（可愛い系）。Google サインイン。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _signingIn = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // 成功すると AuthGate が自動で切り替える。
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'サインインに失敗しました');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE4EC), Color(0xFFFFF5F7)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ロゴは画面の中央に配置。
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Image.asset(
                    'assets/brand/logo.png',
                    width: 300,
                    height: 300,
                  ),
                ),
              ),
              // サインインボタン等は画面下に固定。
              Positioned(
                left: 28,
                right: 28,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE0E6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.pinkDark, fontSize: 13)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _signingIn ? null : _signIn,
                      icon: _signingIn
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Icon(Icons.login_rounded),
                      label:
                          Text(_signingIn ? 'サインイン中…' : 'Googleではじめる'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ふたりとも同じ画面・同じデータを見られます',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
