import 'package:flutter/material.dart';

class LiveStubPage extends StatelessWidget {
  const LiveStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.videocam),
          label: const Text("Start Live (coming soon)"),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Integrate WebRTC/Agora here. We'll wire auth/room later.",
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
