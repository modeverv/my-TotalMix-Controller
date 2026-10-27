import SwiftUI

@main
struct TotalMixSnapshotTouchIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings: AppSettings
    @StateObject private var osc: OSCManager

    init() {
        let settings: AppSettings
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           let defaults = UserDefaults(suiteName: "local.seijiro.TotalMixSnapshotTouch.uitests") {
            defaults.removePersistentDomain(forName: "local.seijiro.TotalMixSnapshotTouch.uitests")
            settings = AppSettings(defaults: defaults)
            let environment = ProcessInfo.processInfo.environment
            settings.oscHost = environment["UITEST_OSC_HOST"] ?? ""
            if let port = environment["UITEST_OSC_SEND_PORT"].flatMap(Int.init) { settings.oscSendPort = port }
            if let port = environment["UITEST_OSC_RECEIVE_PORT"].flatMap(Int.init) { settings.oscReceivePort = port }
        } else {
            settings = AppSettings()
        }
#else
        settings = AppSettings()
#endif
        _settings = StateObject(wrappedValue: settings)
        _osc = StateObject(wrappedValue: OSCManager(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            IOSMainView()
                .environmentObject(settings)
                .environmentObject(osc)
                .preferredColorScheme(.dark)
                .tint(.mint)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { osc.reconnect() }
            else { osc.disconnect() }
        }
    }
}
