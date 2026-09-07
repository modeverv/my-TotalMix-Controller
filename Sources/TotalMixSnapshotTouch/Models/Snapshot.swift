import Foundation

enum SnapshotCommand {
    static let numbers = Array(1...8)
    static func number(forFeedbackAddress address: String) -> Int? {
        numbers.first { self.address(for: $0) == address }
    }
    static func address(for number: Int) -> String? {
        guard numbers.contains(number) else { return nil }
        // TotalMix's OSC snapshot rows are numbered in reverse order.
        return "/3/snapshots/\(9 - number)/1"
    }
}
