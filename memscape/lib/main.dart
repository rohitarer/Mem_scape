import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:memscape/core/themes.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'package:memscape/screens/home/upload/upload_photo_screen.dart';

// Zego
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: kIsWeb
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
        : null,
  );

  runApp(const ProviderScope(child: MemscapeApp()));
}

/// Your Zego project credentials (from the dashboard)
const int kZegoAppID = 760323351;
const String kZegoAppSign =
    '208955149d89286cbb18d05cac4388264e2e8ebab0274aae76fb18d6348d7e12';

/// Starts/stops the Zego invitation service when auth state changes.
class _ZegoCallInvitationController {
  bool _inited = false;

  Future<void> initForUser({
    required String userID,
    required String userName,
  }) async {
    if (_inited) return;
    _inited = true;

    await ZegoUIKitPrebuiltCallInvitationService().init(
      appID: kZegoAppID,
      appSign: kZegoAppSign,
      userID: userID,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],
      // Choose a prebuilt config based on invitation type & participants
      requireConfig: (ZegoCallInvitationData data) {
        final isGroup = data.invitees.length > 1;
        final isVideo = data.type == ZegoCallType.videoCall;

        if (isGroup) {
          return isVideo
              ? ZegoUIKitPrebuiltCallConfig.groupVideoCall()
              : ZegoUIKitPrebuiltCallConfig.groupVoiceCall();
        } else {
          return isVideo
              ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
        }
      },
    );
  }

  Future<void> uninit() async {
    if (!_inited) return;
    _inited = false;
    await ZegoUIKitPrebuiltCallInvitationService().uninit();
  }
}

final _invitationController = _ZegoCallInvitationController();

class MemscapeApp extends StatelessWidget {
  const MemscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Re-init Zego whenever auth state changes
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          _invitationController.uninit(); // when logged out
        } else {
          // derive a simple display name
          final displayName = user.displayName?.trim();
          final userName = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : user.email?.split('@').first ?? user.uid.substring(0, 6);

          _invitationController.initForUser(
            userID: user.uid,
            userName: userName,
          );
        }

        return MaterialApp(
          title: 'Memscape',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const HomeScreen(),
            '/upload': (context) => const UploadMemoryScreen(),
          },
          // Enables the Zego mini-floating window over your pages
          builder: (context, child) {
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                ZegoUIKitPrebuiltCallMiniOverlayPage(
                  contextQuery: () => context,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:memscape/core/themes.dart';
// import 'package:memscape/screens/home/upload/upload_photo_screen.dart';

// import 'screens/splash_screen.dart';
// import 'screens/auth/login_screen.dart';
// import 'screens/home/home_screen.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   await Firebase.initializeApp(
//     options:
//         kIsWeb
//             ? const FirebaseOptions(
//               apiKey: "AIzaSyALwwLyhbgWoLR7U7T6EuAMdRILqcLf-dU",
//               authDomain: "memscape-d6348.firebaseapp.com",
//               databaseURL: "https://memscape-d6348-default-rtdb.firebaseio.com",
//               projectId: "memscape-d6348",
//               storageBucket: "memscape-d6348.appspot.com",
//               messagingSenderId: "1058293704983",
//               appId: "1:1058293704983:web:6d7fb2abc2ae546b686f52",
//               measurementId: "G-F5J0Y5HCCL",
//             )
//             : null, // Android uses google-services.json
//   );
//   debugPrint("✅ Firebase initialized.");

//   runApp(const ProviderScope(child: MemscapeApp()));
// }

// class MemscapeApp extends StatelessWidget {
//   const MemscapeApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Memscape',
//       debugShowCheckedModeBanner: false,
//       theme: AppTheme.lightTheme,
//       darkTheme: AppTheme.darkTheme,
//       themeMode: ThemeMode.system,
//       home: const SplashScreen(),

//       // ✅ Registered routes
//       routes: {
//         '/login': (context) => const LoginScreen(),
//         '/home': (context) => const HomeScreen(),
//         '/upload': (context) => const UploadMemoryScreen(),
//       },
//     );
//   }
// }
