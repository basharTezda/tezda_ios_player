import Flutter
import UIKit

public class TezdaIosPlayerPlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = VideoViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "native_video_player")

        let channel = FlutterMethodChannel(
            name: "native_video_player_channel", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "togglePlay":
                NotificationCenter.default.post(
                    name: NSNotification.Name("TogglePlayPause"), object: nil)
                result(nil)

            case "toggleMute":
                NotificationCenter.default.post(
                    name: NSNotification.Name("ToggleMute"), object: nil)
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
