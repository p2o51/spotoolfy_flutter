import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // 添加URL scheme回调处理
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // 处理Spotify回调
    if url.scheme == "spotoolfy" {
      // 通知Flutter层处理回调
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "spotify_auth",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handleCallback", arguments: url.absoluteString)
      }
      return true
    }
    
    return super.application(app, open: url, options: options)
  }
  
  // iOS 9以下版本的兼容性处理
  override func application(
    _ application: UIApplication,
    open url: URL,
    sourceApplication: String?,
    annotation: Any
  ) -> Bool {
    if url.scheme == "spotoolfy" {
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "spotify_auth",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handleCallback", arguments: url.absoluteString)
      }
      return true
    }
    
    return super.application(application, open: url, sourceApplication: sourceApplication, annotation: annotation)
  }
}
