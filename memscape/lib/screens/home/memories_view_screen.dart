import 'dart:convert';

import 'package:flutter/material.dart';

class MemoriesViewScreen extends StatelessWidget {
  final String photoBase64;

  const MemoriesViewScreen({super.key, required this.photoBase64});

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(photoBase64);

    return Scaffold(
      appBar: AppBar(title: const Text("My Memory")),
      body: Center(child: Image.memory(imageBytes)),
    );
  }
}
