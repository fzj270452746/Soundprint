//
//  EventSuggestionService.swift
//  Soundprint
//
//  基于端内波形能量的“声音变化”候选检测。候选不是自动确认的事件，
//  也不是语义识别结论；用户必须手动确认后才会写入事件时间线。
//

import Foundation

struct EventSuggestion: Codable, Identifiable, Hashable {
    var id: UUID
    var startTime: Double
    var endTime: Double
    var strength: Double
    var title: String

    var duration: Double { max(0, endTime - startTime) }

    var strengthLabel: String {
        "Relative strength \(Int((max(0, min(1, strength)) * 100).rounded()))%"
    }
}

private struct EventSuggestionCache: Codable {
    var version: Int
    var generatedAt: Date
    var suggestions: [EventSuggestion]
}

final class EventSuggestionService {
    static let shared = EventSuggestionService()

    private let storage = StorageManager.shared
    private let library = LibraryService.shared
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.soundprint.event-suggestions"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var pending = Set<UUID>()
    private let lock = NSLock()

    private init() {}

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: SPDefaultsKey.suggestEvents) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: SPDefaultsKey.suggestEvents)
    }

    // MARK: - 调度

    func schedule(recordingID: UUID, force: Bool = false) {
        DispatchQueue.main.async {
            guard Self.isEnabled else { return }
            guard let record = self.library.fetchRecording(id: recordingID) else { return }
            guard let waveformPath = record.waveformRelativePath,
                  let waveformURL = self.storage.absoluteURL(forRelativePath: waveformPath),
                  FileManager.default.fileExists(atPath: waveformURL.path) else { return }

            if !force, self.hasCache(for: record) { return }

            self.lock.lock()
            let alreadyQueued = self.pending.contains(recordingID)
            if !alreadyQueued { self.pending.insert(recordingID) }
            self.lock.unlock()
            guard !alreadyQueued else { return }

            let duration = record.duration
            let suggestionPath = self.storage.relativePathSuggestions(for: recordingID)
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let self, operation?.isCancelled == false else { return }
                self.process(
                    recordingID: recordingID,
                    waveformPath: waveformPath,
                    duration: duration,
                    suggestionPath: suggestionPath
                )
            }
            self.queue.addOperation(operation)
        }
    }

    func scheduleAllIfNeeded() {
        guard Self.isEnabled else { return }
        let records = library.fetchRecordings()
        for record in records {
            schedule(recordingID: record.id, force: false)
        }
    }

    // MARK: - 读取与忽略

    func suggestions(for record: RecordingEntity) -> [EventSuggestion] {
        guard Self.isEnabled else { return [] }
        guard let path = record.waveformRelativePath, !path.isEmpty else { return [] }
        guard let cache = storage.read(EventSuggestionCache.self, fromRelativePath: storage.relativePathSuggestions(for: record.id)) else {
            return []
        }
        return cache.suggestions
    }

    func discard(suggestionID: UUID, for record: RecordingEntity) {
        let path = storage.relativePathSuggestions(for: record.id)
        guard var cache = storage.read(EventSuggestionCache.self, fromRelativePath: path) else { return }
        cache.suggestions.removeAll { $0.id == suggestionID }
        try? storage.write(cache, toRelativePath: path)
        NotificationCenter.default.post(name: SPNotification.suggestionsDidChange, object: nil)
    }

    func clear(for recordingID: UUID) {
        storage.deleteRelativeFile(storage.relativePathSuggestions(for: recordingID))
    }

    private func hasCache(for record: RecordingEntity) -> Bool {
        guard let url = storage.suggestionsURL(for: record) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 生成

    private func process(recordingID: UUID, waveformPath: String, duration: Double, suggestionPath: String) {
        defer {
            lock.lock()
            pending.remove(recordingID)
            lock.unlock()
        }
        guard let waveform = storage.read(WaveformCache.self, fromRelativePath: waveformPath) else { return }
        let suggestions = Self.detectSuggestions(
            buckets: waveform.buckets,
            duration: max(duration, waveform.duration)
        )
        let cache = EventSuggestionCache(
            version: 1,
            generatedAt: Date(),
            suggestions: suggestions
        )
        try? storage.write(cache, toRelativePath: suggestionPath)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SPNotification.suggestionsDidChange, object: nil)
        }
    }

    // MARK: - 检测算法

    static func detectSuggestions(buckets: [WaveformBucket], duration: Double) -> [EventSuggestion] {
        guard buckets.count >= 8, duration > 0.5 else { return [] }
        let bucketDuration = duration / Double(buckets.count)
        let raw = buckets.map { Double($0.rms) }

        // 约 0.25 秒平滑，避免单帧抖动。
        let smoothCount = max(1, Int(0.25 / max(0.001, bucketDuration)))
        var smoothed = [Double](repeating: 0, count: raw.count)
        for index in raw.indices {
            let lower = max(0, index - smoothCount)
            let upper = min(raw.count - 1, index + smoothCount)
            var sum: Double = 0
            for i in lower...upper { sum += raw[i] }
            smoothed[index] = sum / Double(upper - lower + 1)
        }

        // 约 ±2.5 秒的局部基线；中位数比平均值更不容易被短促声音抬高。
        let baselineRadius = max(3, Int(2.5 / max(0.001, bucketDuration)))
        var baseline = [Double](repeating: 0, count: smoothed.count)
        for index in smoothed.indices {
            let lower = max(0, index - baselineRadius)
            let upper = min(smoothed.count - 1, index + baselineRadius)
            let window = smoothed[lower...upper].sorted()
            let median: Double
            if window.count % 2 == 0 {
                median = (window[window.count / 2 - 1] + window[window.count / 2]) / 2
            } else {
                median = window[window.count / 2]
            }
            baseline[index] = max(0.004, median)
        }

        var suggestions: [EventSuggestion] = []
        var index = 0
        while index < smoothed.count {
            let ratio = smoothed[index] / baseline[index]
            guard ratio >= 1.5, smoothed[index] >= 0.018 else {
                index += 1
                continue
            }

            let startIndex = index
            var peakRatio = ratio
            var lastAbove = index
            var quietCount = 0
            while index < smoothed.count {
                let currentRatio = smoothed[index] / baseline[index]
                if currentRatio >= 1.5 {
                    peakRatio = max(peakRatio, currentRatio)
                    lastAbove = index
                    quietCount = 0
                } else if currentRatio >= 1.18 {
                    quietCount = 0
                } else {
                    quietCount += 1
                    if quietCount >= 2 { break }
                }
                index += 1
                if Double(index - startIndex) * bucketDuration > 14 { break }
            }

            let startTime = Double(startIndex) * bucketDuration
            let endTime = min(duration, Double(lastAbove + 1) * bucketDuration)
            let candidateDuration = endTime - startTime
            index = max(index, lastAbove + 1)

            guard candidateDuration >= 0.35,
                  endTime <= duration + 0.01,
                  endTime - startTime < duration * 0.8 else { continue }

            let strength = min(0.96, max(0.25,
                0.28 + 0.30 * min(1.0, log2(max(1.01, peakRatio)) / 2.0)
                + 0.22 * min(1.0, candidateDuration / 3.0)
            ))

            suggestions.append(EventSuggestion(
                id: UUID(),
                startTime: max(0, startTime),
                endTime: max(startTime + 0.3, endTime),
                strength: strength,
                title: "Sound Change"
            ))
        }

        // 合并距离过近的候选，避免时间线拥挤。
        var merged: [EventSuggestion] = []
        for suggestion in suggestions.sorted(by: { $0.startTime < $1.startTime }) {
            if let last = merged.last, suggestion.startTime <= last.endTime + 0.5 {
                var combined = last
                combined.endTime = max(last.endTime, suggestion.endTime)
                combined.strength = max(last.strength, suggestion.strength)
                merged[merged.count - 1] = combined
            } else {
                merged.append(suggestion)
            }
        }

        return Array(merged.prefix(10))
    }
}
