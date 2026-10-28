//
//  RecordingService.swift
//  Soundprint
//
//  录音状态机。计时使用单调时钟，暂停期间不会累加有效时长。
//

import AVFoundation
import Foundation
import UIKit
import os.log

struct RecordingResult {
    let id: UUID
    let temporaryURL: URL
    let duration: Double
    let sampleRate: Double
    let channelCount: Int
    let createdAt: Date
    let markers: [RecordingMarker]
    let placeID: UUID?
    let quality: RecordingQuality
}

final class RecordingService: NSObject {
    var onStateChange: ((RecordingState) -> Void)?
    var onUpdate: ((_ elapsed: Double, _ level: Float, _ history: [Float]) -> Void)?
    var onInterruption: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var state: RecordingState = .idle {
        didSet {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in self?.onStateChange?(self?.state ?? .idle) }
                return
            }
            onStateChange?(state)
        }
    }

    private(set) var markers: [RecordingMarker] = []
    private(set) var sessionID = UUID()
    private(set) var startedAt = Date()

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var temporaryURL: URL?
    private var selectedPlaceID: UUID?
    private var quality: RecordingQuality = RecordingQuality.current
    private var accumulatedTime: TimeInterval = 0
    private var segmentStartUptime: TimeInterval?
    private var smoothedLevel: Float = 0
    private var levelHistory = [Float](repeating: 0, count: 42)
    private var lastSpaceCheck = Date.distantPast
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var isFinishing = false

    var currentElapsed: TimeInterval {
        accumulatedTime + (segmentStartUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0)
    }

    override init() {
        super.init()
        registerNotifications()
    }

    deinit {
        timer?.invalidate()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 权限

    func requestPermission(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - 开始

    /// placeID 可为空；录音结束后仍可在保存页关联地点。
    func start(placeID: UUID?) {
        guard !state.isActive else { return }
        selectedPlaceID = placeID
        quality = RecordingQuality.current
        markers = []
        accumulatedTime = 0
        segmentStartUptime = nil
        smoothedLevel = 0
        levelHistory = [Float](repeating: 0, count: 42)
        isFinishing = false
        sessionID = UUID()
        startedAt = Date()
        state = .preparing

        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.state = .failed("Microphone access is not allowed.")
                self.onError?("Allow Soundprint to use the microphone in the Settings app.")
                return
            }
            self.beginRecording()
        }
    }

    private func beginRecording() {
        guard StorageManager.shared.availableBytes() > 220_000_000 else {
            state = .failed("Not enough free space.")
            onError?("Free up storage on this device, then try again.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true, options: [])
        } catch {
            state = .failed("Recording could not start.")
            onError?("The audio session could not start. Close other apps and try again.")
            return
        }

        let url = StorageManager.shared.newTemporaryRecordingURL(id: sessionID)
        temporaryURL = url

        do {
            let recorder = try AVAudioRecorder(url: url, settings: quality.recorderSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecordingError.startFailed
            }
            self.recorder = recorder
            segmentStartUptime = ProcessInfo.processInfo.systemUptime
            state = .recording
            startTimer()
            persistDraft()
            SPHaptic.medium()
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            state = .failed("Recording could not start.")
            onError?("The recording file could not be prepared. Check free space and microphone status.")
            os_log("Recording start failed: %{public}@", log: .default, type: .error, String(describing: error))
        }
    }

    // MARK: - 暂停 / 继续 / 停止

    func pause() {
        guard state == .recording, let recorder else { return }
        recorder.pause()
        if let start = segmentStartUptime {
            accumulatedTime += ProcessInfo.processInfo.systemUptime - start
        }
        segmentStartUptime = nil
        state = .paused
        stopTimer()
        updateLevelAndNotify()
        persistDraft()
        SPHaptic.light()
    }

    func resume() {
        guard state == .paused, let recorder else { return }
        // 恢复前再次确认空间。
        guard StorageManager.shared.availableBytes() > 80_000_000 else {
            onInterruption?("Cannot resume because storage is running low.")
            return
        }
        guard recorder.record() else {
            onError?("Recording could not resume.")
            return
        }
        segmentStartUptime = ProcessInfo.processInfo.systemUptime
        state = .recording
        startTimer()
        persistDraft()
        SPHaptic.medium()
    }

    func addMarker(kind: EventKind, title: String? = nil) {
        guard state == .recording || state == .paused else { return }
        let marker = RecordingMarker(
            id: UUID(),
            time: currentElapsed,
            kind: kind,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (title ?? kind.title)
                : kind.title
        )
        markers.append(marker)
        persistDraft()
        SPHaptic.success()
    }

    func removeLastMarker() {
        guard !markers.isEmpty else { return }
        markers.removeLast()
        persistDraft()
    }

    func stop(completion: @escaping (Result<RecordingResult, Error>) -> Void) {
        guard state == .recording || state == .paused, let recorder, let url = temporaryURL else {
            completion(.failure(RecordingError.notRecording))
            return
        }
        guard !isFinishing else { return }
        isFinishing = true

        if let start = segmentStartUptime {
            accumulatedTime += ProcessInfo.processInfo.systemUptime - start
        }
        segmentStartUptime = nil
        stopTimer()
        recorder.stop()
        self.recorder = nil
        state = .finalizing

        let elapsed = accumulatedTime
        let captureID = sessionID
        let captureDate = startedAt
        let captureMarkers = markers
        let capturePlace = selectedPlaceID
        let captureQuality = quality
        let expectedRate = captureQuality.sampleRate

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 512 else { throw RecordingError.emptyFile }

                var duration = elapsed
                var sampleRate = expectedRate
                var channels = 1
                if let file = try? AVAudioFile(forReading: url) {
                    sampleRate = file.processingFormat.sampleRate
                    channels = Int(file.processingFormat.channelCount)
                    if sampleRate > 0, file.length > 0 {
                        duration = Double(file.length) / sampleRate
                    }
                } else {
                    let asset = AVURLAsset(url: url)
                    let assetDuration = CMTimeGetSeconds(asset.duration)
                    if assetDuration.isFinite, assetDuration > 0 {
                        duration = assetDuration
                    }
                }
                guard duration > 0.05 else { throw RecordingError.tooShort }

                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let result = RecordingResult(
                        id: captureID,
                        temporaryURL: url,
                        duration: duration,
                        sampleRate: sampleRate,
                        channelCount: channels,
                        createdAt: captureDate,
                        markers: captureMarkers,
                        placeID: capturePlace,
                        quality: captureQuality
                    )
                    self.state = .idle
                    self.isFinishing = false
                    self.persistDraft(finalDuration: duration)
                    completion(.success(result))
                }
            } catch {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.state = .failed("The recording could not be saved.")
                    self.isFinishing = false
                    completion(.failure(error))
                }
            }
        }
    }

    /// 丢弃本次录音草稿（取消保存时调用）。
    func discardSession() {
        guard !state.isActive else { return }
        if let url = temporaryURL {
            try? FileManager.default.removeItem(at: url)
        }
        RecordingDraftStore.shared.clear()
        temporaryURL = nil
        markers = []
        state = .idle
    }

    /// 保存成功后调用，清理崩溃恢复草稿记录。
    func markSessionSaved() {
        RecordingDraftStore.shared.clear()
        temporaryURL = nil
        markers = []
    }

    // MARK: - 计时与电平

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .recording, let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // -60 dB 以下视为静音；开方压缩让低电平也可见。
        let linear = pow(10, power / 20)
        let target = min(1, max(0, sqrt(linear) * 1.25))
        smoothedLevel = smoothedLevel * 0.72 + target * 0.28
        levelHistory.removeFirst()
        levelHistory.append(smoothedLevel)

        if Date().timeIntervalSince(lastSpaceCheck) > 5 {
            lastSpaceCheck = Date()
            if StorageManager.shared.availableBytes() < 40_000_000 {
                pause()
                onInterruption?("Recording paused because storage is running low.")
            }
        }
        onUpdate?(currentElapsed, smoothedLevel, levelHistory)
    }

    private func updateLevelAndNotify() {
        onUpdate?(currentElapsed, smoothedLevel, levelHistory)
    }

    private func persistDraft(finalDuration: Double? = nil) {
        guard let url = temporaryURL else { return }
        let draft = StoredRecordingDraft(
            id: sessionID,
            fileName: url.lastPathComponent,
            placeID: selectedPlaceID,
            createdAt: startedAt,
            quality: quality,
            markers: markers,
            elapsed: finalDuration ?? currentElapsed
        )
        RecordingDraftStore.shared.save(draft)
    }

    // MARK: - 系统中断

    private func registerNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            guard state == .recording else { return }
            pause()
            onInterruption?("Recording paused for a call or other interruption. Audio already recorded is preserved.")
        case .ended:
            if state == .paused {
                onInterruption?("Recording can now resume.")
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .oldDeviceUnavailable, .override, .routeConfigurationChange:
            guard state == .recording else { return }
            pause()
            onInterruption?("Recording paused because the input device changed.")
        default:
            break
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.segmentStartUptime = nil
            self.state = .failed("An error occurred while writing the recording.")
            self.onError?("A problem occurred while saving the recording. The file is preserved as far as possible.")
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // 停止流程由 stop(completion:) 处理，此处只处理异常结束。
        guard flag == false, !isFinishing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.segmentStartUptime = nil
            self.state = .failed("Recording ended early.")
            self.onError?("Recording ended unexpectedly. The saved portion is preserved.")
        }
    }
}

