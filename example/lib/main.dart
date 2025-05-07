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
