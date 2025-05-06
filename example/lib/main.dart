import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:tezda_ios_player/controller.dart';
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
  const VideoExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final controller = NativeVideoController();
          return Stack(
            children: [
              NativeVideoWidget(
                url: videos[index].toString(),
                controller: controller,
              ),

              Positioned.fill(
                child: GestureDetector(
                  onTap: () async => await controller.togglePlayPause(),
                  behavior: HitTestBehavior.translucent, // 👈 VERY important!
                  child: const SizedBox(), // transparent layer
                ),
              ),
              Positioned(
                right: 20,
                bottom: 100,
                child: IconButton(
                  icon: const Icon(Icons.volume_up, color: Colors.white),
                  onPressed: () => controller.toggleMute(),
                ),
              ),
            ],
          );
      
        },
      ),
    );
  }
}
