import Compression
import Foundation

/// Streaming gzip decompression for large resource downloads — the
/// OpenGloss database travels as ~230 MB of gzip and inflates to ~815 MB
/// on device, so both sides are streamed in 1 MB chunks rather than held
/// in memory.
public enum Gunzip {

    public enum Error: Swift.Error {
        case notGzip
        case corrupt
    }

    /// Inflates `source` (a .gz file) into `destination`, replacing it.
    public static func inflate(from source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        // Gzip header: magic 1f 8b, method 8 (deflate), flags, then optional
        // fields the flags declare. What follows is a raw deflate stream,
        // which is exactly what COMPRESSION_ZLIB decodes.
        guard var header = try input.read(upToCount: 10), header.count == 10,
              header[0] == 0x1F, header[1] == 0x8B, header[2] == 8 else {
            throw Error.notGzip
        }
        let flags = header[3]
        if flags & 0x04 != 0 {  // FEXTRA: 2-byte little-endian length + payload
            guard let lengthBytes = try input.read(upToCount: 2), lengthBytes.count == 2 else {
                throw Error.corrupt
            }
            let length = Int(lengthBytes[0]) | Int(lengthBytes[1]) << 8
            _ = try input.read(upToCount: length)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            // FNAME / FCOMMENT: zero-terminated strings.
            while let byte = try input.read(upToCount: 1), byte.first != 0, !byte.isEmpty {}
        }
        if flags & 0x02 != 0 {  // FHCRC
            _ = try input.read(upToCount: 2)
        }
        header.removeAll()

        let temp = destination.appendingPathExtension("inflating")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let output = try FileHandle(forWritingTo: temp)
        defer { try? output.close() }

        var stream = compression_stream()
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw Error.corrupt }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 1 << 20
        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outBuffer.deallocate() }

        var finished = false
        while !finished {
            let chunk = try input.read(upToCount: bufferSize) ?? Data()
            let isLast = chunk.isEmpty
            try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress
                    ?? UnsafePointer(outBuffer)  // never read: empty chunk only
                stream.src_size = chunk.count
                repeat {
                    stream.dst_ptr = outBuffer
                    stream.dst_size = bufferSize
                    status = compression_stream_process(
                        &stream, isLast ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    guard status != COMPRESSION_STATUS_ERROR else { throw Error.corrupt }
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 {
                        try output.write(contentsOf: Data(bytes: outBuffer, count: produced))
                    }
                    if status == COMPRESSION_STATUS_END {
                        finished = true
                        break
                    }
                    // Keep draining while the decoder fills the whole buffer.
                } while stream.src_size > 0 || stream.dst_size == 0
            }
            if isLast && !finished {
                // Truncated file: deflate never signalled its end.
                throw Error.corrupt
            }
        }
        try output.close()
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}
