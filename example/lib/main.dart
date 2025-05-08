import 'package:flutter/material.dart';
import 'package:tezda_ios_player/tezda_ios_player.dart';

import 'const.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Video Player Demo',
      home: VideoExampleScreen(),
    );
  }
}

class VideoExampleScreen extends StatelessWidget {
  VideoExampleScreen({super.key});
  final controller = NativeVideoController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          NativeVideoWidget(controller: controller, urls: videos),

          // Positioned.fill(
          //   child: GestureDetector(
          //     onTap: () async => await controller.togglePlayPause(),
          //     behavior: HitTestBehavior.translucent, // 👈 VERY important!
          //     child: const SizedBox(), // transparent layer
          //   ),
          // ),
          // Positioned(
          //   right: 20,
          //   bottom: 100,
          //   child: IconButton(
          //     icon: const Icon(Icons.volume_up, color: Colors.white),
          //     onPressed: () => controller.toggleMute(),
          //   ),
          // ),
        ],
      ),
    );
  }
}

String extractIdFromUrl(String videoUrl) {
  // Extract the video ID using regular expression
  final RegExp regExp = RegExp(r"\/video\/([a-f0-9]+)\.mp4");
  final match = regExp.firstMatch(videoUrl);

  // Return the extracted ID
  if (match != null && match.groupCount > 0) {
    return match.group(1)!;
  }

  return ""; // Return an empty string if no match is found
}

String generateThumbnailUrl(String videoUrl) {
  String videoId = extractIdFromUrl(videoUrl);
  if (videoId.isNotEmpty) {
    // Construct the new thumbnail URL
    return "https://media.tezda.com/thumbnail/$videoId.jpg";
  }
  return ""; // Return an empty string if no ID was extracted
}

void preloadImage(String imageUrl, BuildContext context) {
  // Create an ImageProvider
  final imageProvider = NetworkImage(imageUrl);

  // Preload the image into the cache
  precacheImage(imageProvider, context);
}
