//
//  ZipArchive.swift
//  Soundprint
//
//  仅支持 Store（无压缩）方式的 ZIP 读写。音频已是 AAC，备份中无需二次压缩。
//  导入时校验 CRC、路径安全、大小上限与格式，拒绝路径穿越与 ZIP64。
//

import Foundation

enum ZipArchiveError: LocalizedError {
    case invalidArchive
    case unsupportedCompression
    case encrypted
    case zip64Unsupported
    case unsafePath
    case tooLarge
    case checksumMismatch
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The ZIP file format could not be read."
        case .unsupportedCompression: return "This compression method is not supported. Choose a ZIP exported from Soundprint."
        case .encrypted: return "Encrypted ZIP files are not supported."
        case .zip64Unsupported: return "ZIP files larger than 4GB are not supported."
        case .unsafePath: return "Import was stopped because the archive contains an unsafe file path."
        case .tooLarge: return "The archive exceeds the size limit."
        case .checksumMismatch: return "File verification failed. The archive may be damaged."
        case .writeFailed: return "The ZIP could not be written."
        }
    }
}

enum ZipArchiveWriter {
    struct Entry {
        enum Source {
            case data(Data)
            case file(URL)
        }
        let path: String
        let source: Source

        static func data(path: String, data: Data) -> Entry {
            Entry(path: path, source: .data(data))
        }

        static func file(path: String, url: URL) -> Entry {
            Entry(path: path, source: .file(url))
        }
    }

    static func write(entries: [Entry], to outputURL: URL) throws {
        guard entries.count <= Int(UInt16.max) else { throw ZipArchiveError.tooLarge }
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        guard fm.createFile(atPath: outputURL.path, contents: nil) else {
            throw ZipArchiveError.writeFailed
        }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        var centralRecords: [Data] = []
        let dos = dosDateTime(Date())

        for entry in entries {
            guard let nameData = entry.path.data(using: .utf8),
                  !nameData.isEmpty,
                  isSafeArchivePath(entry.path) else {
                throw ZipArchiveError.unsafePath
            }
            let localOffset = offset
            switch entry.source {
            case .data(let data):
                guard data.count <= Int(UInt32.max) else { throw ZipArchiveError.tooLarge }
                let crc = CRC32.checksum(data)
                var header = localHeader(
                    nameLength: UInt16(nameData.count),
                    crc: crc,
                    compressedSize: UInt32(data.count),
                    uncompressedSize: UInt32(data.count),
                    dosTime: dos.time,
                    dosDate: dos.date
                )
                header.append(nameData)
                header.append(data)
                try handle.write(contentsOf: header)
                offset += UInt64(header.count)
                centralRecords.append(centralRecord(
                    nameData: nameData,
                    crc: crc,
                    size: UInt32(data.count),
                    localOffset: localOffset,
                    dosTime: dos.time,
                    dosDate: dos.date
                ))

            case .file(let url):
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize else {
                    throw ZipArchiveError.invalidArchive
                }
                guard size <= Int(UInt32.max) else { throw ZipArchiveError.tooLarge }

                var header = localHeader(
                    nameLength: UInt16(nameData.count),
                    crc: 0,
                    compressedSize: 0,
                    uncompressedSize: 0,
                    dosTime: dos.time,
                    dosDate: dos.date
                )
                header.append(nameData)
                try handle.write(contentsOf: header)
                offset += UInt64(header.count)

                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                var crc = CRC32()
                var written: UInt64 = 0
                while true {
                    let chunk = try input.read(upToCount: 512 * 1024) ?? Data()
                    if chunk.isEmpty { break }
                    crc.update(chunk)
                    try handle.write(contentsOf: chunk)
                    written += UInt64(chunk.count)
                }
                guard written == UInt64(size) else { throw ZipArchiveError.writeFailed }
                offset += written

                // 回填本地头中的 CRC 与大小。
                let patch = littleEndianData(
                    values: [crc.value, UInt32(size), UInt32(size)]
                )
                try handle.seek(toOffset: localOffset + 14)
                try handle.write(contentsOf: patch)
                try handle.seekToEnd()
                centralRecords.append(centralRecord(
                    nameData: nameData,
                    crc: crc.value,
                    size: UInt32(size),
                    localOffset: localOffset,
                    dosTime: dos.time,
                    dosDate: dos.date
                ))
            }
        }

        let centralOffset = offset
        for record in centralRecords {
            try handle.write(contentsOf: record)
            offset += UInt64(record.count)
        }
        let centralSize = offset - centralOffset
        guard offset <= UInt64(UInt32.max) else { throw ZipArchiveError.tooLarge }

        var end = Data()
        end.appendLE32(0x06054b50)
        end.appendLE16(0)
        end.appendLE16(0)
        end.appendLE16(UInt16(centralRecords.count))
        end.appendLE16(UInt16(centralRecords.count))
        end.appendLE32(UInt32(centralSize))
        end.appendLE32(UInt32(centralOffset))
        end.appendLE16(0)
        try handle.write(contentsOf: end)
        try handle.synchronize()
    }

