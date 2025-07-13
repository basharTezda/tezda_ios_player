import Flutter
import UIKit

public class TezdaIosPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public var eventSink: FlutterEventSink?
    private var notificationObserver: NSObjectProtocol?
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = VideoViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "native_video_player")
        let channel = FlutterMethodChannel(name: "native_video_player_channel", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "native_video_player_event", binaryMessenger: registrar.messenger())
        let instance = TezdaIosPlayerPlugin()
        eventChannel.setStreamHandler(instance)
        instance.notificationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("VideoDurationUpdate"), object: nil, queue: .main) { notification in
            instance.handleVideoDurationUpdate(notification)
        }
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "togglePlay":
                NotificationCenter.default.post(name: NSNotification.Name("TogglePlayPause"), object: nil)
                result(nil)
                 case "play":
                NotificationCenter.default.post(name: NSNotification.Name("play"), object: nil)
                result(nil)
                 case "pause":
                NotificationCenter.default.post(name: NSNotification.Name("pause"), object: nil)
                result(nil)
                
            case "toggleMute":
                NotificationCenter.default.post(name: NSNotification.Name("ToggleMute"), object: nil)
                result(nil)
            case "cacheVideos":
                if let arguments = call.arguments as? [String: Any],
                   let videos = arguments["videos"] as? [String] {
                    instance.handleCacheVideos(videos: videos)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Time argument missing", details: nil))
                }
            case "seekTo":
                if let arguments = call.arguments as? [String: Any],
                   let time = arguments["time"] as? Double {
                    // Post a notification to seek to the desired time
                    NotificationCenter.default.post(name: Notification.Name("SeekToTimeNotification"), object: time)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Time argument missing", details: nil))
                }
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    @objc private func handleVideoDurationUpdate(_ notification: Notification) {
        if let eventData = notification.object as? [String: Any] {
            self.sendEventToFlutter(event: eventData )
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    private func handleCacheVideos(videos: [String]){
        VideoPlayerUIView.shared.cacheVideoUrls(urls: videos) { result in
            print("Caching completed: \(result)")
        }
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    public func sendEventToFlutter(event: Any ) {
         do {
             let result = try  eventSink?(["event": "\(event)"])
 //            print("Success:", result)
         } catch {
 //            print("Error:", error)
         }
       
    }
}
