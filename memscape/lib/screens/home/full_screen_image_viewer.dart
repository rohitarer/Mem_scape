import 'package:flutter/material.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/widgets/photo_card.dart';

class FullscreenImageViewer extends StatefulWidget {
  final List<PhotoModel> photos;
  final int initialIndex;

  const FullscreenImageViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late PageController _controller;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffsetY += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_dragOffsetY.abs() > 150) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffsetY = 0); // Recenter if not dismissed
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dragPercent = (_dragOffsetY / screenHeight).clamp(-1.0, 1.0);
    final scale = 1.0 - dragPercent.abs() * 0.4; // shrink up to 0.6
    final opacity = 1.0 - dragPercent.abs() * 0.9;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(opacity.clamp(0.0, 1.0)),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        itemBuilder: (context, index) {
          final photo = widget.photos[index];

          return GestureDetector(
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                transform:
                    Matrix4.identity()
                      ..translate(0.0, _dragOffsetY)
                      ..scale(scale.clamp(0.6, 1.0)),
                curve: Curves.easeOut,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.95,
                    maxWidth: MediaQuery.of(context).size.width * 0.95,
                  ),
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: PhotoCard(photo: photo),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
