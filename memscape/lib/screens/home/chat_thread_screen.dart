import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:memscape/widgets/chat_input_bar.dart';
import 'package:memscape/widgets/message_bubble.dart';

class ChatThreadScreen extends StatefulWidget {
  final String otherUid;
  final String? pairId;

  const ChatThreadScreen({super.key, required this.otherUid, this.pairId});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String? _otherNickname;
  ImageProvider? _otherAvatar;
  ImageProvider? _myAvatar; // 👈 new

  // Reply preview
  String? _replyText;
  String? _replySender;

  // Typing
  bool _otherTyping = false;
  Timer? _typingOffTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _typingSub;

  String get myUid => _auth.currentUser!.uid;

  String get _pairId {
    if (widget.pairId != null) return widget.pairId!;
    final a = myUid.compareTo(widget.otherUid) <= 0 ? myUid : widget.otherUid;
    final b = myUid.compareTo(widget.otherUid) <= 0 ? widget.otherUid : myUid;
    return "${a}_$b";
  }

  @override
  void initState() {
    super.initState();
    _loadOtherUser();
    _loadMyAvatar(); // 👈 new
    _listenTyping();
  }

  @override
  void dispose() {
    _typingSub?.cancel();
    _typingOffTimer?.cancel();
    super.dispose();
  }

  // dummy “encryption”
  String _enc(String plain) => base64Encode(utf8.encode(plain));
  String _dec(String enc) {
    try {
      return utf8.decode(base64Decode(enc));
    } catch (_) {
      return enc;
    }
  }

  // Load avatars
  Future<void> _loadMyAvatar() async {
    try {
      final me = await _db.collection('users').doc(myUid).get();
      final data = me.data();
      final profilePath = (data?['profileImagePath'] as String?);

      ImageProvider? avatar;
      if (profilePath != null && profilePath.isNotEmpty) {
        final b64 = await FirestoreService().fetchProfileBase64(profilePath);
        if (b64 != null && b64.isNotEmpty) {
          try {
            avatar = MemoryImage(base64Decode(b64));
          } catch (_) {}
        }
      }
      avatar ??= const NetworkImage(
        "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
      );
      if (mounted) setState(() => _myAvatar = avatar);
    } catch (_) {}
  }

  Future<void> _loadOtherUser() async {
    try {
      final snap = await _db.collection('users').doc(widget.otherUid).get();
      final data = snap.data();
      final nickname = (data?['username'] as String?) ?? 'mutual';
      final profilePath = (data?['profileImagePath'] as String?);

      ImageProvider? avatar;
      if (profilePath != null && profilePath.isNotEmpty) {
        final base64 = await FirestoreService().fetchProfileBase64(profilePath);
        if (base64 != null && base64.isNotEmpty) {
          try {
            avatar = MemoryImage(base64Decode(base64));
          } catch (_) {}
        }
      }
      avatar ??= const NetworkImage(
        "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
      );

      if (mounted) {
        setState(() {
          _otherNickname = nickname;
          _otherAvatar = avatar;
        });
      }
    } catch (_) {}
  }

  // Typing
  void _listenTyping() {
    _typingSub = _db
        .collection('connections')
        .doc(_pairId)
        .snapshots() // no metadata changes
        .listen((doc) {
          final data = doc.data();
          final typingMap = (data?['typing'] as Map?)?.cast<String, dynamic>();
          final otherIsTyping =
              typingMap != null
                  ? (typingMap[widget.otherUid] as bool?) ?? false
                  : false;

          if (mounted && otherIsTyping != _otherTyping) {
            setState(() => _otherTyping = otherIsTyping); // only when changed
          }
        });
  }

  Future<void> _setTyping(bool isTyping) async {
    await _db.collection('connections').doc(_pairId).set({
      'typing': {myUid: isTyping},
    }, SetOptions(merge: true));
  }

  void _onTypingPulse() {
    _setTyping(true);
    _typingOffTimer?.cancel();
    _typingOffTimer = Timer(
      const Duration(seconds: 2),
      () => _setTyping(false),
    );
  }

