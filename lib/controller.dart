import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';

class NativeVideoController {
  static const MethodChannel _channel = MethodChannel(
    'native_video_player_channel',
  );
  static const EventChannel _eventChannel = EventChannel(
    'native_video_player_event',
  );

  static Duration currentTime = Duration(microseconds: 0);
  static Duration duration = Duration(microseconds: 1);
  static Duration buffured = Duration(microseconds: 0);
  static bool isPlaying = false;
  static Stream<Map> get onUpdate {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event['started'] != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          isPlaying = event['started'];
        });
      }
      if (event['currentTime'] != null) {
        currentTime = setUpMicro(event['currentTime']);
      }
      if (event['duration'] != null) {
        duration = setUpMicro(event['duration']);
        return {};
      }
      if (event['buffering'] != null) {
        buffured = setUpMicro(event['buffering']);
        return {};
      }

      return {};
    });
  }

  Future<void> togglePlayPause() async {
    await _channel.invokeMethod('togglePlay');
  }

  Future<void> toggleMute() async {
    await _channel.invokeMethod('toggleMute');
  }

  Future<void> seekTo(double seconds) async {
    try {
      await _channel.invokeMethod('seekTo', {'time': seconds});
    } on PlatformException catch (e) {
      log('Error seeking to $seconds: ${e.message}');
    }
  }

  static Duration setUpMicro(double duration) {
    return Duration(microseconds: (duration * 1000000).toInt());
  }

  static Future<void> reset() async {
    currentTime = Duration(microseconds: 0);
    duration = Duration(microseconds: 1);
    buffured = Duration(microseconds: 0);
    isPlaying = false;
  }
}
