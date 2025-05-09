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
    return Slider(
      activeColor: Color.fromRGBO(255, 255, 255, 1),
      inactiveColor: Colors.transparent,
      secondaryTrackValue:
          (NativeVideoController.buffered.inMicroseconds /
                      NativeVideoController.duration.inMicroseconds) >
                  1
              ? 1
              : NativeVideoController.buffered.inMicroseconds /
                  NativeVideoController.duration.inMicroseconds,
      secondaryActiveColor: Colors.grey,

      value:
          NativeVideoController.currentTime.inMicroseconds /
          NativeVideoController.duration.inMicroseconds,

      // label: _currentDiscreteSliderValue.round().toString(),
      onChanged: (double value) {
        // setState(() {
        //   _sliderValue = value;
        NativeVideoController.seekTo(
          value * NativeVideoController.duration.inMicroseconds / 1000000,
        );
        // );
        // log( "value: $value");
        // _currentDiscreteSliderValue = value;
        // });
      },
    );
  }
}
