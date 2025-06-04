import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memscape/screens/home/home_screen.dart';

import '../../models/photo_model.dart';
import '../../widgets/custom_textfield.dart';
import '../../widgets/primary_button.dart';

class UploadPhotoScreen extends ConsumerStatefulWidget {
  const UploadPhotoScreen({super.key});

  @override
  ConsumerState<UploadPhotoScreen> createState() => _UploadPhotoScreenState();
}

class _UploadPhotoScreenState extends ConsumerState<UploadPhotoScreen> {
  File? _selectedImage;
  final captionController = TextEditingController();
  final locationController = TextEditingController();
  TextEditingController? fieldTextEditingController;
  bool isLoading = false;
  final picker = ImagePicker();
  double? _lat;
  double? _lng;
  bool isPublic = true;

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
  }

  Future<void> pickImage() async {
    try {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final file = File(picked.path);
        final sizeInMB = await file.length() / (1024 * 1024);
        if (sizeInMB > 5) {
          _showSnackBar("❌ Image too large. Please pick one under 5MB.");
          return;
        }
        setState(() => _selectedImage = file);
      } else {
        _showSnackBar("⚠️ No image selected.");
      }
    } catch (e) {
      _showSnackBar("❌ Image selection failed: $e");
    }
  }

  Future<void> getCurrentLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception("❌ Location permission denied");
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final city =
          placemarks.isNotEmpty
              ? placemarks.first.locality ?? 'Unknown'
              : 'Unknown';

      setState(() {
        locationController.text = city;
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (e) {
      debugPrint("❌ Failed to get location: $e");
      locationController.text = 'Unknown';
    }
  }

  Future<String> encodeImageToBase64(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return base64Encode(bytes);
  }

  // Future<void> uploadMemory() async {
  //   debugPrint("🟡 Upload started");

  //   if (_selectedImage == null) {
  //     _showSnackBar("❗ Please select an image.");
  //     debugPrint("❌ No image selected");
  //     return;
  //   }

  //   if (captionController.text.trim().isEmpty ||
  //       locationController.text.trim().isEmpty) {
  //     _showSnackBar("⚠️ Please enter a caption and location.");
  //     debugPrint("⚠️ Caption or location is empty");
  //     return;
  //   }

  //   setState(() => isLoading = true);

  //   try {
  //     final user = FirebaseAuth.instance.currentUser;
  //     if (user == null) throw Exception("❌ User not authenticated");

  //     final locationInput = locationController.text.trim();
  //     debugPrint("📍 Location input: $locationInput");

  //     double finalLat, finalLng;
  //     String country = "Unknown";
  //     String state = "Unknown";
  //     String city = "Unknown";
  //     String place = locationInput.split(',').first.trim();

  //     try {
  //       final locationList = await locationFromAddress(locationInput);
  //       finalLat = locationList.first.latitude;
  //       finalLng = locationList.first.longitude;
  //       debugPrint("✅ Geocoded coordinates: ($finalLat, $finalLng)");

  //       final placemarks = await placemarkFromCoordinates(finalLat, finalLng);
  //       if (placemarks.isNotEmpty) {
  //         final mark = placemarks.first;
  //         country = mark.country ?? "Unknown";
  //         state = mark.administrativeArea ?? "Unknown";
  //         city = mark.locality ?? mark.subAdministrativeArea ?? "Unknown";
  //         place = mark.name?.isNotEmpty == true ? mark.name! : place;
  //         debugPrint(
  //           "📌 Placemark - Place: $place, State: $state, Country: $country",
  //         );
  //       }
  //     } catch (e) {
  //       debugPrint("⚠️ Geocoding failed: $e");

  //       if (_lat != null && _lng != null) {
  //         finalLat = _lat!;
  //         finalLng = _lng!;
  //         debugPrint("🗺️ Using fallback _lat/_lng: ($finalLat, $finalLng)");
  //       } else {
  //         throw Exception("❌ Unable to determine location coordinates.");
  //       }
  //     }

  //     final base64Image = await encodeImageToBase64(_selectedImage!);
  //     debugPrint("🖼️ Image encoded to base64 (length: ${base64Image.length})");

  //     final photo = PhotoModel(
  //       uid: user.uid,
  //       caption: captionController.text.trim(),
  //       location: locationInput,
  //       timestamp: DateTime.now(),
  //       lat: finalLat,
  //       lng: finalLng,
  //       isPublic: isPublic,
  //       place: place,
  //     );

  //     debugPrint("📤 Preparing to upload to Firestore/Realtime DB...");

  //     // final docRef =
  //     //     FirebaseFirestore.instance
  //     //         .collection('photos')
  //     //         .doc(place)
  //     //         .collection('photos')
  //     //         .doc(); // generate unique ID

  //     final sanitizedPlace = place.replaceAll(
  //       '/',
  //       '_',
  //     ); // avoid invalid Firestore IDs
  //     final docRef =
  //         FirebaseFirestore.instance
  //             .collection('photos')
  //             .doc(
  //               sanitizedPlace,
  //             ) // ✅ Use readable place name like 'S G Balekundri Institute of Technology'
  //             .collection('photos')
  //             .doc();

  //     final imagePath = "images/${docRef.id}";

  //     // Upload image to Realtime DB
  //     await FirebaseDatabase.instance.ref(imagePath).set(base64Image);
  //     debugPrint("✅ Image uploaded to Realtime DB at $imagePath");

  //     // Upload metadata to Firestore
  //     await docRef.set(photo.copyWith(imagePath: imagePath).toMap());
  //     debugPrint("✅ Metadata uploaded to Firestore at ${docRef.path}");

  //     if (context.mounted) {
  //       debugPrint("🏁 Navigating back to HomeScreen...");
  //       Navigator.of(context).pushAndRemoveUntil(
  //         MaterialPageRoute(builder: (_) => const HomeScreen()),
  //         (route) => false,
  //       );
  //     }
  //   } catch (e) {
  //     _showSnackBar("❌ Upload failed: ${e.toString()}");
  //     debugPrint("🔥 Exception during upload: $e");
  //   } finally {
  //     if (mounted) setState(() => isLoading = false);
  //     debugPrint("🟢 Upload process finished");
  //   }
  // }
  Future<void> uploadMemory() async {
    if (_selectedImage == null) {
      _showSnackBar("❗ Please select an image.");
      return;
    }

    if (captionController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty) {
      _showSnackBar("⚠️ Please enter a caption and location.");
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final base64Image = await encodeImageToBase64(_selectedImage!);
      final photoId = FirebaseFirestore.instance.collection('photos').doc().id;
      final imagePath = "images/$photoId";

      await FirebaseDatabase.instance.ref(imagePath).set(base64Image);

      final photo = PhotoModel(
        uid: user.uid,
        caption: captionController.text.trim(),
        location: locationController.text.trim(),
        timestamp: DateTime.now(),
        lat: _lat ?? 0,
        lng: _lng ?? 0,
        isPublic: isPublic,
        place: locationController.text.split(',').first.trim(),
      ).copyWith(imagePath: imagePath);

      await FirebaseFirestore.instance
          .collection("photos")
          .doc(photoId)
          .set(photo.toMap());

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      _showSnackBar("❌ Upload failed: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<String>> fetchNominatimSuggestions(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
    );

    final response = await http.get(
      url,
      headers: {'User-Agent': 'FlutterApp/1.0 (yourname@example.com)'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      return data.map((item) => item['display_name'] as String).toList();
    } else {
      throw Exception('Failed to load suggestions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Memory")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: pickImage,
              child:
                  _selectedImage != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _selectedImage!,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      )
                      : Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.grey[300],
                        ),
                        child: const Center(
                          child: Text("📷 Tap to select image"),
                        ),
                      ),
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: captionController,
              label: "Caption",
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TypeAheadField<String>(
              suggestionsCallback: fetchNominatimSuggestions,
              itemBuilder: (context, String suggestion) {
                return ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(suggestion),
                );
              },
              onSelected: (String suggestion) {
                debugPrint("📍 Suggestion selected: $suggestion");
                locationController.text = suggestion;
                fieldTextEditingController?.text = suggestion;
                debugPrint(
                  "📝 locationController updated to: ${locationController.text}",
                );
              },
              builder: (context, controller, focusNode) {
                fieldTextEditingController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: isPublic,
              title: const Text("Make this memory public"),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) => setState(() => isPublic = val ?? true),
            ),
            const SizedBox(height: 24),
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : PrimaryButton(text: "Upload Memory", onPressed: uploadMemory),
          ],
        ),
      ),
    );
  }
}

