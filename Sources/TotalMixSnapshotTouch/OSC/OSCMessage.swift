import Foundation

struct OSCMessage: Equatable {
    enum Value: Equatable { case float(Float), string(String), integer(Int32) }
    let address: String
    let value: Value
    var number: Float? {
        switch value { case .float(let v): return v; case .integer(let v): return Float(v); case .string: return nil }
    }
    static func encode(_ address: String, value: Float) -> Data {
        func string(_ value: String) -> Data {
            var data = Data(value.utf8); data.append(0)
            while data.count % 4 != 0 { data.append(0) }
            return data
        }
        var result = string(address) + string(",f")
        var bits = value.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
        return result
    }
    static func decode(_ data: Data, depth: Int = 0) -> [OSCMessage] {
        let bytes = Array(data)
        guard depth < 8, !bytes.isEmpty else { return [] }
        func uint(_ index: Int) -> UInt32? {
            guard index >= 0, index + 4 <= bytes.count else { return nil }
            return bytes[index..<index+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        if bytes.starts(with: Array("#bundle\0".utf8)) {
            guard bytes.count >= 16 else { return [] }
            var index = 16, result: [OSCMessage] = []
            while index < bytes.count {
                guard let size = uint(index), size > 0, Int(size) <= bytes.count - index - 4 else { return [] }
                index += 4
                result += decode(Data(bytes[index..<index+Int(size)]), depth: depth + 1)
                index += Int(size)
            }
            return result
        }
        var index = 0
        func readString() -> String? {
            guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0),
                  let text = String(bytes: bytes[index..<end], encoding: .utf8) else { return nil }
            index = (end + 4) / 4 * 4
            guard index <= bytes.count else { return nil }
            return text
        }
        guard let address = readString(), address.hasPrefix("/"), let tag = readString() else { return [] }
        let value: Value
        switch tag {
        case ",f":
            guard let bits = uint(index) else { return [] }
            let number = Float(bitPattern: bits)
            guard number.isFinite else { return [] }
            value = .float(number)
        case ",i":
            guard let bits = uint(index) else { return [] }
            value = .integer(Int32(bitPattern: bits))
        case ",s": guard let text = readString() else { return [] }; value = .string(text)
        default: return []
        }
        return [OSCMessage(address: address, value: value)]
    }
}
