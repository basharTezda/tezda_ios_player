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

  final controller = NativeVideoController(videos.first);

  @override
  void initState() {

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: 
      PageView.builder(
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
          final videoUrl =  videos.reversed.toList()[index];
          return Column(
            children: [
              Container(height: .1,color: Colors.transparent,),
              Expanded(
                child: NativeVideoWidget(
                  shouldShow: true,
                  url: videoUrl,
                  preloadUrl: videos.reversed.toList(),
                  shouldMute: false,
                  isLandscape: false,
                  // placeholder: Image.network(
                  //   generateThumbnailUrl(videoUrl),
                  //   fit: BoxFit.cover,
                  //   width: MediaQuery.of(context).size.width,
                  //   height: MediaQuery.of(context).size.height,
                  // ),
                  onDoubleTapDown: (d) {
                    log("double tapped");
                  }, shouldShow: true,
                ),
              ),
            Container(height: 50,color: Colors.transparent,)
            ],
          );
        },
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
