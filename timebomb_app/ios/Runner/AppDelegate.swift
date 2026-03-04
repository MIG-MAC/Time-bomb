import Flutter
import UIKit

private var rustMethodChannel: FlutterMethodChannel?

@_cdecl("tb_flutter_event_callback")
func tb_flutter_event_callback(event_type: UInt8, json_payload: UnsafePointer<CChar>?) {
  let payload = json_payload != nil ? String(cString: json_payload!) : "{}"
  DispatchQueue.main.async {
    rustMethodChannel?.invokeMethod("onRustEvent", arguments: [
      "eventType": Int(event_type),
      "payload": payload,
    ])
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      rustMethodChannel = FlutterMethodChannel(
        name: "timebomb_app/time_bomb_core",
        binaryMessenger: controller.binaryMessenger
      )

      rustMethodChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleRustMethod(call: call, result: result)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleRustMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initSession":
      guard
        let args = call.arguments as? [String: Any],
        let userId = args["userId"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing userId", details: nil))
        return
      }

      let initOk = userId.withCString { cUserId in
        tb_init_session(cUserId)
      }
      let callbackOk = tb_register_event_callback(tb_flutter_event_callback)
      result(initOk && callbackOk)

    case "buildMessage":
      guard
        let args = call.arguments as? [String: Any],
        let instruction = args["instruction"] as? Int,
        let transport = args["transport"] as? Int,
        let payloadJson = args["payloadJson"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Invalid buildMessage args", details: nil))
        return
      }

      let rustBuffer = payloadJson.withCString { cPayload in
        tb_build_message(UInt8(instruction), UInt8(transport), cPayload)
      }

      defer {
        tb_free_rust_buffer(rustBuffer)
      }

      guard let ptr = rustBuffer.ptr, rustBuffer.len > 0 else {
        result(nil)
        return
      }

      let data = Data(bytes: ptr, count: Int(rustBuffer.len))
      result(FlutterStandardTypedData(bytes: data))

    case "processIncoming":
      guard
        let args = call.arguments as? [String: Any],
        let typedData = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "bad_args", message: "Missing bytes", details: nil))
        return
      }

      let data = typedData.data
      let processOk = data.withUnsafeBytes { rawBuffer -> Bool in
        guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return false
        }
        return tb_process_incoming_message(baseAddress, data.count)
      }
      result(processOk)

    case "getSessionState":
      guard let statePtr = tb_get_session_state() else {
        result(nil)
        return
      }

      let state = String(cString: statePtr)
      tb_free_c_string(statePtr)
      result(state)

    case "resetSession":
      result(tb_reset_session())

    case "lastError":
      guard let errPtr = tb_last_error_message() else {
        result(nil)
        return
      }

      let error = String(cString: errPtr)
      tb_free_c_string(errPtr)
      result(error)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
