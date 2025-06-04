import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:memscape/core/themes.dart';
import 'package:memscape/screens/home/upload_photo_screen.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options:
        kIsWeb
            ? const FirebaseOptions(
              apiKey: "AIzaSyALwwLyhbgWoLR7U7T6EuAMdRILqcLf-dU",
              authDomain: "memscape-d6348.firebaseapp.com",
              databaseURL: "https://memscape-d6348-default-rtdb.firebaseio.com",
              projectId: "memscape-d6348",
              storageBucket: "memscape-d6348.appspot.com",
              messagingSenderId: "1058293704983",
              appId: "1:1058293704983:web:6d7fb2abc2ae546b686f52",
              measurementId: "G-F5J0Y5HCCL",
            )
            : null, // Android uses google-services.json
  );
  debugPrint("✅ Firebase initialized.");

  runApp(const ProviderScope(child: MemscapeApp()));
}

class MemscapeApp extends StatelessWidget {
  const MemscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memscape',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),

      // ✅ Registered routes
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/upload': (context) => const UploadPhotoScreen(),
      },
    );
  }
}
