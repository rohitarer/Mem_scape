import 'package:cloud_firestore/cloud_firestore.dart';

enum LinkUpStatus { pending, accepted, blocked }

class ConnectionModel {
  final String pairId;
  final String requester;
  final List<String> users; // length 2
  final LinkUpStatus status;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  ConnectionModel({
    required this.pairId,
    required this.requester,
    required this.users,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory ConnectionModel.fromMap(String id, Map<String, dynamic> map) {
    final statusStr = (map['status'] as String?) ?? 'pending';
    return ConnectionModel(
      pairId: id,
      requester: map['requester'] as String,
      users: (map['users'] as List).whereType<String>().toList(),
      status:
          {
            'pending': LinkUpStatus.pending,
            'accepted': LinkUpStatus.accepted,
            'blocked': LinkUpStatus.blocked,
          }[statusStr]!,
      createdAt: map['createdAt'] as Timestamp?,
      updatedAt: map['updatedAt'] as Timestamp?,
    );
  }

  static String makePairId(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';
}
