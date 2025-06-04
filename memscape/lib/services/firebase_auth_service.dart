import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Register a new user and store their profile in Firestore
  Future<UserModel?> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      print("🔐 Creating Firebase user for $email");

      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = UserModel(
        uid: cred.user!.uid,
        name: name,
        email: email,
        photoUrl: null,
        bio: '',
      );

      print("🔥 Writing user to Firestore: ${user.toMap()}");

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(user.toMap(), SetOptions(merge: true));

      print("✅ User saved to Firestore");

      return user;
    } on FirebaseAuthException catch (e) {
      print("❌ FirebaseAuthException: ${e.message}");
      throw Exception(e.message ?? 'Registration failed');
    } catch (e, s) {
      print("❌ Unexpected Firestore error: $e\n$s");
      throw Exception('Unexpected error: $e');
    }
  }

  /// Login existing user and fetch profile
  Future<UserModel?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      print("🔑 Logging in user: $email");

      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final doc =
          await _firestore.collection('users').doc(cred.user!.uid).get();

      if (!doc.exists) {
        print("⚠️ User document not found in Firestore");
        throw Exception("User not found in database.");
      }

      print("✅ User fetched from Firestore");

      return UserModel.fromMap(doc.data()!);
    } on FirebaseAuthException catch (e) {
      print("❌ FirebaseAuthException during login: ${e.message}");
      throw Exception(e.message ?? 'Login failed');
    } catch (e, s) {
      print("❌ Unexpected login error: $e\n$s");
      throw Exception('Unexpected error: $e');
    }
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      print("🚪 Signing out user");
      await _auth.signOut();
    } catch (e, s) {
      print("❌ Logout error: $e\n$s");
      throw Exception("Logout failed: $e");
    }
  }

  /// Get current user's profile
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      print("👤 Fetching current user: ${user.uid}");

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      return UserModel.fromMap(doc.data()!);
    } catch (e, s) {
      print("❌ Error fetching user: $e\n$s");
      throw Exception("Failed to fetch user: $e");
    }
  }
}
