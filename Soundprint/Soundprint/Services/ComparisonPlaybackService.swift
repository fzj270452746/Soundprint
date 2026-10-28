//
//  ComparisonPlaybackService.swift
//  Soundprint
//
//  A/B 同步播放。两段音频独立解码，使用共同时间轴；时长不同时较短一轨自然结束。
//

import AVFoundation
import Foundation

final class ComparisonPlaybackService: NSObject {
    enum Mode {
        case both
        case aOnly
        case bOnly
    }

    var onUpdate: ((_ current: Double, _ duration: Double, _ isPlaying: Bool) -> Void)?
    var onFinish: (() -> Void)?

    private(set) var durationA: Double = 0
    private(set) var durationB: Double = 0
    private(set) var isPlaying = false
    var mode: Mode = .both {
        didSet { applyVolumes() }
    }
    private(set) var usesNormalization = false
    /// The selected common range. When nil, the whole recording is played.
    private(set) var playRange: ClosedRange<Double>?

    private var playerA: AVAudioPlayer?
    private var playerB: AVAudioPlayer?
    private var baseTime: Double = 0
    private var startUptime: TimeInterval?
    private var timer: Timer?
    private var gainA: Float = 1
    private var gainB: Float = 1
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    var maxDuration: Double { max(durationA, durationB) }

    var currentTime: Double {
        guard let startUptime else { return min(baseTime, maxDuration) }
        return min(maxDuration, baseTime + (ProcessInfo.processInfo.systemUptime - startUptime))
    }

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self?.pause() }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable else { return }
            self?.pause()
        }
    }

    deinit {
        timer?.invalidate()
        playerA?.stop()
        playerB?.stop()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    @discardableResult
    func load(aURL: URL, bURL: URL) -> Bool {
        timer?.invalidate()
        playerA?.stop()
        playerB?.stop()
        do {
            let a = try AVAudioPlayer(contentsOf: aURL)
            let b = try AVAudioPlayer(contentsOf: bURL)
            a.prepareToPlay()
            b.prepareToPlay()
            playerA = a
            playerB = b
            durationA = a.duration
            durationB = b.duration
            baseTime = 0
            startUptime = nil
            isPlaying = false
            applyVolumes()
            onUpdate?(0, maxDuration, false)
            return true
        } catch {
            playerA = nil
            playerB = nil
            durationA = 0
            durationB = 0
            return false
        }
    }

    func setPlayRange(_ range: ClosedRange<Double>?) {
        guard let range else {
            playRange = nil
            return
        }
        let lower = min(maxDuration, max(0, range.lowerBound))
        let upper = min(maxDuration, max(lower, range.upperBound))
        guard upper > lower else {
            playRange = nil
            return
        }
        let clamped = lower...upper
        playRange = clamped
        if !clamped.contains(currentTime) {
            seek(to: clamped.lowerBound)
        }
    }

    func setNormalization(enabled: Bool, rmsA: Double?, rmsB: Double?) {
        usesNormalization = enabled
        guard enabled, let rmsA, let rmsB else {
            gainA = 1
            gainB = 1
            applyVolumes()
            return
        }
        // 以较小 RMS + 3 dB 为目标，仅做衰减型音量对齐，避免削波。
        let target = min(rmsA, rmsB) + 3
        gainA = Self.gain(for: rmsA, target: target)
        gainB = Self.gain(for: rmsB, target: target)
        applyVolumes()
    }

    func play() {
        guard let playerA, let playerB else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            return
        }
        let activeRange = playRange ?? 0...maxDuration
        if currentTime >= activeRange.upperBound - 0.05 || currentTime < activeRange.lowerBound {
            baseTime = activeRange.lowerBound
            playerA.currentTime = min(activeRange.lowerBound, durationA)
            playerB.currentTime = min(activeRange.lowerBound, durationB)
        }
        let time = currentTime
        if time < durationA { playerA.currentTime = time; playerA.play() }
        if time < durationB { playerB.currentTime = time; playerB.play() }
        startUptime = ProcessInfo.processInfo.systemUptime
        if !isPlaying {
            baseTime = time
        }
        isPlaying = true
        applyVolumes()
        startTimer()
        onUpdate?(time, maxDuration, true)
    }

    func pause() {
        guard isPlaying else { return }
        baseTime = currentTime
        playerA?.pause()
        playerB?.pause()
        startUptime = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        applyVolumes()
        onUpdate?(baseTime, maxDuration, false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: Double) {
        let activeRange = playRange ?? 0...maxDuration
        let target = max(activeRange.lowerBound, min(activeRange.upperBound, time))
        baseTime = target
        if !isPlaying {
            playerA?.currentTime = min(target, durationA)
            playerB?.currentTime = min(target, durationB)
        } else {
            if target < durationA {
                playerA?.currentTime = target
                playerA?.play()
            } else {
                playerA?.pause()
            }
            if target < durationB {
                playerB?.currentTime = target
                playerB?.play()
            } else {
                playerB?.pause()
            }
            startUptime = ProcessInfo.processInfo.systemUptime
        }
        onUpdate?(target, maxDuration, isPlaying)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.currentTime
            let upperBound = self.playRange?.upperBound ?? self.maxDuration
            if current >= upperBound {
                self.playerA?.stop()
                self.playerB?.stop()
                self.isPlaying = false
                self.startUptime = nil
                self.baseTime = upperBound
                self.timer?.invalidate()
                self.timer = nil
                self.onUpdate?(upperBound, self.maxDuration, false)
                if self.playRange == nil {
                    self.onFinish?()
                }
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } else {
                self.onUpdate?(current, self.maxDuration, true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func applyVolumes() {
        let volumeA: Float
        let volumeB: Float
        switch mode {
        case .both:
            volumeA = gainA
            volumeB = gainB
        case .aOnly:
            volumeA = gainA
            volumeB = 0
        case .bOnly:
            volumeA = 0
            volumeB = gainB
        }
        playerA?.volume = volumeA
        playerB?.volume = volumeB
    }

    private static func gain(for rmsDBFS: Double, target: Double) -> Float {
        guard rmsDBFS.isFinite, rmsDBFS < 0 else { return 1 }
        let delta = target - rmsDBFS
        let linear = pow(10, delta / 20)
        return Float(min(1, max(0, linear)))
    }
}
