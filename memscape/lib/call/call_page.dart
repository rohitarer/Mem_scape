import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../zego_config.dart';

class CallPage extends StatelessWidget {
  final String callID; // room / call ID both users join
  final String userID; // unique per user
  final String userName; // display name
  final bool video; // true = video call, false = voice call

  const CallPage({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    this.video = true,
  });

  @override
  Widget build(BuildContext context) {
    final config =
        video
            ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();

    return ZegoUIKitPrebuiltCall(
      appID: ZegoConfig.appID,
      appSign: ZegoConfig.appSign,
      userID: userID,
      userName: userName,
      callID: callID,
      config:
          config
            ..turnOnCameraWhenJoining = video
            ..turnOnMicrophoneWhenJoining = true
            ..avatarBuilder = (context, size, user, extra) {
              // optional: show your chat avatars here
              return CircleAvatar(
                radius: size.width / 2,
                backgroundColor: Colors.grey.shade300,
                child: Text(
                  (user?.name ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            },
    );
  }
}