// import 'dart:convert';
// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_typeahead/flutter_typeahead.dart';
// import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:firebase_auth/firebase_auth.dart';

// import 'package:memscape/services/firestore_service.dart';
// import '../../models/photo_model.dart';
// import '../../widgets/custom_textfield.dart';
// import '../../widgets/primary_button.dart';

// // ... (imports unchanged)

// class UploadPhotoScreen extends ConsumerStatefulWidget {
//   const UploadPhotoScreen({super.key});

//   @override
//   ConsumerState<UploadPhotoScreen> createState() => _UploadPhotoScreenState();
// }

// class _UploadPhotoScreenState extends ConsumerState<UploadPhotoScreen> {
//   File? _selectedImage;
//   final captionController = TextEditingController();
//   final locationController = TextEditingController();

//   /// 👇 Add this to sync TypeAhead input and our own controller
//   TextEditingController? fieldTextEditingController;

//   bool isLoading = false;
//   final picker = ImagePicker();
//   double? _lat;
//   double? _lng;
//   bool isPublic = true;

//   @override
//   void initState() {
//     super.initState();
//     getCurrentLocation();
//   }

//   Future<void> pickImage() async {
//     try {
//       final picked = await picker.pickImage(source: ImageSource.gallery);
//       if (picked != null) {
//         final file = File(picked.path);
//         final sizeInMB = await file.length() / (1024 * 1024);
//         if (sizeInMB > 5) {
//           _showSnackBar("❌ Image too large. Please pick one under 5MB.");
//           return;
//         }
//         setState(() => _selectedImage = file);
//       } else {
//         _showSnackBar("⚠️ No image selected.");
//       }
//     } catch (e) {
//       _showSnackBar("❌ Image selection failed: $e");
//     }
//   }

