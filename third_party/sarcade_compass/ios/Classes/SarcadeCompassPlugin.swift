import CoreLocation
import Flutter
import UIKit

/// Heading of Core Location (magnetic north) and its accuracy.
public class SarcadeCompassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var sink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SarcadeCompassPlugin()
        let channel = FlutterEventChannel(name: "org.sarcade/compass", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(instance)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = kCLHeadingFilterNone
        manager.headingOrientation = .portrait
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if !CLLocationManager.headingAvailable() {
            return FlutterError(code: "no_sensor", message: "No compass on this device", details: nil)
        }
        sink = events
        manager.startUpdatingHeading()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        manager.stopUpdatingHeading()
        sink = nil
        return nil
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the heading is not valid (calibration needed).
        let valid = newHeading.headingAccuracy >= 0
        sink?([valid ? newHeading.magneticHeading : -1.0, valid ? newHeading.headingAccuracy : -1.0, -1.0])
    }

    /// iOS shows its own calibration screen when it needs it.
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }
}
