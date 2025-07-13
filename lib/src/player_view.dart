import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../tezda_ios_player.dart';

List<String> cached = [];

class NativeVideoWidget extends StatefulWidget {
  final String url;
  final bool shouldMute;
  final bool isLandscape;
  final Widget? placeholder;
  final List<String>? preloadUrl;
  final Function(TapDownDetails)? onDoubleTapDown;
  final Function()? onLongPressStart;
  final Function()? onLongPressEnd;
  final Function(VisibilityInfo)? onVisibilityChanged;
  final Function()? onDoubleTap;
  final Function(double)? onFinished;
  final Function(double)? onDeinit;

  final bool shouldShow;
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
      this.onLongPressEnd,
      required this.shouldShow,
      this.onDoubleTap,
      this.onFinished,
      this.onDeinit});

  @override
  State<NativeVideoWidget> createState() => _NativeVideoWidgetState();
}

class _NativeVideoWidgetState extends State<NativeVideoWidget> {
  bool _started = false;
  @override
  void initState() {
    NativeVideoController.onUpdateStream.listen(
      (event) => mounted
          ? setState(() {
              if (event['onFinished'] != null && widget.onFinished != null) {
                widget.onFinished?.call(event['duration']);
              }
              if (event['onDeinit'] != null && widget.onDeinit != null) {
                widget.onDeinit?.call(event['duration']);
              }
              if (event['onDoubleTap'] != null && widget.onDoubleTap != null) {
                widget.onDoubleTap?.call();
              }
              if (event["started"] != null) {
                Future.delayed(Duration(milliseconds: 50), () {
                  _started = true;
                });
              }
            })
          : null,
    );
    super.initState();
  }

  // final NativeVideoController controller = NativeVideoController(widget.url);
  bool shouldPlayVideo = false;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            height: 2,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                UiKitView(
                  onPlatformViewCreated: (id) => log("message from native view created $id"),
                  viewType: 'native_video_player',
                  creationParams: {
                    'url': widget.url,
                    'shouldMute': widget.shouldMute,
                    'isLandscape': widget.isLandscape,
                    "preLoadUrls": takeOnlyFive(
                        removedItem: widget.url, list: widget.preloadUrl ?? []),
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                ),
                if (!_started || !widget.shouldShow) widget.placeholder ?? Container(),
              ],
            ),
          ),
        ],
      );
}

List<String> takeOnlyFive(
    {required String removedItem, required List<String> list}) {
  cached.add(removedItem);
  final fixedList = list.toList();
  fixedList.removeWhere((item) => cached.contains(item));
  List<String> firstFive =
      fixedList.length > 2 ? fixedList.sublist(0, 2) : fixedList;
  return firstFive;
}
