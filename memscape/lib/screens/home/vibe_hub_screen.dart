import 'package:flutter/material.dart';
import 'chats_screen.dart';
import 'pings_screen.dart';

class VibeHubScreen extends StatelessWidget {
  const VibeHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("💬 Vibe Hub"),
          bottom: const TabBar(
            isScrollable: false,
            tabs: [
              // Tab(icon: Icon(Icons.forum_rounded), text: "Chats"),
              // Tab(icon: Icon(Icons.bolt_rounded), text: "Pings"),
              Tab(text: "Chats"),
              Tab(text: "Pings"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // 👉 Hooked to your separate screens
            ChatsScreen(),
            PingsScreen(),
          ],
        ),
      ),
    );
  }
}
