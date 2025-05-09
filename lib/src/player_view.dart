import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../tezda_ios_player.dart';

class NativeVideoWidget extends StatefulWidget {
  final String url;
  final bool shouldMute;
  final bool isLandscape;
  final Widget? placeholder;

  const NativeVideoWidget({
    super.key,
    required this.url,
    required this.shouldMute,
    required this.isLandscape,
    this.placeholder,
  });

  @override
  State<NativeVideoWidget> createState() => _NativeVideoWidgetState();
}

class _NativeVideoWidgetState extends State<NativeVideoWidget> {
  @override
  void initState() {
    NativeVideoController.onUpdateStream.listen(
      (event) => mounted ? setState(() {}) : null,
    );
    super.initState();
  }

  bool shouldPlayVideo = false;
  @override
  Widget build(BuildContext context) => Stack(
        children: [
          VisibilityDetector(
            key: Key(widget.url),
            onVisibilityChanged: (info) {
              if (info.visibleFraction < .1) {
                shouldPlayVideo = false;
              }
              if (info.visibleFraction > .9) {
                shouldPlayVideo = true;
              }
              mounted ? setState(() {}) : null;
            },
            child: shouldPlayVideo
                ? UiKitView(
                    viewType: 'native_video_player',
                    creationParams: {
                      'url': widget.url,
                      'shouldMute': widget.shouldMute,
                      'isLandscape': widget.isLandscape,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : widget.placeholder ?? const SizedBox(),
          ),
          if (!NativeVideoController.isPlaying)
            Positioned.fill(child: widget.placeholder ?? const SizedBox()),
        ],
      );
}
