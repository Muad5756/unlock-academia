import Flutter
import Foundation

protocol ScreenProtectionApplying {
    func enableScreenshotBlocking() throws -> [String: Any]
}

final class SecurityScreenProtectionBridge: NSObject {
    private let channel: FlutterMethodChannel
    private let adapter: ScreenProtectionApplying?

    init(
        messenger: FlutterBinaryMessenger,
        adapter: ScreenProtectionApplying?
    ) {
        self.channel = FlutterMethodChannel(
            name: "app.security/screen_protection",
            binaryMessenger: messenger
        )
        self.adapter = adapter
        super.init()
        channel.setMethodCallHandler(handle)
    }

    static func register(
        with registrar: FlutterPluginRegistrar,
        adapter: ScreenProtectionApplying?
    ) {
        _ = SecurityScreenProtectionBridge(
            messenger: registrar.messenger(),
            adapter: adapter
        )
    }

    private func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard call.method == "enableScreenshotBlocking" else {
            result(FlutterMethodNotImplemented)
            return
        }

        let arguments = call.arguments as? [String: Any]
        let qaForceFailure = arguments?["qaForceFailure"] as? Bool ?? false

        #if DEBUG
        if qaForceFailure {
            result([
                "ok": false,
                "code": "SCREEN_PROTECTION_FAILED",
                "message": "enableScreenshotBlocking: failed to apply protection",
                "logs": [
                    "QA dev-mode simulated ScreenPreventerKit failure"
                ]
            ])
            return
        }
        #endif

        guard let adapter = adapter else {
            result([
                "ok": false,
                "code": "SCREEN_PROTECTION_ADAPTER_MISSING",
                "message": "No native screen-protection adapter is registered",
                "logs": [
                    "Failing closed because screen protection is not wired"
                ]
            ])
            return
        }

        do {
            let response = try adapter.enableScreenshotBlocking()
            result(response)
        } catch {
            result([
                "ok": false,
                "code": "SCREEN_PROTECTION_EXCEPTION",
                "message": String(describing: error),
                "logs": [
                    "Native screen-protection adapter threw an exception"
                ]
            ])
        }
    }
}
