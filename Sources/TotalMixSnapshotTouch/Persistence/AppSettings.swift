import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var oscEnabled: Bool { didSet { defaults.set(oscEnabled, forKey: "oscEnabled") } }
    @Published var oscHost: String { didSet { defaults.set(oscHost, forKey: "oscHost") } }
    @Published var oscSendPort: Int { didSet { defaults.set(oscSendPort, forKey: "oscSendPort") } }
    @Published var oscReceivePort: Int { didSet { defaults.set(oscReceivePort, forKey: "oscReceivePort") } }
    @Published private(set) var snapshotNames: [String]
    @Published private(set) var hiddenSnapshots: Set<Int>
    var visibleSnapshotNumbers: [Int] {
        SnapshotCommand.numbers.filter { !hiddenSnapshots.contains($0) }
    }
    func setHidden(_ hidden: Bool, for number: Int) {
        guard SnapshotCommand.numbers.contains(number) else { return }
        if hidden { hiddenSnapshots.insert(number) }
        else { hiddenSnapshots.remove(number) }
        defaults.set(hiddenSnapshots.sorted(), forKey: "hiddenSnapshots")
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        oscEnabled = defaults.object(forKey: "oscEnabled") as? Bool ?? true
        #if os(iOS)
        let defaultHost = ""
        let defaultSendPort = 7002
        let defaultReceivePort = 9002
        #else
        let defaultHost = "127.0.0.1"
        let defaultSendPort = 7001
        let defaultReceivePort = 9001
        #endif
        oscHost = defaults.string(forKey: "oscHost") ?? defaultHost
        let sendPort = defaults.integer(forKey: "oscSendPort")
        let receivePort = defaults.integer(forKey: "oscReceivePort")
        oscSendPort = (1024...65535).contains(sendPort) ? sendPort : defaultSendPort
        oscReceivePort = (1024...65535).contains(receivePort) ? receivePort : defaultReceivePort
        hiddenSnapshots = Set((defaults.array(forKey: "hiddenSnapshots") as? [Int] ?? [])
            .filter { SnapshotCommand.numbers.contains($0) })
        let stored = defaults.stringArray(forKey: "snapshotNames") ?? []
        snapshotNames = SnapshotCommand.numbers.map { stored.indices.contains($0 - 1) ? stored[$0 - 1] : "Snapshot \($0)" }
    }
    func name(for number: Int) -> String {
        guard snapshotNames.indices.contains(number - 1) else { return "" }
        let name = snapshotNames[number - 1]
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Snapshot \(number)" : name
    }
    func setName(_ name: String, for number: Int) {
        guard snapshotNames.indices.contains(number - 1) else { return }
        snapshotNames[number - 1] = name
        defaults.set(snapshotNames, forKey: "snapshotNames")
    }
    func resetNames() {
        snapshotNames = SnapshotCommand.numbers.map { "Snapshot \($0)" }
        defaults.set(snapshotNames, forKey: "snapshotNames")
    }
}
