import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final user = FirebaseAuth.instance.currentUser!;
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  // 🔹 Emotions config
  static const int _maxEmotions = 5;
  static const List<String> _availableEmotions = [
    'Happy',
    'Sad',
    'Chill',
    'Excited',
    'Adventurous',
    'Romantic',
    'Curious',
    'Crazy',
    'Learning',
    'Relaxed',
    'Nostalgic',
    'Inspired',
    'Motivated',
    'Calm',
    'Energetic',
  ];
  List<String> _selectedEmotions = [];

  String? imagePath;
  String? imageBase64;
  bool isLoading = true;

  final realtimeDB = FirebaseDatabase.instance;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _usernameController.text = data['username'] ?? '';
        _bioController.text = data['bio'] ?? '';
        imagePath = data['profileImagePath'];

        // 🔹 Load emotions
        final em = data['emotions'];
        if (em is List) {
          _selectedEmotions = em.whereType<String>().toList();
        }

        if (imagePath != null && imagePath!.isNotEmpty) {
          final snapshot = await realtimeDB.ref(imagePath!).get();
          if (snapshot.exists) {
            imageBase64 = snapshot.value as String;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error loading profile: $e");
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final bytes = await File(pickedFile.path).readAsBytes();
    final base64String = base64Encode(bytes);

    final path = "profile_images/${user.uid}";
    await realtimeDB.ref(path).set(base64String);

    setState(() {
      imagePath = path;
      imageBase64 = base64String;
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'profileImagePath': path,
      'name': _nameController.text.trim(),
      'username': _usernameController.text.trim(),
      'bio': _bioController.text.trim(),
      // 🔹 Persist emotions on image save too (keeps both flows consistent)
      'emotions': _selectedEmotions,
    }, SetOptions(merge: true));
  }

  Future<void> _saveProfile() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        'bio': _bioController.text.trim(),
        'profileImagePath': imagePath ?? '',
        // 🔹 Save selected emotions
        'emotions': _selectedEmotions,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Profile saved successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Failed to save profile: $e")));
    }
  }

  // 🔹 “Dropdown-like” multi-select opener
  Future<void> _openEmotionsPicker() async {
    final current = Set<String>.from(_selectedEmotions);

    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final temp = Set<String>.from(current);
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void toggle(String value) {
              if (temp.contains(value)) {
                temp.remove(value);
              } else {
                if (temp.length >= _maxEmotions) return; // enforce limit
                temp.add(value);
              }
              setModalState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        "Select Emotions",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${temp.length}/$_maxEmotions",
                        style: TextStyle(
                          color:
                              temp.length >= _maxEmotions
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // List with checkboxes
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _availableEmotions.length,
                      itemBuilder: (context, i) {
                        final label = _availableEmotions[i];
                        final selected = temp.contains(label);
                        final canSelectMore =
                            temp.length < _maxEmotions || selected;
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (val) {
                            if (val == true && !canSelectMore) return;
                            toggle(label);
                          },
                          title: Text(label),
                          controlAffinity: ListTileControlAffinity.leading,
                          secondary:
                              selected ? const Icon(Icons.check_circle) : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, current.toList()),
                        child: const Text("Cancel"),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, temp.toList()),
                        child: const Text("Done"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedEmotions = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("👤 Edit Profile"),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveProfile),
        ],
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage:
                              imageBase64 != null
                                  ? MemoryImage(base64Decode(imageBase64!))
                                  : const NetworkImage(
                                        "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                                      )
                                      as ImageProvider,
                        ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt),
                          onPressed: _pickAndUploadImage,
                          tooltip: "Change photo",
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),

                    // 🔹 Emotions "dropdown" just below Bio
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Emotions (up to $_maxEmotions)",
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _openEmotionsPicker,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: "Select emotions",
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                        ),
                        child:
                            _selectedEmotions.isEmpty
                                ? Text(
                                  "None selected",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                )
                                : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      _selectedEmotions
                                          .map(
                                            (e) => Chip(
                                              label: Text(e),
                                              onDeleted: () {
                                                setState(() {
                                                  _selectedEmotions.remove(e);
                                                });
                                              },
                                            ),
                                          )
                                          .toList(),
                                ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
    );
  }
}

