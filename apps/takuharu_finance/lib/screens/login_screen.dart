import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.pink.withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        size: 56, color: AppColors.pink),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'たくはるファイナンス',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zenMaruGothic(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ふたりの家計簿 ♡',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zenMaruGothic(
                    fontSize: 14,
                    color: AppColors.textSub,
                  ),
                ),
                const Spacer(flex: 3),
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
                  label: Text(_signingIn ? 'サインイン中…' : 'Googleではじめる'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ふたりとも同じ画面・同じデータを見られます',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
