import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:developer';
import 'package:flutter/foundation.dart';
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
  static Duration buffered = Duration(microseconds: 0);
  static bool isPlaying = false;
  static bool isReady = false;
  static bool isFinished = false;
  final List<String> _cachedUrls = [];
  final int _maxCacheSize = 5;
  // Stream to listen for updates from the native side
  static Stream<Map> onUpdateStream =
      _eventChannel.receiveBroadcastStream().map((data) {
    final event = _extractMessage(data['event']);
    if (event['started'] != null) {
      isReady = event['started'];
    }
    if (event['isPlaying'] != null) {
      isPlaying = event['isPlaying'];
    }
    if (event['currentTime'] != null) {
      currentTime = setUpMicro(event['currentTime']);
    }
    if (event['duration'] != null) {
      duration = setUpMicro(event['duration']);
    }
    if (event['buffering'] != null) {
      buffered = setUpMicro(event['buffering']);
    }
    if (currentTime.inSeconds != 0 &&
        currentTime.inSeconds == duration.inSeconds &&
        isReady &&
        !isFinished) {
      isFinished = true;
    }
    if (event['message'] != null) {
      log(event .toString());
    }

    return event;
  });

  Future<void> preCacheVideos(List<String> urls) async {
    try {
      // Keep only the last X videos to prevent excessive caching
      // if (_cachedUrls.length > _maxCacheSize) {
      //   final urlsToRemove = _cachedUrls.sublist(0, _cachedUrls.length - _maxCacheSize);
      //   await _channel.invokeMethod('removeCachedVideos', {'urls': urlsToRemove});
      //   _cachedUrls.removeWhere((url) => urlsToRemove.contains(url));
      // }

      // Cache new videos
      final newUrls = urls.where((url) => !_cachedUrls.contains(url)).toList();
      if (newUrls.isNotEmpty) {
        await _channel.invokeMethod('cacheVideoList', {'urls': newUrls});
        _cachedUrls.addAll(newUrls);
      }
    } catch (e) {
      debugPrint('Error caching videos: $e');
    }
  }

  Future<void> togglePlayPause() async {
    await _channel.invokeMethod('togglePlay');
  }

  Future<void> toggleMute() async {
    await _channel.invokeMethod('toggleMute');
  }

  Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  static Future<void> seekTo(double seconds) async {
    try {
      await _channel.invokeMethod('seekTo', {'time': seconds});
    } on PlatformException catch (e) {
      log('Error seeking to $seconds: ${e.message}');
    }
  }

  static Duration setUpMicro(dynamic duration) {
    try {
      return Duration(microseconds: (duration * 1000000).toInt());
    } catch (e) {
      return Duration(microseconds: 0);
    }
  }

  static Future<void> reset() async {
    currentTime = Duration(microseconds: 0);
    duration = Duration(microseconds: 1);
    buffered = Duration(microseconds: 0);
    isPlaying = false;
    isReady = false;
    isFinished = false;
  }

  static _extractMessage(data) {
    return _convertToObject(data.toString());
  }

  static Map<String, dynamic> _convertToObject(String str) {
    try {
      Map<String, dynamic> myMap =
          jsonDecode(str.replaceAll("[", "{").replaceAll("]", "}"));
      return myMap;
    } catch (e) {
      return {"error": e.toString()};
    }
  }
}
