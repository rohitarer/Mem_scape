class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String? bio;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.bio,
  });

  /// Create a UserModel from Firestore/Realtime DB Map
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photoUrl'],
      bio: map['bio'],
    );
  }

  /// Convert UserModel to Map for Firestore or Realtime DB
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'bio': bio,
    };
  }
}
