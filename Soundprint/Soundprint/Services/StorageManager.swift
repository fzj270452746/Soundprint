//
//  StorageManager.swift
//  Soundprint
//
//  管理应用沙盒中的原始音频、可重建缓存与临时文件。
//

import AVFoundation
import Foundation

struct StorageStats {
    var audioBytes: Int64 = 0
    var cacheBytes: Int64 = 0
    var databaseBytes: Int64 = 0
    var availableBytes: Int64 = 0
    var recordingCount: Int = 0

    var totalAppBytes: Int64 { audioBytes + cacheBytes + databaseBytes }
    var cacheRatio: Double {
        let total = max(1, totalAppBytes)
        return Double(cacheBytes) / Double(total)
    }
}

struct StorageIntegrityReport {
    var missingAudio: [(id: UUID, title: String, path: String)] = []
    var orphanAudio: [URL] = []
    var orphanCache: [URL] = []
    var pendingDeletions: [String] = []

    var hasIssues: Bool {
        !missingAudio.isEmpty || !orphanAudio.isEmpty || !orphanCache.isEmpty || !pendingDeletions.isEmpty
    }
}

final class StorageManager {
    static let shared = StorageManager()

    let baseDirectory: URL
    let databaseDirectory: URL
    let audioDirectory: URL
    let waveformDirectory: URL
    let analysisDirectory: URL
    let tempDirectory: URL
    let exportDirectory: URL
    let recordingDraftsDirectory: URL

    private let fileManager = FileManager.default
    private let pendingDeletionKey = SPDefaultsKey.pendingDeletions

