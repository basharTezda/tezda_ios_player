import 'package:flutter/material.dart';
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
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Slider(
        thumbColor: Colors.red.withOpacity(0.0),
        // padding: EdgeInsets.all(0),
        activeColor: Color.fromRGBO(255, 255, 255, 1),
        inactiveColor: Colors.transparent,
        secondaryTrackValue: (NativeVideoController.buffered.inMicroseconds /
                    NativeVideoController.duration.inMicroseconds) >
                1
            ? 1
            : NativeVideoController.buffered.inMicroseconds /
                NativeVideoController.duration.inMicroseconds,
        secondaryActiveColor: Colors.grey,
        value: NativeVideoController.currentTime.inMicroseconds /

            NativeVideoController.duration.inMicroseconds,
        onChanged: (double value) {
          NativeVideoController.seekTo(
            value * NativeVideoController.duration.inMicroseconds / 1000000,
          );

        },
      ),
    );
  }
}