//   Future<void> getCurrentLocation() async {
//     try {
//       final permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied ||
//           permission == LocationPermission.deniedForever) {
//         throw Exception("❌ Location permission denied");
//       }

//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );
//       final placemarks = await placemarkFromCoordinates(
//         position.latitude,
//         position.longitude,
//       );
//       final city =
//           placemarks.isNotEmpty
//               ? placemarks.first.locality ?? 'Unknown'
//               : 'Unknown';

//       setState(() {
//         locationController.text = city;
//         _lat = position.latitude;
//         _lng = position.longitude;
//       });
//     } catch (e) {
//       debugPrint("❌ Failed to get location: $e");
//       locationController.text = 'Unknown';
//     }
//   }

//   Future<String> encodeImageToBase64(File imageFile) async {
//     final bytes = await imageFile.readAsBytes();
//     return base64Encode(bytes);
//   }

//   Future<void> uploadMemory() async {
//     if (_selectedImage == null) {
//       _showSnackBar("❗ Please select an image.");
//       return;
//     }

//     if (captionController.text.trim().isEmpty ||
//         locationController.text.trim().isEmpty) {
//       _showSnackBar("⚠️ Please enter a caption and location.");
//       return;
//     }

//     setState(() => isLoading = true);

//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) throw Exception("❌ User not authenticated");