// MARK: - 录音草稿（崩溃恢复）

struct StoredRecordingDraft: Codable {
    var id: UUID
    var fileName: String
    var placeID: UUID?
    var createdAt: Date
    var quality: RecordingQuality
    var markers: [RecordingMarker]
    var elapsed: Double
}

struct RecoveredRecording {
    let draft: StoredRecordingDraft
    let temporaryURL: URL
    let duration: Double
    let sampleRate: Double
    let channelCount: Int
}

final class RecordingDraftStore {
    static let shared = RecordingDraftStore()

    private var draftURL: URL {
        StorageManager.shared.recordingDraftsDirectory.appendingPathComponent("draft.json")
    }

    private init() {}

    func save(_ draft: StoredRecordingDraft) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(draft) {
            try? data.write(to: draftURL, options: .atomic)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: draftURL)
    }

    /// 启动时尝试恢复崩溃或强制退出前的录音。
    func recoverIfNeeded() -> RecoveredRecording? {
        guard let data = try? Data(contentsOf: draftURL),
              let draft = try? JSONDecoder().decode(StoredRecordingDraft.self, from: data) else {
            return nil
        }
        let url = StorageManager.shared.recordingDraftsDirectory.appendingPathComponent(draft.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            clear()
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 512 else {
            clear()
            return nil
        }

        guard let file = try? AVAudioFile(forReading: url) else {
            // Do not mistake an unfinished m4a for a “playable” file.
            try? FileManager.default.removeItem(at: url)
            clear()
            return nil
        }
        let sampleRate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        guard sampleRate > 0, file.length > 0 else {
            try? FileManager.default.removeItem(at: url)
            clear()
            return nil
        }
        let duration = Double(file.length) / sampleRate
        guard duration > 0.1 else {
            clear()
            return nil
        }
        return RecoveredRecording(
            draft: draft,
            temporaryURL: url,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channels
        )
    }
}

// MARK: - 设置

extension RecordingQuality {
    static var current: RecordingQuality {
        guard let raw = UserDefaults.standard.string(forKey: SPDefaultsKey.recordingQuality),
              let quality = RecordingQuality(rawValue: raw) else {
            return .standard
        }
        return quality
    }

    static func setCurrent(_ quality: RecordingQuality) {
        UserDefaults.standard.set(quality.rawValue, forKey: SPDefaultsKey.recordingQuality)
    }
}

enum RecordingError: LocalizedError {
    case startFailed
    case notRecording
    case emptyFile
    case tooShort

    var errorDescription: String? {
        switch self {
        case .startFailed: return "Recording could not start."
        case .notRecording: return "Not currently recording."
        case .emptyFile: return "The recording file is empty."
        case .tooShort: return "The recording is too short."
        }
    }
}