    // MARK: - 头

    private static func localHeader(
        nameLength: UInt16,
        crc: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        dosTime: UInt16,
        dosDate: UInt16
    ) -> Data {
        var data = Data()
        data.appendLE32(0x04034b50)
        data.appendLE16(20)
        data.appendLE16(0x0800)
        data.appendLE16(0)
        data.appendLE16(dosTime)
        data.appendLE16(dosDate)
        data.appendLE32(crc)
        data.appendLE32(compressedSize)
        data.appendLE32(uncompressedSize)
        data.appendLE16(nameLength)
        data.appendLE16(0)
        return data
    }

    private static func centralRecord(
        nameData: Data,
        crc: UInt32,
        size: UInt32,
        localOffset: UInt64,
        dosTime: UInt16,
        dosDate: UInt16
    ) -> Data {
        var data = Data()
        data.appendLE32(0x02014b50)
        data.appendLE16(20)
        data.appendLE16(20)
        data.appendLE16(0x0800)
        data.appendLE16(0)
        data.appendLE16(dosTime)
        data.appendLE16(dosDate)
        data.appendLE32(crc)
        data.appendLE32(size)
        data.appendLE32(size)
        data.appendLE16(UInt16(nameData.count))
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE32(0)
        data.appendLE32(UInt32(localOffset))
        data.append(nameData)
        return data
    }

    private static func littleEndianData(values: [UInt32]) -> Data {
        var data = Data()
        values.forEach { data.appendLE32($0) }
        return data
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("..") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, components.year ?? 2024))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

enum ZipArchiveReader {
    struct Entry {
        let path: String
        let compression: UInt16
        let flags: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localOffset: UInt32
    }

    static func extract(zipURL: URL, to destination: URL) throws {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ZipArchiveError.invalidArchive }

