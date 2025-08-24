import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final bool isMine;
  final String text;
  final DateTime? createdAt;
  final ImageProvider? avatarProvider; // now used on BOTH sides
  final String? nicknameForA11y;
  final String? replyText;
  final VoidCallback onSwipeReply;

  const MessageBubble({
    super.key,
    required this.isMine,
    required this.text,
    required this.createdAt,
    required this.onSwipeReply,
    this.avatarProvider,
    this.nicknameForA11y,
    this.replyText,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        createdAt != null ? DateFormat('hh:mm a').format(createdAt!) : '';

    final bubbleColor =
        isMine
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceVariant;

    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlign = isMine ? MainAxisAlignment.end : MainAxisAlignment.start;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (replyText != null && replyText!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                replyText!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            timeStr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );

    // Swipe‑to‑reply only on the OTHER person's messages
    final gestureChild =
        isMine
            ? bubble
            : GestureDetector(
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 250) {
                  onSwipeReply();
                }
              },
              child: bubble,
            );

    // 👉 Avatar is shown for BOTH sides now.
    final avatar = CircleAvatar(backgroundImage: avatarProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: rowAlign,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            avatarProvider != null
                ? avatar
                : const SizedBox(width: 32, height: 32),
            const SizedBox(width: 8),
            Flexible(child: gestureChild),
          ] else ...[
            Flexible(child: gestureChild),
            const SizedBox(width: 8),
            avatarProvider != null
                ? avatar
                : const SizedBox(width: 32, height: 32),
          ],
        ],
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';

// class MessageBubble extends StatelessWidget {
//   final bool isMine;
//   final String text;
//   final DateTime? createdAt;
//   final ImageProvider? avatarProvider; // show only for other user
//   final String? nicknameForA11y;
//   final String? replyText;
//   final VoidCallback onSwipeReply;

//   const MessageBubble({
//     super.key,
//     required this.isMine,
//     required this.text,
//     required this.createdAt,
//     required this.onSwipeReply,
//     this.avatarProvider,
//     this.nicknameForA11y,
//     this.replyText,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final timeStr =
//         createdAt != null ? DateFormat('hh:mm a').format(createdAt!) : '';

//     final bubbleColor = isMine
//         ? Theme.of(context).colorScheme.primaryContainer
//         : Theme.of(context).colorScheme.surfaceVariant;

//     final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
//     final rowAlign = isMine ? MainAxisAlignment.end : MainAxisAlignment.start;

//     final bubble = Container(
//       constraints: const BoxConstraints(maxWidth: 320),
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: bubbleColor,
//         borderRadius: BorderRadius.circular(14),
//       ),
//       child: Column(
//         crossAxisAlignment: align,
//         children: [
//           if (replyText != null && replyText!.isNotEmpty)
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//               margin: const EdgeInsets.only(bottom: 6),
//               decoration: BoxDecoration(
//                 color: Theme.of(context).colorScheme.surface.withOpacity(.6),
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(
//                   color: Theme.of(context).colorScheme.outlineVariant,
//                 ),
//               ),
//               child: Text(
//                 replyText!,
//                 maxLines: 2,
//                 overflow: TextOverflow.ellipsis,
//                 style: Theme.of(context)
//                     .textTheme
//                     .bodySmall
//                     ?.copyWith(fontStyle: FontStyle.italic),
//               ),
//             ),
//           Text(
//             text,
//             style: Theme.of(context).textTheme.bodyMedium,
//           ),
//           const SizedBox(height: 6),
//           Text(
//             timeStr,
//             style: Theme.of(context)
//                 .textTheme
//                 .labelSmall
//                 ?.copyWith(color: Theme.of(context).colorScheme.outline),
//           ),
//         ],
//       ),
//     );

//     // Swipe-to-reply only on the other user's messages (isMine == false)
//     final gestureChild = isMine
//         ? bubble
//         : GestureDetector(
//             onHorizontalDragEnd: (details) {
//               // swipe right only (positive velocity) to avoid accidental triggers
//               if ((details.primaryVelocity ?? 0) > 250) {
//                 onSwipeReply();
//               }
//             },
//             child: bubble,
//           );

//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         mainAxisAlignment: rowAlign,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           if (!isMine && avatarProvider != null) ...[
//             CircleAvatar(backgroundImage: avatarProvider),
//             const SizedBox(width: 8),
//           ],
//           Flexible(child: gestureChild),
//           if (isMine) const SizedBox(width: 48), // breathing room for symmetry
//         ],
//       ),
//     );
//   }
// }
