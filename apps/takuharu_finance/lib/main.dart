import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finance_core/finance_core.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TakuharuFinanceApp());
}

class TakuharuFinanceApp extends StatelessWidget {
  const TakuharuFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'たくはるファイナンス',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B8A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF5F7),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _info = AppInfo(
    name: 'たくはるファイナンス',
    tagline: 'たくと はる の家計簿',
  );

  @override
  Widget build(BuildContext context) {
    final firebaseProject = Firebase.app().options.projectId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('たくはるファイナンス'),
        backgroundColor: const Color(0xFFFF6B8A),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, size: 80, color: Color(0xFFFF6B8A)),
              const SizedBox(height: 24),
              Text(
                _info.greeting(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Color(0xFF6B4452), height: 1.6),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFF6B8A)),
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                ),
                child: const Text(
                  'v1.0.1+2  /  com.takuharu.finance',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFF6B8A), fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 6),
                  Text(
                    'Firebase接続中: $firebaseProject',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50), fontFamily: 'monospace'),
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