        let tailSize = UInt64(min(fileSize, 65_557))
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try readExactly(handle, count: Int(tailSize))
        guard let eocdRange = tail.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards) else {
            throw ZipArchiveError.invalidArchive
        }
        let eocd = tail.subdata(in: eocdRange.lowerBound..<tail.endIndex)
        guard eocd.count >= 22 else { throw ZipArchiveError.invalidArchive }
        var cursor = 0
        guard eocd.readUInt32(at: &cursor) == 0x06054b50 else { throw ZipArchiveError.invalidArchive }
        _ = eocd.readUInt16(at: &cursor)
        _ = eocd.readUInt16(at: &cursor)
        let totalEntries = Int(eocd.readUInt16(at: &cursor))
        let entriesOnDisk = Int(eocd.readUInt16(at: &cursor))
        let centralSize = UInt64(eocd.readUInt32(at: &cursor))
        let centralOffset = UInt64(eocd.readUInt32(at: &cursor))
        _ = eocd.readUInt16(at: &cursor)

        guard totalEntries != Int(UInt16.max), entriesOnDisk != Int(UInt16.max) else {
            throw ZipArchiveError.zip64Unsupported
        }
        guard totalEntries == entriesOnDisk, totalEntries <= 10_000 else {
            throw ZipArchiveError.tooLarge
        }
        guard centralOffset + centralSize <= fileSize else {
            throw ZipArchiveError.invalidArchive
        }

        try handle.seek(toOffset: centralOffset)
        let central = try readExactly(handle, count: Int(centralSize))
        var entries: [Entry] = []
        var index = 0
        for _ in 0..<totalEntries {
            guard central.readUInt32(at: &index) == 0x02014b50 else {
                throw ZipArchiveError.invalidArchive
            }
            _ = central.readUInt16(at: &index)
            let versionNeeded = central.readUInt16(at: &index)
            let flags = central.readUInt16(at: &index)
            let compression = central.readUInt16(at: &index)
            _ = central.readUInt16(at: &index)
            _ = central.readUInt16(at: &index)
            let crc = central.readUInt32(at: &index)
            let compressedSize = central.readUInt32(at: &index)
            let uncompressedSize = central.readUInt32(at: &index)
            let nameLength = Int(central.readUInt16(at: &index))
            let extraLength = Int(central.readUInt16(at: &index))
            let commentLength = Int(central.readUInt16(at: &index))
            _ = central.readUInt16(at: &index)
            _ = central.readUInt16(at: &index)
            _ = central.readUInt32(at: &index)
            let localOffset = central.readUInt32(at: &index)
            guard nameLength >= 0, index + nameLength + extraLength + commentLength <= central.count else {
                throw ZipArchiveError.invalidArchive
            }
            let nameData = central.subdata(in: index..<(index + nameLength))
            index += nameLength + extraLength + commentLength
            guard versionNeeded <= 63, let name = String(data: nameData, encoding: .utf8) else {
                throw ZipArchiveError.invalidArchive
            }
            guard flags & 0x0001 == 0 else { throw ZipArchiveError.encrypted }
            guard compression == 0 else { throw ZipArchiveError.unsupportedCompression }
            guard compressedSize != UInt32.max, uncompressedSize != UInt32.max, localOffset != UInt32.max else {
                throw ZipArchiveError.zip64Unsupported
            }
            guard isSafeExtractionPath(name) else { throw ZipArchiveError.unsafePath }
            entries.append(Entry(
                path: name,
                compression: compression,
                flags: flags,
                crc: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localOffset: localOffset
            ))
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var totalExtracted: UInt64 = 0
        for entry in entries {
            if entry.path.hasSuffix("/") {
                let directory = destination.appendingPathComponent(String(entry.path.dropLast()))
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                continue
            }
            guard UInt64(entry.uncompressedSize) <= 4 * 1024 * 1024 * 1024 else {
                throw ZipArchiveError.tooLarge
            }
            totalExtracted += UInt64(entry.uncompressedSize)
            guard totalExtracted <= 20 * 1024 * 1024 * 1024 else {
                throw ZipArchiveError.tooLarge
            }

            let fileURL = destination.appendingPathComponent(entry.path)
            let standardized = fileURL.standardizedFileURL.path
            let root = destination.standardizedFileURL.path
            guard standardized.hasPrefix(root + "/") else { throw ZipArchiveError.unsafePath }
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            try handle.seek(toOffset: UInt64(entry.localOffset))
            let localHeader = try readExactly(handle, count: 30)
            var localCursor = 0
            guard localHeader.readUInt32(at: &localCursor) == 0x04034b50 else {
                throw ZipArchiveError.invalidArchive
            }
            _ = localHeader.readUInt16(at: &localCursor)
            _ = localHeader.readUInt16(at: &localCursor)
            _ = localHeader.readUInt16(at: &localCursor)
            _ = localHeader.readUInt16(at: &localCursor)
            _ = localHeader.readUInt16(at: &localCursor)
            _ = localHeader.readUInt32(at: &localCursor)
            _ = localHeader.readUInt32(at: &localCursor)
            _ = localHeader.readUInt32(at: &localCursor)
            let localNameLength = Int(localHeader.readUInt16(at: &localCursor))
            let localExtraLength = Int(localHeader.readUInt16(at: &localCursor))
            let dataOffset = UInt64(entry.localOffset) + 30 + UInt64(localNameLength + localExtraLength)
            guard dataOffset + UInt64(entry.compressedSize) <= fileSize else {
                throw ZipArchiveError.invalidArchive
            }

            if fm.fileExists(atPath: fileURL.path) {
                try fm.removeItem(at: fileURL)
            }
            guard fm.createFile(atPath: fileURL.path, contents: nil) else {
                throw ZipArchiveError.writeFailed
            }
            let output = try FileHandle(forWritingTo: fileURL)
            defer { try? output.close() }
            try handle.seek(toOffset: dataOffset)
            var remaining = Int(entry.compressedSize)
            var crc = CRC32()
            while remaining > 0 {
                let count = min(512 * 1024, remaining)
                let chunk = try handle.read(upToCount: count) ?? Data()
                guard !chunk.isEmpty else { throw ZipArchiveError.invalidArchive }
                crc.update(chunk)
                try output.write(contentsOf: chunk)
                remaining -= chunk.count
            }
            try output.synchronize()
            guard crc.value == entry.crc else { throw ZipArchiveError.checksumMismatch }
        }
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            let chunk = try handle.read(upToCount: remaining) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count == count else { throw ZipArchiveError.invalidArchive }
        return data
    }

    private static func isSafeExtractionPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0"),
              !path.contains("..") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}

// MARK: - CRC32

struct CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    private var state: UInt32 = 0xFFFFFFFF

    var value: UInt32 { state ^ 0xFFFFFFFF }

    init() {}

    mutating func update(_ data: Data) {
        var crc = state
        data.withUnsafeBytes { buffer in
            for byte in buffer.bindMemory(to: UInt8.self) {
                crc = Self.table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        state = crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.value
    }
}

// MARK: - 字节工具

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func readUInt16(at index: inout Int) -> UInt16 {
        guard index + 2 <= count else { return 0 }
        let value = UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
        index += 2
        return value
    }

    func readUInt32(at index: inout Int) -> UInt32 {
        guard index + 4 <= count else { return 0 }
        let value = UInt32(self[index])
            | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16)
            | (UInt32(self[index + 3]) << 24)
        index += 4
        return value
    }
}
