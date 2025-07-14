import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:tezda_ios_player/tezda_ios_player.dart';
import 'const.dart';

void main() => runApp(const MyApp());

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

class VideoExampleScreen extends StatefulWidget {
  const VideoExampleScreen({super.key});

  @override
  State<VideoExampleScreen> createState() => _VideoExampleScreenState();
}

class _VideoExampleScreenState extends State<VideoExampleScreen> {
  final controller = NativeVideoController();

  @override
  void initState() {
    // NativeVideoController.cacheVideos(videos);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // if (true) {
    //   return Scaffold(
    //     body: Center(
    //       child: Text(
    //         "This example is not supported on web, please run on iOS or Android",
    //         style: TextStyle(fontSize: 20),
    //       ),
    //     ),
    //   );
    // }
    return Scaffold(
      body: PageView.builder(
        onPageChanged: (value) {
          NativeVideoController.reset();
          setState(() {});
        },
        scrollDirection: Axis.vertical,
        itemCount: videos.length,
        itemBuilder: (context, index) {
          // final randomIndex = true ? index : Random().nextInt(videos.length);
          // final nextVideo = videos[index + 1];
          // preloadImage(generateThumbnailUrl(nextVideo), context);
          final videoUrl = videos.toList()[index];
          return Column(
            children: [
              Expanded(
                child: NativeVideoWidget(
                  onDeinit: (i,n,l) {
                    log("onDeinit called", name: "NativeVideoWidget");
                  },
                  onFinished: (i) {
                    log("onFinished called", name: "NativeVideoWidget");
                  },
                  onDoubleTap: () {
                    log("onDoubleTap called", name: "NativeVideoWidget");
                  },
                  shouldShow: true,
                  url: videoUrl,
                  preloadUrl: videos.toList(),
                  shouldMute: false,
                  isLandscape: false,
                ),
              ),
              Container(
                height: 50,
                color: Colors.transparent,
              )
            ],
          );
        },
      ),
    );
  }
}
