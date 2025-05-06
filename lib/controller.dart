import 'dart:async';

import 'package:flutter/services.dart';

class NativeVideoController {
  static const MethodChannel _channel = MethodChannel('native_video_player_channel');

  Future<void> togglePlayPause() async {
    await _channel.invokeMethod('togglePlay');
  }

  Future<void> toggleMute() async {
    await _channel.invokeMethod('toggleMute');
  }
}