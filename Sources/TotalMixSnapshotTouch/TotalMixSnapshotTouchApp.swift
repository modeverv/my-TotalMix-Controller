import SwiftUI

@main
struct TotalMixSnapshotTouchApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var midi: MIDIManager
    @StateObject private var osc: OSCManager
    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _midi = StateObject(wrappedValue: MIDIManager(settings: settings))
        _osc = StateObject(wrappedValue: OSCManager(settings: settings))
    }
    var body: some Scene {
        Window("TotalMix Snapshot Touch", id: "main") {
            MainView().environmentObject(settings).environmentObject(midi).environmentObject(osc)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
