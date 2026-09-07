import Foundation

enum SnapshotCommand {
    static let numbers = Array(1...8)
    enum Encoding: String, CaseIterable, Identifiable {
        case noteOff, noteOnZero
        var id: String { rawValue }
        var title: String { self == .noteOff ? "Note Off（標準）" : "Note On / Velocity 0（互換）" }
    }
    static func bytes(for number: Int, encoding: Encoding = .noteOff) throws -> [UInt8] {
        guard numbers.contains(number) else { throw MIDIError.invalidSnapshot }
        return [encoding == .noteOff ? 0x80 : 0x90, UInt8(53 + number), 0]
    }
}

struct MIDIDestinationInfo: Identifiable, Equatable {
    let endpoint: UInt32
    let uniqueID: Int32
    let displayName: String
    var id: UInt32 { endpoint }
}

enum DestinationSelection {
    static func preferred(in destinations: [MIDIDestinationInfo], savedID: Int32?) -> MIDIDestinationInfo? {
        if let savedID, let saved = destinations.first(where: { $0.uniqueID == savedID }) { return saved }
        return destinations.first { $0.displayName.lowercased().contains("totalmixremote") }
    }
}

enum MIDIError: LocalizedError {
    case invalidSnapshot, disconnected, system(String, Int32)
    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: return "Snapshot番号は1〜8を指定してください。"
        case .disconnected: return "MIDI出力先が見つかりません。設定から出力先を選択してください。"
        case let .system(operation, code): return "\(operation)に失敗しました（\(code)）。設定から再検索してください。"
        }
    }
}
