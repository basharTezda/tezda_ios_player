
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tezda_ios_player/controller.dart';
export 'package:tezda_ios_player/tezda_ios_player.dart';
export 'package:tezda_ios_player/controller.dart';
class NativeVideoWidget extends StatelessWidget {
  final String url;
  final NativeVideoController controller;

  const NativeVideoWidget({
    super.key,
    required this.url,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UiKitView(
          viewType: 'native_video_player',
          creationParams: {'url': url},
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ],
    );
  }
}