  // Messages
  Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream() {
    return _db
        .collection('messages')
        .doc(_pairId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots(); // no metadata changes
  }

  Future<void> _sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    try {
      final encText = _enc(clean);
      final encReply =
          (_replyText != null && _replyText!.isNotEmpty)
              ? _enc(_replyText!)
              : null;

      final msg = <String, dynamic>{
        'senderId': myUid,
        'text': encText,
        'enc': true,
        'createdAt': FieldValue.serverTimestamp(),
        if (encReply != null)
          'reply': {'text': encReply, 'senderId': _replySender ?? ''},
      };

      final items = _db.collection('messages').doc(_pairId).collection('items');
      final docRef = await items.add(msg);

      // mirrors (rules now allow either participant to write)
      await Future.wait([
        _db
            .collection('users')
            .doc(myUid)
            .collection('chats')
            .doc(_pairId)
            .collection('items')
            .doc(docRef.id)
            .set(msg),
        _db
            .collection('users')
            .doc(widget.otherUid)
            .collection('chats')
            .doc(_pairId)
            .collection('items')
            .doc(docRef.id)
            .set(msg),
      ]);

      setState(() {
        _replyText = null;
        _replySender = null;
      });

      await _db.collection('connections').doc(_pairId).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _setTyping(false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
    }
  }

  void _onSwipeReply(String text, String senderId) {
    if (senderId == myUid) return;
    setState(() {
      _replyText = text;
      _replySender = senderId;
    });
  }

  void _clearReply() {
    setState(() {
      _replyText = null;
      _replySender = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _otherNickname ?? 'mutual';
    final avatar =
        _otherAvatar ??
        const NetworkImage(
          "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
        );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(backgroundImage: avatar),
            const SizedBox(width: 12),
            Text(nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messageStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "say hey to spark a vibe ✨",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  key: const PageStorageKey('chat-list'), // keep scroll pos
                  reverse: true,
                  cacheExtent: 600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final m = doc.data();
                    final senderId = m['senderId'] as String? ?? '';
                    final isEnc = m['enc'] == true;
                    final rawText = (m['text'] as String?) ?? '';
                    final text = isEnc ? _dec(rawText) : rawText;

                    final ts = (m['createdAt']);
                    final createdAt = (ts is Timestamp) ? ts.toDate() : null;

                    final reply = m['reply'] as Map<String, dynamic>?;
                    final replyTextRaw = reply?['text'] as String?;
                    final replyText =
                        (replyTextRaw != null && isEnc)
                            ? _dec(replyTextRaw)
                            : replyTextRaw;

                    final isMine = senderId == myUid;

                    return KeyedSubtree(
                      key: ValueKey(
                        doc.id,
                      ), // 👈 stabilize widgets, reduce flicker
                      child: MessageBubble(
                        isMine: isMine,
                        text: text,
                        createdAt: createdAt,
                        avatarProvider:
                            isMine ? _myAvatar : _otherAvatar, // 👈 BOTH sides
                        nicknameForA11y: nickname,
                        replyText: replyText,
                        onSwipeReply: () => _onSwipeReply(text, senderId),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Typing indicator slot — fixed height to avoid layout jumps
          SizedBox(
            height: 22,
            child: AnimatedOpacity(
              opacity: _otherTyping ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${_otherNickname ?? 'They'} are typing…",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Composer
          ChatInputBar(
            replyText: _replyText,
            onCancelReply: _clearReply,
            onSend: _sendMessage,
            onTypingPulse: _onTypingPulse,
          ),
        ],
      ),
    );
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/services/firestore_service.dart';
// import 'package:memscape/widgets/chat_input_bar.dart';
// import 'package:memscape/widgets/message_bubble.dart';

// /// 💬 VibeLine — one‑to‑one DM screen
// /// - AppBar: avatar + nickname
// /// - Swipe a bubble (other side) → reply preview above input
// /// - Typing indicator shown **above** the text field
// /// - Fan‑out saves to both users
// /// - Dummy encryption (base64) now; swap later for real E2E
// class ChatThreadScreen extends StatefulWidget {
//   final String otherUid;
//   final String? pairId;

//   const ChatThreadScreen({super.key, required this.otherUid, this.pairId});

//   @override
//   State<ChatThreadScreen> createState() => _ChatThreadScreenState();
// }

// class _ChatThreadScreenState extends State<ChatThreadScreen> {
//   final _auth = FirebaseAuth.instance;
//   final _db = FirebaseFirestore.instance;

//   String? _otherNickname;
//   ImageProvider? _otherAvatar;
//   ImageProvider? _myAvatar;

//   // Reply preview
//   String? _replyText;
//   String? _replySender;

//   // Typing
//   bool _otherTyping = false;
//   Timer? _typingOffTimer; // debounce my typing "false"
//   StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _typingSub;

//   String get myUid => _auth.currentUser!.uid;

//   String get _pairId {
//     if (widget.pairId != null) return widget.pairId!;
//     final a = myUid.compareTo(widget.otherUid) <= 0 ? myUid : widget.otherUid;
//     final b = myUid.compareTo(widget.otherUid) <= 0 ? widget.otherUid : myUid;
//     return "${a}_$b";
//   }

//   @override
//   void initState() {
//     super.initState();
//     _loadOtherUser();
//     _loadMyAvatar();
//     _listenTyping();
//   }

//   @override
//   void dispose() {
//     _typingSub?.cancel();
//     _typingOffTimer?.cancel();
//     super.dispose();
//   }

//   // ===== Encryption placeholders (swap later for real E2E) =====
//   String _enc(String plain) => base64Encode(utf8.encode(plain));
//   String _dec(String enc) {
//     try {
//       return utf8.decode(base64Decode(enc));
//     } catch (_) {
//       // fallback if not encrypted (legacy)
//       return enc;
//     }
//   }

//   // ===== Typing (stored in connections/{pairId}.typing.{uid}: bool) =====
//   void _listenTyping() {
//     _typingSub = _db
//         .collection('connections')
//         .doc(_pairId)
//         .snapshots(includeMetadataChanges: true)
//         .listen((doc) {
//           final data = doc.data();
//           final typingMap = (data?['typing'] as Map?)?.cast<String, dynamic>();
//           final otherIsTyping =
//               typingMap != null
//                   ? (typingMap[widget.otherUid] as bool?) ?? false
//                   : false;
//           if (mounted && otherIsTyping != _otherTyping) {
//             setState(
//               () => _otherTyping = otherIsTyping,
//             ); // 👈 only when changed
//           }
//           // if (mounted) {
//           //   setState(() => _otherTyping = otherIsTyping);
//           // }
//         });
//   }

//   Future<void> _loadMyAvatar() async {
//     // 👈 NEW
//     try {
//       final me = await _db.collection('users').doc(myUid).get();
//       final data = me.data();
//       final profilePath = (data?['profileImagePath'] as String?);

//       ImageProvider? avatar;
//       if (profilePath != null && profilePath.isNotEmpty) {
//         final base64 = await FirestoreService().fetchProfileBase64(profilePath);
//         if (base64 != null && base64.isNotEmpty) {
//           try {
//             avatar = MemoryImage(base64Decode(base64));
//           } catch (_) {}
//         }
//       }
//       avatar ??= const NetworkImage(
//         "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//       );

//       if (mounted) setState(() => _myAvatar = avatar);
//     } catch (_) {}
//   }

//   Future<void> _setTyping(bool isTyping) async {
//     await _db.collection('connections').doc(_pairId).set({
//       'typing': {myUid: isTyping},
//     }, SetOptions(merge: true));
//   }

//   void _onTypingPulse() {
//     // call when user is typing in the TextField
//     _setTyping(true);
//     _typingOffTimer?.cancel();
//     _typingOffTimer = Timer(
//       const Duration(seconds: 2),
//       () => _setTyping(false),
//     );
//   }

//   // ===== Other user =====
//   Future<void> _loadOtherUser() async {
//     try {
//       final snap = await _db.collection('users').doc(widget.otherUid).get();
//       final data = snap.data();
//       final nickname = (data?['username'] as String?) ?? 'mutual';
//       final profilePath = (data?['profileImagePath'] as String?);

//       ImageProvider? avatar;
//       if (profilePath != null && profilePath.isNotEmpty) {
//         final base64 = await FirestoreService().fetchProfileBase64(profilePath);
//         if (base64 != null && base64.isNotEmpty) {
//           try {
//             avatar = MemoryImage(base64Decode(base64));
//           } catch (_) {}
//         }
//       }
//       avatar ??= const NetworkImage(
//         "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//       );

//       if (mounted) {
//         setState(() {
//           _otherNickname = nickname;
//           _otherAvatar = avatar;
//         });
//       }
//     } catch (_) {}
//   }

//   // ===== Messages =====
//   Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream() {
//     return _db
//         .collection('messages')
//         .doc(_pairId)
//         .collection('items')
//         .orderBy('createdAt', descending: true)
//         .snapshots();
//     // .snapshots(includeMetadataChanges: true);
//   }

//   Future<void> _sendMessage(String text) async {
//     final clean = text.trim();
//     if (clean.isEmpty) return;

//     try {
//       final encText = _enc(clean);
//       final encReply =
//           (_replyText != null && _replyText!.isNotEmpty)
//               ? _enc(_replyText!)
//               : null;

//       final msg = <String, dynamic>{
//         'senderId': myUid,
//         'text': encText,
//         'enc': true,
//         'createdAt': FieldValue.serverTimestamp(),
//         if (encReply != null)
//           'reply': {'text': encReply, 'senderId': _replySender ?? ''},
//       };

//       // canonical
//       final items = _db.collection('messages').doc(_pairId).collection('items');
//       final docRef = await items.add(msg);

//       // fan‑out mirrors
//       await Future.wait([
//         _db
//             .collection('users')
//             .doc(myUid)
//             .collection('chats')
//             .doc(_pairId)
//             .collection('items')
//             .doc(docRef.id)
//             .set(msg),
//         _db
//             .collection('users')
//             .doc(widget.otherUid)
//             .collection('chats')
//             .doc(_pairId)
//             .collection('items')
//             .doc(docRef.id)
//             .set(msg),
//       ]);

//       setState(() {
//         _replyText = null;
//         _replySender = null;
//       });

//       await _db.collection('connections').doc(_pairId).set({
//         'updatedAt': FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true));

//       // stop typing
//       await _setTyping(false);
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
//     }
//   }

//   void _onSwipeReply(String text, String senderId) {
//     // Only allow reply on the other person's bubble
//     if (senderId == myUid) return;
//     setState(() {
//       _replyText = text;
//       _replySender = senderId;
//     });
//   }

//   void _clearReply() {
//     setState(() {
//       _replyText = null;
//       _replySender = null;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final nickname = _otherNickname ?? 'mutual';
//     final avatar =
//         _otherAvatar ??
//         const NetworkImage(
//           "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//         );

//     return Scaffold(
//       appBar: AppBar(
//         titleSpacing: 0,
//         title: Row(
//           children: [
//             CircleAvatar(backgroundImage: avatar),
//             const SizedBox(width: 12),
//             Text(nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
//           ],
//         ),
//       ),
//       body: Column(
//         children: [
//           // Messages
//           Expanded(
//             child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//               stream: _messageStream(),
//               builder: (context, snap) {
//                 if (snap.connectionState == ConnectionState.waiting) {
//                   return const Center(child: CircularProgressIndicator());
//                 }
//                 final docs = snap.data?.docs ?? [];
//                 if (docs.isEmpty) {
//                   return Center(
//                     child: Padding(
//                       padding: const EdgeInsets.all(24),
//                       child: Text(
//                         "say hey to spark a vibe ✨",
//                         style: Theme.of(context).textTheme.titleMedium
//                             ?.copyWith(fontWeight: FontWeight.w600),
//                       ),
//                     ),
//                   );
//                 }

//                 return ListView.builder(
//                   reverse: true,
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 12,
//                     vertical: 10,
//                   ),
//                   itemCount: docs.length,
//                   itemBuilder: (context, i) {
//                     final m = docs[i].data();
//                     final senderId = m['senderId'] as String? ?? '';
//                     final isEnc = m['enc'] == true;
//                     final rawText = (m['text'] as String?) ?? '';
//                     final text = isEnc ? _dec(rawText) : rawText;

//                     final ts = (m['createdAt']);
//                     final createdAt = (ts is Timestamp) ? ts.toDate() : null;

//                     final reply = m['reply'] as Map<String, dynamic>?;
//                     final replyTextRaw = reply?['text'] as String?;
//                     final replyText =
//                         (replyTextRaw != null && isEnc)
//                             ? _dec(replyTextRaw)
//                             : replyTextRaw;

//                     final isMine = senderId == myUid;

//                     return MessageBubble(
//                       isMine: isMine,
//                       text: text,
//                       createdAt: createdAt,
//                       avatarProvider: isMine ? _myAvatar : _otherAvatar,
//                       // avatarProvider: isMine ? null : avatar,
//                       nicknameForA11y: nickname,
//                       replyText: replyText,
//                       onSwipeReply: () => _onSwipeReply(text, senderId),
//                     );
//                   },
//                 );
//               },
//             ),
//           ),

//           // Typing indicator (above the input bar)
//           if (_otherTyping)
//             Padding(
//               padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
//               child: Row(
//                 children: [
//                   const SizedBox(
//                     width: 16,
//                     height: 16,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   ),
//                   const SizedBox(width: 8),
//                   Text(
//                     "${_otherNickname ?? 'They'} are typing…",
//                     style: Theme.of(context).textTheme.bodySmall,
//                   ),
//                 ],
//               ),
//             ),

//           // Composer
//           ChatInputBar(
//             replyText: _replyText,
//             onCancelReply: _clearReply,
//             onSend: _sendMessage,
//             onTypingPulse: _onTypingPulse, // <— fire while typing
//           ),
//         ],
//       ),
//     );
//   }
// }
