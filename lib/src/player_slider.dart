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
    if (NativeVideoController.duration.inSeconds < 10) {
      return Container();
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width +40,),
      child: Stack(
        // fit: StackFit.passthrough,
        children: [
          FlutterSlider(
            values: [
              NativeVideoController.buffered.inMicroseconds.ceilToDouble(),
            ],
            max: NativeVideoController.duration.inMicroseconds.ceilToDouble(),
            min: 0,
            handler: FlutterSliderHandler(
              opacity: 0,
              // disabled: true,
            ),
            trackBar: FlutterSliderTrackBar(
              activeTrackBar: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
              inactiveTrackBar: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          FlutterSlider(
            onDragStarted: (handlerIndex, lowerValue, upperValue) {
              NativeVideoController().pause();
            },
            onDragCompleted: (handlerIndex, lowerValue, upperValue) {
              NativeVideoController().play();
            },
            values: [
              NativeVideoController.currentTime.inMicroseconds.ceilToDouble(),
            ],
            max: NativeVideoController.duration.inMicroseconds.ceilToDouble(),
            min: 0,
            handler: FlutterSliderHandler(
              opacity: 0,
              // disabled: true,
              child: Icon(Icons.circle, size: 5),
            ),
            trackBar: FlutterSliderTrackBar(
              activeTrackBar: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              inactiveTrackBar: BoxDecoration(
                color: Colors.grey.withOpacity(0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            tooltip: FlutterSliderTooltip(
              custom: (value) {
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_formatDuration(NativeVideoController.currentTime)} / ${_formatDuration(NativeVideoController.duration)}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
            onDragging: (handlerIndex, lowerValue, upperValue) {
              NativeVideoController.seekTo(lowerValue / 1000000);
            },
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
