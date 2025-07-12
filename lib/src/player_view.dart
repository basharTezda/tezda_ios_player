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
      required this.shouldShow});

  @override
  State<NativeVideoWidget> createState() => _NativeVideoWidgetState();
}

class _NativeVideoWidgetState extends State<NativeVideoWidget> {
  @override
  void initState() {
    log(widget.url,name: "NativeVideoWidget");
    NativeVideoController.onUpdateStream.listen(
      (event) => mounted ? setState(() {}) : null,
    );
    super.initState();
  }

  final NativeVideoController controller = NativeVideoController();
  bool shouldPlayVideo = false;
  @override
  Widget build(BuildContext context) => widget.shouldShow
      ? UiKitView(
          viewType: 'native_video_player',
          creationParams: {
            'url': widget.url,
            'shouldMute': widget.shouldMute,
            'isLandscape': widget.isLandscape,
            "preLoadUrls": takeOnlyFive(
                removedItem: widget.url, list: widget.preloadUrl ?? []),
          },
          creationParamsCodec: const StandardMessageCodec(),
        )
      : Container(
          color: Colors.transparent,
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
