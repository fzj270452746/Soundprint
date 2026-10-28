//
//  PlaybackService.swift
//  Soundprint
//
//  单轨播放。所有处理均在本地，切换录音时不会改动原始文件。
//

import AVFoundation
import Foundation

final class PlaybackService: NSObject {
    enum State: Equatable {
        case idle
        case playing
        case paused
        case finished
        case failed(String)
    }

    var onUpdate: ((_ currentTime: Double, _ duration: Double, _ isPlaying: Bool) -> Void)?
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var url: URL?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

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
        player?.stop()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    @discardableResult
    func load(url: URL) -> Bool {
        stopTimer()
        player?.stop()
        self.url = url
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = false
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            currentTime = 0
            state = .idle
            onUpdate?(0, duration, false)
            return true
        } catch {
            self.player = nil
            duration = 0
            currentTime = 0
            state = .failed("The audio could not be loaded.")
            onUpdate?(0, 0, false)
            return false
        }
    }

    func togglePlayback() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            state = .failed("The audio could not be played.")
            return
        }
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
            currentTime = 0
        }
        guard player.play() else {
            state = .failed("The audio could not be played.")
            return
        }
        state = .playing
        startTimer()
        onUpdate?(player.currentTime, player.duration, true)
    }

    func pause() {
        guard let player, state == .playing else { return }
        player.pause()
        currentTime = player.currentTime
        state = .paused
        stopTimer()
        onUpdate?(currentTime, duration, false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        stopTimer()
        state = .idle
        onUpdate?(0, duration, false)
    }

    func seek(to time: Double) {
        guard let player else { return }
        let target = max(0, min(duration, time))
        player.currentTime = target
        currentTime = target
        if state == .finished {
            state = .paused
        }
        onUpdate?(target, duration, state == .playing)
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            self.onUpdate?(player.currentTime, self.duration, self.state == .playing)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension PlaybackService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopTimer()
        currentTime = duration
        state = flag ? .finished : .failed("Playback stopped partway.")
        onUpdate?(duration, duration, false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopTimer()
        state = .failed("An error occurred during playback.")
        onUpdate?(player.currentTime, duration, false)
    }
}
