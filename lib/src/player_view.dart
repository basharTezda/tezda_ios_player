import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../tezda_ios_player.dart';

class NativeVideoWidget extends StatefulWidget {
  final String url;
  final bool shouldMute;
  final bool isLandscape;
  final Widget? placeholder;
  final String? preloadUrl;
  final Function(TapDownDetails)? onDoubleTapDown;
  final Function()? onLongPressStart;
  final Function()? onLongPressEnd;
  final Function(VisibilityInfo)? onVisibilityChanged;
  const NativeVideoWidget(
      {super.key,
      required this.url,
      required this.shouldMute,
      required this.isLandscape,
      this.placeholder,
      this.preloadUrl,
      this.onDoubleTapDown,
      this.onLongPressStart,
      this.onVisibilityChanged,
      this.onLongPressEnd});

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

  final NativeVideoController controller = NativeVideoController();
  bool shouldPlayVideo = false;
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black,
        child: Stack(
          children: [
            VisibilityDetector(
              key: Key(widget.url),
              onVisibilityChanged: (info) {
                if (widget.onVisibilityChanged != null) {
                  widget.onVisibilityChanged?.call(info);
                }

                if (info.visibleFraction < .1) {
                  shouldPlayVideo = false;
                  controller.pause();
                }
                if (info.visibleFraction > .9) {
                  shouldPlayVideo = true;
                  controller.play();
                }
                // log("Visibility fraction: ${info.visibleFraction}");
                mounted ? setState(() {}) : null;
              },
              child: shouldPlayVideo
                  ? UiKitView(
                      viewType: 'native_video_player',
                      creationParams: {
                        'url': widget.url,
                        'shouldMute': widget.shouldMute,
                        'isLandscape': widget.isLandscape,
                        "preLoadUrl": widget.preloadUrl ?? widget.url,
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                    )
                  : widget.placeholder ?? Container(),

              // const SizedBox(
            ),
            if (!NativeVideoController.isReady)
              Positioned.fill(child: widget.placeholder ?? const SizedBox()),
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: (d) => widget.onDoubleTapDown?.call(d),
                onLongPressStart: (d) => widget.onLongPressStart?.call(),
                onLongPressEnd: (d) => widget.onLongPressEnd?.call(),
                onTap: () async => !NativeVideoController.isPlaying
                    ? await controller.play()
                    : await controller.pause(),
                behavior: HitTestBehavior.translucent,
                child: const SizedBox(), // transparent layer
              ),
            ),
          ],
        ),
      );
}
