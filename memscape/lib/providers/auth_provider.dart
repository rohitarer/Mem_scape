import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/firebase_auth_service.dart';

/// 🔐 Auth service singleton
final authServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});

/// 🔁 Firebase auth state stream (User)
final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// 👤 Current user model (loaded from Firestore)
final userModelProvider = FutureProvider<UserModel?>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return await authService.getCurrentUser();
});

/// 🔑 Login provider using email/password
final loginProvider = FutureProvider.family<UserModel?, Map<String, String>>((
  ref,
  credentials,
) async {
  final authService = ref.read(authServiceProvider);
  return await authService.loginUser(
    email: credentials['email']!,
    password: credentials['password']!,
  );
});

/// 🆕 Register provider using name/email/password
final registerProvider = FutureProvider.family<UserModel?, Map<String, String>>(
  (ref, data) async {
    final authService = ref.read(authServiceProvider);
    return await authService.registerUser(
      name: data['name']!,
      email: data['email']!,
      password: data['password']!,
    );
  },
);

/// 🚪 Logout action
final logoutProvider = Provider<Future<void> Function()>((ref) {
  final authService = ref.read(authServiceProvider);
  return authService.logout;
});