//       final locationInput = locationController.text.trim();
//       double finalLat, finalLng;
//       String country = "Unknown";
//       String state = "Unknown";
//       String city = "Unknown";
//       String place = locationInput.split(',').first.trim(); // fallback

//       try {
//         final locationList = await locationFromAddress(locationInput);
//         finalLat = locationList.first.latitude;
//         finalLng = locationList.first.longitude;

//         final placemarks = await placemarkFromCoordinates(finalLat, finalLng);
//         if (placemarks.isNotEmpty) {
//           final mark = placemarks.first;
//           country = mark.country ?? "Unknown";
//           state = mark.administrativeArea ?? "Unknown";
//           city = mark.locality ?? mark.subAdministrativeArea ?? "Unknown";
//           if (mark.name != null && mark.name!.isNotEmpty) {
//             place = mark.name!;
//           }
//         }
//       } catch (_) {
//         if (_lat != null && _lng != null) {
//           finalLat = _lat!;
//           finalLng = _lng!;
//         } else {
//           throw Exception("❌ Unable to determine location coordinates.");
//         }
//       }

//       final base64Image = await encodeImageToBase64(_selectedImage!);

//       final photo = PhotoModel(
//         uid: user.uid,
//         imageBase64: base64Image, // add this
//         caption: captionController.text.trim(),
//         location: locationInput,
//         timestamp: DateTime.now(),
//         lat: finalLat,
//         lng: finalLng,
//         isPublic: isPublic,
//       );

//       // Build dynamic nested path
//       final docPath = "photos/$country/$state/$city/$place";
//       await FirebaseFirestore.instance.collection(docPath).add(photo.toMap());
//       // ✅ Now no arguments passed

//       if (mounted) {
//         Navigator.pop(context);
//         _showSnackBar("✅ Memory uploaded successfully!");
//       }
//     } catch (e) {
//       _showSnackBar("❌ Upload failed: ${e.toString()}");
//     } finally {
//       if (mounted) setState(() => isLoading = false);
//     }
//   }

//   // Future<void> uploadMemory() async {
//   //   if (_selectedImage == null) {
//   //     _showSnackBar("❗ Please select an image.");
//   //     return;
//   //   }

//   //   if (captionController.text.trim().isEmpty ||
//   //       locationController.text.trim().isEmpty) {
//   //     _showSnackBar("⚠️ Please enter a caption and location.");
//   //     return;
//   //   }

//   //   setState(() => isLoading = true);

//   //   try {
//   //     final user = FirebaseAuth.instance.currentUser;
//   //     if (user == null) throw Exception("❌ User not authenticated");

//   //     final locationInput = locationController.text.trim();
//   //     double finalLat, finalLng;

//   //     try {
//   //       final locationList = await locationFromAddress(locationInput);
//   //       finalLat = locationList.first.latitude;
//   //       finalLng = locationList.first.longitude;
//   //     } catch (_) {
//   //       if (_lat != null && _lng != null) {
//   //         finalLat = _lat!;
//   //         finalLng = _lng!;
//   //       } else {
//   //         throw Exception("❌ Unable to determine location coordinates.");
//   //       }
//   //     }

//   //     final base64Image = await encodeImageToBase64(_selectedImage!);

//   //     // Only metadata goes into Firestore
//   //     final photo = PhotoModel(
//   //       uid: user.uid,
//   //       caption: captionController.text.trim(),
//   //       location: locationInput,
//   //       timestamp: DateTime.now(),
//   //       lat: finalLat,
//   //       lng: finalLng,
//   //       isPublic: isPublic,
//   //     );

//   //     await FirestoreService().uploadPhoto(photo, base64Image);
//   //     if (mounted) {
//   //       Navigator.pop(context);
//   //       _showSnackBar("✅ Memory uploaded successfully!");
//   //     }
//   //   } catch (e) {
//   //     _showSnackBar("❌ Upload failed: ${e.toString()}");
//   //   } finally {
//   //     if (mounted) setState(() => isLoading = false);
//   //   }
//   // }

