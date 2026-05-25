import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finance_core/finance_core.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FutaFinanceApp());
}

class FutaFinanceApp extends StatelessWidget {
  const FutaFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FutaFinance',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1116),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _info = AppInfo(
    name: 'FutaFinance',
    tagline: '事業用財務管理',
  );

  @override
  Widget build(BuildContext context) {
    final firebaseProject = Firebase.app().options.projectId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FutaFinance'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance, size: 80, color: Color(0xFF7986CB)),
              const SizedBox(height: 24),
              Text(
                _info.greeting(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF7986CB)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'v1.0.1+2  /  com.futa.finance',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7986CB), fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF66BB6A)),
                  const SizedBox(width: 6),
                  Text(
                    'Firebase接続中: $firebaseProject',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF66BB6A), fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
