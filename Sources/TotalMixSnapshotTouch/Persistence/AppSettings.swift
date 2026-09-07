import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var oscEnabled: Bool { didSet { defaults.set(oscEnabled, forKey: "oscEnabled") } }
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
    @Published var destinationID: Int32? {
        didSet {
            if let destinationID { defaults.set(Int(destinationID), forKey: "destinationUniqueID") }
            else { defaults.removeObject(forKey: "destinationUniqueID") }
        }
    }
    @Published var encoding: SnapshotCommand.Encoding {
        didSet { defaults.set(encoding.rawValue, forKey: "midiEncoding") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        oscEnabled = defaults.object(forKey: "oscEnabled") as? Bool ?? true
        let sendPort = defaults.integer(forKey: "oscSendPort")
        let receivePort = defaults.integer(forKey: "oscReceivePort")
        oscSendPort = (1024...65535).contains(sendPort) ? sendPort : 7001
        oscReceivePort = (1024...65535).contains(receivePort) ? receivePort : 9001
        hiddenSnapshots = Set((defaults.array(forKey: "hiddenSnapshots") as? [Int] ?? [])
            .filter { SnapshotCommand.numbers.contains($0) })
        let stored = defaults.stringArray(forKey: "snapshotNames") ?? []
        snapshotNames = SnapshotCommand.numbers.map { stored.indices.contains($0 - 1) ? stored[$0 - 1] : "Snapshot \($0)" }
        destinationID = (defaults.object(forKey: "destinationUniqueID") as? NSNumber)?.int32Value
        encoding = SnapshotCommand.Encoding(rawValue: defaults.string(forKey: "midiEncoding") ?? "") ?? .noteOff
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