//   void _showSnackBar(String message) {
//     ScaffoldMessenger.of(
//       context,
//     ).showSnackBar(SnackBar(content: Text(message)));
//   }

//   Future<List<String>> fetchNominatimSuggestions(String query) async {
//     final url = Uri.parse(
//       'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
//     );

//     final response = await http.get(
//       url,
//       headers: {'User-Agent': 'FlutterApp/1.0 (yourname@example.com)'},
//     );

//     if (response.statusCode == 200) {
//       final data = json.decode(response.body) as List;
//       return data.map((item) => item['display_name'] as String).toList();
//     } else {
//       throw Exception('Failed to load suggestions');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Upload Memory")),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(24),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             GestureDetector(
//               onTap: pickImage,
//               child:
//                   _selectedImage != null
//                       ? ClipRRect(
//                         borderRadius: BorderRadius.circular(16),
//                         child: Image.file(
//                           _selectedImage!,
//                           height: 220,
//                           width: double.infinity,
//                           fit: BoxFit.cover,
//                         ),
//                       )
//                       : Container(
//                         height: 220,
//                         width: double.infinity,
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(16),
//                           color: Colors.grey[300],
//                         ),
//                         child: const Center(
//                           child: Text("📷 Tap to select image"),
//                         ),
//                       ),
//             ),
//             const SizedBox(height: 20),
//             CustomTextField(
//               controller: captionController,
//               label: "Caption",
//               maxLines: 2,
//             ),
//             const SizedBox(height: 12),
//             // CustomTextField(controller: locationController, label: "Location"),
//             TypeAheadField<String>(
//               suggestionsCallback: (String query) async {
//                 final url = Uri.parse(
//                   'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
//                 );
//                 final response = await http.get(
//                   url,
//                   headers: {
//                     'User-Agent': 'FlutterApp/1.0 (yourname@example.com)',
//                   },
//                 );
//                 if (response.statusCode == 200) {
//                   final data = json.decode(response.body) as List;
//                   return data
//                       .map((item) => item['display_name'] as String)
//                       .toList();
//                 } else {
//                   return [];
//                 }
//               },
//               itemBuilder: (context, String suggestion) {
//                 return ListTile(
//                   leading: const Icon(Icons.location_on),
//                   title: Text(suggestion),
//                 );
//               },
//               // onSelected: (String suggestion) {
//               //   locationController.text = suggestion;
//               //   // Add this to update visible field too
//               //   fieldTextEditingController?.text = suggestion;
//               // },
//               onSelected: (String suggestion) {
//                 debugPrint("📍 Suggestion selected: $suggestion");
//                 locationController.text = suggestion;
//                 fieldTextEditingController?.text =
//                     suggestion; // ✅ Update visible field
//                 debugPrint(
//                   "📝 locationController updated to: ${locationController.text}",
//                 );
//               },

//               builder: (context, fieldTextEditingController, focusNode) {
//                 // Keep reference for later use in onSelected
//                 this.fieldTextEditingController = fieldTextEditingController;

//                 return TextField(
//                   controller: fieldTextEditingController,
//                   focusNode: focusNode,
//                   decoration: const InputDecoration(
//                     labelText: 'Location',
//                     border: OutlineInputBorder(),
//                   ),
//                 );
//               },
//             ),

//             const SizedBox(height: 12),
//             CheckboxListTile(
//               contentPadding: EdgeInsets.zero,
//               value: isPublic,
//               title: const Text("Make this memory public"),
//               controlAffinity: ListTileControlAffinity.leading,
//               onChanged: (val) => setState(() => isPublic = val ?? true),
//             ),
//             const SizedBox(height: 24),
//             isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : PrimaryButton(text: "Upload Memory", onPressed: uploadMemory),
//           ],
//         ),
//       ),
//     );
//   }
// }
