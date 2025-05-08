import Flutter
import UIKit
import CachingPlayerItem

public class TezdaIosPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public var eventSink: FlutterEventSink?
    private var notificationObserver: NSObjectProtocol?

public class TezdaIosPlayerPlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = VideoViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "native_video_player")

        let channel = FlutterMethodChannel(
            name: "native_video_player_channel", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "togglePlay":
                NotificationCenter.default.post(name: NSNotification.Name("TogglePlayPause"), object: nil)
                result(nil)
                
            case "toggleMute":
                NotificationCenter.default.post(name: NSNotification.Name("ToggleMute"), object: nil)
                result(nil)
                
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
            // Forward the event to Flutter
            eventSink?(eventData)
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Clear eventSink when the stream is canceled
        self.eventSink = nil
        // Remove the NotificationCenter observer
//        if let observer = notificationObserver {
//            NotificationCenter.default.removeObserver(observer)
//        }
        return nil
    }

    // Method to send events to Flutter
    public func sendEventToFlutter(event: String) {
        eventSink?(event)
    }
}
