import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_xlider/flutter_xlider.dart';
import 'player_controller.dart';

class NativeVideoSlider extends StatefulWidget {
  const NativeVideoSlider({super.key});

  @override
  State<NativeVideoSlider> createState() => __NativeVideoSliderStateState();
}

class __NativeVideoSliderStateState extends State<NativeVideoSlider> {
  @override
  void initState() {
    NativeVideoController.onUpdateStream.listen(
      (event) => mounted ? setState(() {}) : null,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterSlider(
      values: [NativeVideoController.currentTime.inMicroseconds.ceilToDouble(),NativeVideoController.buffered.inMicroseconds.ceilToDouble()],
      max: NativeVideoController.duration.inMicroseconds.ceilToDouble(),
      min: 0,
      handler: FlutterSliderHandler(
        opacity: 0,
        disabled: true,
        child: Icon(Icons.circle, size: 5),
      ),
      trackBar: FlutterSliderTrackBar(
        activeTrackBar: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(4)),
        inactiveTrackBar: BoxDecoration(
            color: Colors.grey, borderRadius: BorderRadius.circular(4)),
      ),
      onDragging: (handlerIndex, lowerValue, upperValue) {
        log(lowerValue.toString());
        // Call Swift native code via MethodChannel
        // _channel.invokeMethod('seekTo', {'progress': lowerValue});
      },

      // thumbColor: Colors.red.withOpacity(0.0),
      // // padding: EdgeInsets.all(0),
      // activeColor: Color.fromRGBO(255, 255, 255, 1),
      // inactiveColor: Colors.transparent,
      // secondaryTrackValue: (NativeVideoController.buffered.inMicroseconds /
      //             NativeVideoController.duration.inMicroseconds) >
      //         1
      //     ? 1
      //     : NativeVideoController.buffered.inMicroseconds /
      //         NativeVideoController.duration.inMicroseconds,
      // secondaryActiveColor: Colors.grey,
      // value: NativeVideoController.currentTime.inMicroseconds /

      //     NativeVideoController.duration.inMicroseconds,
      // onChanged: (double value) {
      //   NativeVideoController.seekTo(
      //     value * NativeVideoController.duration.inMicroseconds / 1000000,
      //   );

      // },
    );
  }
}