    private init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        baseDirectory = support.appendingPathComponent("Soundprint", isDirectory: true)
        databaseDirectory = baseDirectory.appendingPathComponent("Database", isDirectory: true)
        audioDirectory = baseDirectory.appendingPathComponent("Audio", isDirectory: true)
        waveformDirectory = baseDirectory.appendingPathComponent("Waveforms", isDirectory: true)
        analysisDirectory = baseDirectory.appendingPathComponent("Analysis", isDirectory: true)
        tempDirectory = baseDirectory.appendingPathComponent("Temp", isDirectory: true)
        exportDirectory = tempDirectory.appendingPathComponent("Exports", isDirectory: true)
        recordingDraftsDirectory = tempDirectory.appendingPathComponent("RecordingDrafts", isDirectory: true)
        prepareDirectories()
    }

    // MARK: - 目录

    func prepareDirectories() {
        let directories = [
            baseDirectory,
            databaseDirectory,
            audioDirectory,
            waveformDirectory,
            analysisDirectory,
            tempDirectory,
            exportDirectory,
            recordingDraftsDirectory
        ]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        // 原始音频使用“首次解锁后可访问”的保护等级，保证后台录音与锁屏播放可靠。
        protectDirectory(audioDirectory)
        protectDirectory(databaseDirectory)
        protectDirectory(recordingDraftsDirectory)

        // 可重建缓存不参与 iCloud 备份。
        excludeFromBackup(waveformDirectory)
        excludeFromBackup(analysisDirectory)
        excludeFromBackup(tempDirectory)
    }

    private func protectDirectory(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    func protectFile(at url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    // MARK: - 路径

    func relativePathAudio(for id: UUID) -> String {
        "Audio/\(id.uuidString).m4a"
    }

    func relativePathWaveform(for id: UUID) -> String {
        "Waveforms/\(id.uuidString).waveform.json"
    }

    func relativePathAnalysis(for id: UUID) -> String {
        "Analysis/\(id.uuidString).analysis.json"
    }

    func relativePathSuggestions(for id: UUID) -> String {
        "Analysis/\(id.uuidString).suggestions.json"
    }

    func relativePathSpectrogram(for id: UUID) -> String {
        "Analysis/\(id.uuidString).spectrogram.json"
    }

    func absoluteURL(forRelativePath path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }
        let url = baseDirectory.appendingPathComponent(trimmed).standardizedFileURL
        let base = baseDirectory.standardizedFileURL.path
        guard url.path == base || url.path.hasPrefix(base + "/") else { return nil }
        return url
    }

    func audioURL(for record: RecordingEntity) -> URL? {
        absoluteURL(forRelativePath: record.relativeAudioPath)
    }

    func waveformURL(for record: RecordingEntity) -> URL? {
        guard let path = record.waveformRelativePath else { return nil }
        return absoluteURL(forRelativePath: path)
    }

    func analysisURL(for record: RecordingEntity) -> URL? {
        guard let path = record.analysis?.analysisRelativePath else { return nil }
        return absoluteURL(forRelativePath: path)
    }

    func spectrogramURL(for record: RecordingEntity) -> URL? {
        guard let path = record.analysis?.spectrogramRelativePath else { return nil }
        return absoluteURL(forRelativePath: path)
    }

    func suggestionsURL(for record: RecordingEntity) -> URL? {
        absoluteURL(forRelativePath: relativePathSuggestions(for: record.id))
    }

    func newTemporaryRecordingURL(id: UUID = UUID()) -> URL {
        recordingDraftsDirectory
            .appendingPathComponent("\(id.uuidString).m4a")
    }

    func makeExportDirectory(name: String) throws -> URL {
        let safeName = SPFormat.safeFilename(name, fallback: "Soundprint")
        let url = exportDirectory
            .appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func tempFileURL(name: String, extension ext: String) -> URL {
        let safeName = SPFormat.safeFilename(name, fallback: "Soundprint")
        return tempDirectory
            .appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(8)).\(ext)")
    }

    // MARK: - 文件操作

    @discardableResult
    func moveRecording(from temporaryURL: URL, to recordID: UUID) throws -> String {
        let relative = relativePathAudio(for: recordID)
        guard let destination = absoluteURL(forRelativePath: relative) else {
            throw StorageError.invalidPath
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        protectFile(at: destination)
        return relative
    }

    @discardableResult
    func importAudio(from sourceURL: URL, for recordID: UUID) throws -> String {
        let relative = relativePathAudio(for: recordID)
        guard let destination = absoluteURL(forRelativePath: relative) else {
            throw StorageError.invalidPath
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        protectFile(at: destination)
        return relative
    }

    func write<T: Encodable>(_ value: T, toRelativePath path: String) throws {
        guard let url = absoluteURL(forRelativePath: path) else { throw StorageError.invalidPath }
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        protectFile(at: url)
    }

    func read<T: Decodable>(_ type: T.Type, fromRelativePath path: String) -> T? {
        guard let url = absoluteURL(forRelativePath: path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func deleteRelativeFile(_ path: String?) {
        guard let path, let url = absoluteURL(forRelativePath: path) else { return }
        try? fileManager.removeItem(at: url)
    }

    func deleteAudioFile(for record: RecordingEntity) {
        guard let url = audioURL(for: record) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            queuePendingDeletion(record.relativeAudioPath)
        }
        deleteRelativeFile(record.waveformRelativePath)
        if let analysisPath = record.analysis?.analysisRelativePath {
            deleteRelativeFile(analysisPath)
        }
        if let spectrogramPath = record.analysis?.spectrogramRelativePath {
            deleteRelativeFile(spectrogramPath)
        }
        deleteRelativeFile(relativePathSuggestions(for: record.id))
    }

    func deleteAllAudioAndCache() throws {
        for directory in [audioDirectory, waveformDirectory, analysisDirectory, recordingDraftsDirectory] {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        prepareDirectories()
        UserDefaults.standard.removeObject(forKey: pendingDeletionKey)
    }

    func cleanTemporaryFiles() {
        if let exports = try? fileManager.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in exports {
                try? fileManager.removeItem(at: url)
            }
        }
        // 清理上次异常退出留下的导入解压目录，但保留录音草稿供恢复。
        if let tempContents = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for url in tempContents where url.lastPathComponent.hasPrefix("Import-") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    func clearAnalysisCaches() throws {
        for directory in [waveformDirectory, analysisDirectory] {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        prepareDirectories()
    }

    // MARK: - 待删除队列

    var pendingDeletions: [String] {
        UserDefaults.standard.stringArray(forKey: pendingDeletionKey) ?? []
    }

    func queuePendingDeletion(_ relativePath: String) {
        var paths = pendingDeletions
        guard !paths.contains(relativePath) else { return }
        paths.append(relativePath)
        UserDefaults.standard.set(paths, forKey: pendingDeletionKey)
    }

    func retryPendingDeletions() {
        var remaining: [String] = []
        for path in pendingDeletions {
            guard let url = absoluteURL(forRelativePath: path) else { continue }
            if !fileManager.fileExists(atPath: url.path) { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                remaining.append(path)
            }
        }
        UserDefaults.standard.set(remaining, forKey: pendingDeletionKey)
    }

    func removeOrphanFiles(knownAudioPaths: Set<String>) throws -> (audio: Int, cache: Int) {
        var removedAudio = 0
        var removedCache = 0

        if let audioFiles = try? fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in audioFiles where url.pathExtension.lowercased() == "m4a" {
                let relative = "Audio/\(url.lastPathComponent)"
                if !knownAudioPaths.contains(relative) {
                    try? fileManager.removeItem(at: url)
                    removedAudio += 1
                }
            }
        }

        let knownIDs = Set(knownAudioPaths.compactMap { path -> String? in
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return name.isEmpty ? nil : name
        })

        for directory in [waveformDirectory, analysisDirectory] {
            if let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {
                for url in files {
                    let base = url.deletingPathExtension().lastPathComponent
                    let id = base.components(separatedBy: ".").first ?? base
                    if !knownIDs.contains(id) {
                        try? fileManager.removeItem(at: url)
                        removedCache += 1
                    }
                }
            }
        }

        return (removedAudio, removedCache)
    }

    // MARK: - 统计

    func stats(completion: @escaping (StorageStats) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var result = StorageStats()
            result.audioBytes = self.directorySize(self.audioDirectory)
            result.cacheBytes = self.directorySize(self.waveformDirectory) + self.directorySize(self.analysisDirectory)
            result.databaseBytes = self.directorySize(self.databaseDirectory)
            result.recordingCount = self.audioFileCount()

            if let values = try? self.baseDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let available = values.volumeAvailableCapacityForImportantUsage {
                result.availableBytes = available
            } else if let values = try? self.baseDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                      let available = values.volumeAvailableCapacity {
                result.availableBytes = Int64(available)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func availableBytes() -> Int64 {
        if let values = try? baseDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return available
        }
        return 0
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private func audioFileCount() -> Int {
        (try? fileManager.contentsOfDirectory(atPath: audioDirectory.path))?
            .filter { $0.lowercased().hasSuffix(".m4a") }
            .count ?? 0
    }

    func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    func audioDuration(at url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        return duration.isFinite ? max(0, duration) : 0
    }
}

enum StorageError: LocalizedError {
    case invalidPath
    case insufficientSpace
    case recordingUnreadable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "The storage location could not be determined."
        case .insufficientSpace:
            return "The device does not have enough free space."
        case .recordingUnreadable:
            return "The recording file could not be read."
        case .saveFailed:
            return "The data could not be saved."
        }
    }
}
