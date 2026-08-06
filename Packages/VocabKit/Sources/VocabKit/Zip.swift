import Foundation

/// Store-only (method 0) ZIP writer/reader — enough for our own archives,
/// with standard CRC-32 so other tools accept them.
public enum Zip {
    public static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offsets: [UInt32] = []
        for (name, data) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            offsets.append(UInt32(out.count))
            out.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
            out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(crc)); out.append(le32(UInt32(data.count))); out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(nameData.count))); out.append(le16(0))
            out.append(nameData); out.append(data)
        }
        for (index, (name, data)) in entries.enumerated() {
            let nameData = Data(name.utf8)
            central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32(crc32(data))); central.append(le32(UInt32(data.count))); central.append(le32(UInt32(data.count)))
            central.append(le16(UInt16(nameData.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
            central.append(le32(offsets[index]))
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    /// Reads stored entries; compressed entries are skipped.
    public static func extract(_ data: Data) -> [String: Data] {
        var entries: [String: Data] = [:]
        var cursor = 0
        let bytes = [UInt8](data)
        while cursor + 30 <= bytes.count {
            guard bytes[cursor] == 0x50, bytes[cursor + 1] == 0x4B,
                  bytes[cursor + 2] == 0x03, bytes[cursor + 3] == 0x04 else { break }
            let method = Int(bytes[cursor + 8]) | Int(bytes[cursor + 9]) << 8
            let size = Int(bytes[cursor + 18]) | Int(bytes[cursor + 19]) << 8
                | Int(bytes[cursor + 20]) << 16 | Int(bytes[cursor + 21]) << 24
            let nameLength = Int(bytes[cursor + 26]) | Int(bytes[cursor + 27]) << 8
            let extraLength = Int(bytes[cursor + 28]) | Int(bytes[cursor + 29]) << 8
            let nameStart = cursor + 30
            let dataStart = nameStart + nameLength + extraLength
            guard dataStart + size <= bytes.count else { break }
            let name = String(bytes: bytes[nameStart..<nameStart + nameLength], encoding: .utf8) ?? ""
            if method == 0, !name.isEmpty {
                entries[name] = Data(bytes[dataStart..<dataStart + size])
            }
            cursor = dataStart + size
        }
        return entries
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
