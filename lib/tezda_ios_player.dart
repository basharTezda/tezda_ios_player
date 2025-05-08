import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tezda_ios_player/controller.dart';

export 'package:tezda_ios_player/tezda_ios_player.dart';
export 'package:tezda_ios_player/controller.dart';

class NativeVideoWidget extends StatelessWidget {
  final List<String> urls;  // Accept a list of URLs
  final NativeVideoController controller;
  final bool shouldMute;
  final bool isLandscape;

  const NativeVideoWidget({
    super.key,
    required this.urls,
    required this.controller,
    required this.shouldMute,
    required this.isLandscape,
  });


  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'native_video_player',
      creationParams: {'urls': urls},  // Pass the list of URLs
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