// import 'dart:convert';
// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';

// class EditProfileScreen extends StatefulWidget {
//   const EditProfileScreen({super.key});

//   @override
//   State<EditProfileScreen> createState() => _EditProfileScreenState();
// }

// class _EditProfileScreenState extends State<EditProfileScreen> {
//   final user = FirebaseAuth.instance.currentUser!;
//   final _nameController = TextEditingController();
//   final _usernameController = TextEditingController();
//   final _bioController = TextEditingController();

//   String? imagePath;
//   String? imageBase64;
//   bool isLoading = true;

//   final realtimeDB = FirebaseDatabase.instance;

//   @override
//   void initState() {
//     super.initState();
//     _loadProfile();
//   }

//   Future<void> _loadProfile() async {
//     try {
//       final doc =
//           await FirebaseFirestore.instance
//               .collection('users')
//               .doc(user.uid)
//               .get();
//       if (doc.exists) {
//         final data = doc.data()!;
//         _nameController.text = data['name'] ?? '';
//         _usernameController.text = data['username'] ?? '';
//         _bioController.text = data['bio'] ?? '';
//         imagePath = data['profileImagePath'];

//         if (imagePath != null && imagePath!.isNotEmpty) {
//           final snapshot = await realtimeDB.ref(imagePath!).get();
//           if (snapshot.exists) {
//             imageBase64 = snapshot.value as String;
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("❌ Error loading profile: $e");
//     }

//     if (mounted) {
//       setState(() {
//         isLoading = false;
//       });
//     }
//   }

//   Future<void> _pickAndUploadImage() async {
//     final picker = ImagePicker();
//     final pickedFile = await picker.pickImage(source: ImageSource.gallery);
//     if (pickedFile == null) return;

//     final bytes = await File(pickedFile.path).readAsBytes();
//     final base64String = base64Encode(bytes);

//     final path = "profile_images/${user.uid}";
//     await realtimeDB.ref(path).set(base64String);

//     setState(() {
//       imagePath = path;
//       imageBase64 = base64String;
//     });

//     await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
//       'profileImagePath': path,
//       'name': _nameController.text.trim(),
//       'username': _usernameController.text.trim(),
//       'bio': _bioController.text.trim(),
//     }, SetOptions(merge: true));
//   }

//   Future<void> _saveProfile() async {
//     try {
//       await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
//         'name': _nameController.text.trim(),
//         'username': _usernameController.text.trim(),
//         'bio': _bioController.text.trim(),
//         'profileImagePath': imagePath ?? '',
//       }, SetOptions(merge: true));

//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("✅ Profile saved successfully")),
//       );
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text("❌ Failed to save profile: $e")));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("👤 Edit Profile"),
//         actions: [
//           IconButton(icon: const Icon(Icons.save), onPressed: _saveProfile),
//         ],
//       ),
//       body:
//           isLoading
//               ? const Center(child: CircularProgressIndicator())
//               : SingleChildScrollView(
//                 padding: const EdgeInsets.all(24),
//                 child: Column(
//                   children: [
//                     Stack(
//                       alignment: Alignment.bottomRight,
//                       children: [
//                         CircleAvatar(
//                           radius: 60,
//                           backgroundImage:
//                               imageBase64 != null
//                                   ? MemoryImage(base64Decode(imageBase64!))
//                                   : const NetworkImage(
//                                         "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//                                       )
//                                       as ImageProvider,
//                         ),
//                         IconButton(
//                           icon: const Icon(Icons.camera_alt),
//                           onPressed: _pickAndUploadImage,
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 24),
//                     TextField(
//                       controller: _nameController,
//                       decoration: const InputDecoration(
//                         labelText: 'Full Name',
//                         border: OutlineInputBorder(),
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     TextField(
//                       controller: _usernameController,
//                       decoration: const InputDecoration(
//                         labelText: 'Username',
//                         border: OutlineInputBorder(),
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     TextField(
//                       controller: _bioController,
//                       decoration: const InputDecoration(
//                         labelText: 'Bio',
//                         border: OutlineInputBorder(),
//                       ),
//                       maxLines: 3,
//                     ),
//                   ],
//                 ),
//               ),
//     );
//   }
// }
