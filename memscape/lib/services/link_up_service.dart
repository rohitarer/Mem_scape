// services/link_up_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/connection_model.dart';

class LinkUpService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String get myUid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _connRef(String uidA, String uidB) {
    final pairId = ConnectionModel.makePairId(uidA, uidB);
    return _db.collection('connections').doc(pairId);
  }

  Future<void> sendLinkUp(String otherUid) async {
    if (myUid == otherUid) return;
    final ref = _connRef(myUid, otherUid);
    final pairId = ref.id;
    final now = FieldValue.serverTimestamp();

    // Create/merge the connection doc
    await ref.set({
      'users': [myUid, otherUid],
      'requester': myUid,
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // 🔔 Send an in-app notification to recipient
    await _db.collection('users').doc(otherUid).collection('inbox').add({
      'type': 'linkup_request',
      'fromUid': myUid,
      'pairId': pairId,
      'read': false,
      'createdAt': now,
    });
  }

  Future<void> cancelLinkUp(String otherUid) async {
    final ref = _connRef(myUid, otherUid);
    await ref.delete();

    // (Optional) mark recipient inbox items for this pair as canceled
    final inbox =
        await _db
            .collection('users')
            .doc(otherUid)
            .collection('inbox')
            .where('pairId', isEqualTo: ref.id)
            .get();
    for (final d in inbox.docs) {
      d.reference.update({'canceled': true});
    }
  }

  Future<void> acceptLinkUp(String otherUid) async {
    final ref = _connRef(myUid, otherUid);
    final now = FieldValue.serverTimestamp();
    await ref.update({'status': 'accepted', 'updatedAt': now});

    // 🔔 Notify requester that you accepted
    await _db
        .collection('users')
        .doc(otherUid) // notify the original requester
        .collection('inbox')
        .add({
          'type': 'linkup_accept',
          'fromUid': myUid,
          'pairId': ref.id,
          'read': false,
          'createdAt': now,
        });
  }

  Future<void> ignoreLinkUp(String otherUid) async {
    final ref = _connRef(myUid, otherUid);
    await ref.delete();

    // (Optional) mark recipient/requester inbox entries for this pair as resolved
  }

  // Stream<ConnectionModel?> watchConnection(String otherUid) {
  //   final ref = _connRef(myUid, otherUid);
  //   return ref.snapshots().map((doc) {
  //     if (!doc.exists) return null;
  //     return ConnectionModel.fromMap(doc.id, doc.data()!);
  //   });
  // }

  Stream<ConnectionModel?> watchConnection(String otherUid) {
    final ref = _connRef(myUid, otherUid);
    return ref
        .snapshots(includeMetadataChanges: true) // 👈 important
        .map(
          (doc) =>
              doc.exists ? ConnectionModel.fromMap(doc.id, doc.data()!) : null,
        );
  }
}

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import '../models/connection_model.dart';

// class LinkUpService {
//   final _auth = FirebaseAuth.instance;
//   final _db = FirebaseFirestore.instance;

//   String get myUid => _auth.currentUser!.uid;

//   DocumentReference<Map<String, dynamic>> _connRef(String uidA, String uidB) {
//     final pairId = ConnectionModel.makePairId(uidA, uidB);
//     return _db.collection('connections').doc(pairId);
//   }

//   Stream<ConnectionModel?> watchConnection(String otherUid) {
//     final ref = _connRef(myUid, otherUid);
//     return ref.snapshots().map((doc) {
//       if (!doc.exists) return null;
//       return ConnectionModel.fromMap(doc.id, doc.data()!);
//     });
//   }

//   Future<void> sendLinkUp(String otherUid) async {
//     if (myUid == otherUid) return;
//     final ref = _connRef(myUid, otherUid);
//     final now = FieldValue.serverTimestamp();
//     await ref.set({
//       'users': [myUid, otherUid],
//       'requester': myUid,
//       'status': 'pending',
//       'createdAt': now,
//       'updatedAt': now,
//     }, SetOptions(merge: true));
//   }

//   Future<void> cancelLinkUp(String otherUid) async {
//     final ref = _connRef(myUid, otherUid);
//     await ref.delete();
//   }

//   Future<void> acceptLinkUp(String otherUid) async {
//     final ref = _connRef(myUid, otherUid);
//     final now = FieldValue.serverTimestamp();
//     await ref.update({'status': 'accepted', 'updatedAt': now});
//   }

//   Future<void> ignoreLinkUp(String otherUid) async {
//     final ref = _connRef(myUid, otherUid);
//     await ref.delete();
//   }
// }
