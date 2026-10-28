//
//  AudioAnalysisService.swift
//  Soundprint
//
//  使用 AVAssetReader 与 Accelerate 在本地生成波形、RMS、峰值、频带能量和简化声谱图。
//  分析结果写入可重建缓存，原始录音永远不会被修改。
//

import Accelerate
import AVFoundation
import Foundation

// MARK: - 缓存数据结构

struct WaveformBucket: Codable {
    var min: Float
    var max: Float
    var rms: Float
}

struct WaveformCache: Codable {
    var version: Int
    var duration: Double
    var sampleRate: Double
    var channels: Int
    var peak: Float
    var rms: Float
    var buckets: [WaveformBucket]

    var normalizedPeak: Float { max(0.0001, peak) }
}

struct BandShares: Codable {
    var low: Double
    var mid: Double
    var high: Double

    static let empty = BandShares(low: 0, mid: 0, high: 0)
}

struct AudioAnalysisSummary: Codable {
    var algorithmVersion: String
    var duration: Double
    var sampleRate: Double
    var channels: Int
    var peak: Double
    var peakDBFS: Double
    var rmsMean: Double
    var rmsDBFS: Double
    var rmsTimeline: [Float]
    var timelineInterval: Double
    var bands: BandShares
    var windowSize: Int
    var hopSize: Int
    var createdAt: Date
}

struct SpectrogramCache: Codable {
    var version: Int
    var columns: Int
    var bands: Int
    var duration: Double
    var minFrequency: Double
    var maxFrequency: Double
    /// 按频带优先存储：index = band * columns + column。
    var values: [Float]
}

// MARK: - 分析协调器

final class AudioAnalysisService {
    static let shared = AudioAnalysisService()

    static let algorithmVersion = "1.0"

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.soundprint.analysis"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    private let storage = StorageManager.shared
    private let library = LibraryService.shared
    private var queuedIDs = Set<UUID>()
    private let stateLock = NSLock()

    private let waveformMemoryCache = NSCache<NSString, WaveformBox>()
    private let analysisMemoryCache = NSCache<NSString, AnalysisBox>()
    private let spectrogramMemoryCache = NSCache<NSString, SpectrogramBox>()

    private init() {
        waveformMemoryCache.countLimit = 40
        analysisMemoryCache.countLimit = 40
        spectrogramMemoryCache.countLimit = 12
    }

    // MARK: - 调度

    func schedule(recordingID: UUID, force: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.enqueueOnMain(recordingID: recordingID, force: force)
        }
    }

    private func enqueueOnMain(recordingID: UUID, force: Bool) {
        guard let record = library.fetchRecording(id: recordingID) else { return }
        guard let audioURL = storage.audioURL(for: record),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            library.setAnalysisState(.failed, for: recordingID)
            return
        }

        let autoAnalysis = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
        let deep = force || autoAnalysis
        let hasWaveform: Bool = {
            guard let path = record.waveformRelativePath,
                  let url = storage.absoluteURL(forRelativePath: path) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }()

        stateLock.lock()
        let isQueued = queuedIDs.contains(recordingID)
        stateLock.unlock()

        if isQueued { return }
        if !force {
            if record.analysisState == .ready { return }
            if !deep && hasWaveform { return }
        }

        stateLock.lock()
        queuedIDs.insert(recordingID)
        stateLock.unlock()

        if deep {
            library.setAnalysisState(.processing, for: recordingID)
        }

        let job = AnalysisJob(
            recordingID: recordingID,
            audioURL: audioURL,
            deepAnalysis: deep
        )

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, operation?.isCancelled == false else { return }
            self.run(job: job)
        }
        queue.addOperation(operation)
    }

    private func run(job: AnalysisJob) {
        var waveformPath: String?
        do {
            let waveform = try WaveformGenerator.generate(url: job.audioURL)
            let waveformRelative = storage.relativePathWaveform(for: job.recordingID)
            try storage.write(waveform, toRelativePath: waveformRelative)
            waveformPath = waveformRelative

            guard job.deepAnalysis else {
                DispatchQueue.main.async {
                    self.finishWaveformOnly(job: job, waveformPath: waveformRelative)
                }
                return
            }

            let spectrum = try SpectrogramGenerator.generate(url: job.audioURL, duration: waveform.duration)
            let spectrogramRelative = storage.relativePathSpectrogram(for: job.recordingID)
            try storage.write(spectrum.cache, toRelativePath: spectrogramRelative)

            let timeline = Self.makeTimeline(from: waveform)
            let summary = AudioAnalysisSummary(
                algorithmVersion: Self.algorithmVersion,
                duration: waveform.duration,
                sampleRate: waveform.sampleRate,
                channels: waveform.channels,
                peak: Double(waveform.peak),
                peakDBFS: Self.dbFS(Double(waveform.peak)),
                rmsMean: Double(waveform.rms),
                rmsDBFS: Self.dbFS(Double(waveform.rms)),
                rmsTimeline: timeline.values,
                timelineInterval: timeline.interval,
                bands: spectrum.bandShares,
                windowSize: SpectrogramGenerator.fftSize,
                hopSize: spectrum.hopSize,
                createdAt: Date()
            )

            let analysisRelative = storage.relativePathAnalysis(for: job.recordingID)
            try storage.write(summary, toRelativePath: analysisRelative)

            DispatchQueue.main.async {
                self.finishDeep(job: job, summary: summary, waveformPath: waveformPath, analysisPath: analysisRelative, spectrogramPath: spectrogramRelative)
            }
        } catch {
            DispatchQueue.main.async {
                self.finishFailure(job: job, waveformPath: waveformPath)
            }
        }
    }

    private func finishWaveformOnly(job: AnalysisJob, waveformPath: String) {
        let auto = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
        library.updateAnalysisMetadata(
            for: job.recordingID,
            waveformPath: waveformPath,
            analysisResult: nil,
            analysisPath: nil,
            spectrogramPath: nil
        )
        if auto {
            // 正常情况下不会发生；若设置被切换，安排完整分析。
            schedule(recordingID: job.recordingID, force: false)
        }
        removeQueued(job.recordingID)
        invalidateMemoryCache(id: job.recordingID)
        EventSuggestionService.shared.schedule(recordingID: job.recordingID, force: false)
    }

    private func finishDeep(
        job: AnalysisJob,
        summary: AudioAnalysisSummary,
        waveformPath: String?,
        analysisPath: String,
        spectrogramPath: String?
    ) {
        library.updateAnalysisMetadata(
            for: job.recordingID,
            waveformPath: waveformPath,
            analysisResult: summary,
            analysisPath: analysisPath,
            spectrogramPath: spectrogramPath
        )
        removeQueued(job.recordingID)
        invalidateMemoryCache(id: job.recordingID)
        EventSuggestionService.shared.schedule(recordingID: job.recordingID, force: false)
    }

    private func finishFailure(job: AnalysisJob, waveformPath: String?) {
        if let waveformPath {
            library.updateWaveformPath(for: job.recordingID, path: waveformPath)
        }
        library.setAnalysisState(.failed, for: job.recordingID)
        removeQueued(job.recordingID)
        invalidateMemoryCache(id: job.recordingID)
    }

    private func removeQueued(_ id: UUID) {
        stateLock.lock()
        queuedIDs.remove(id)
        stateLock.unlock()
    }

    private func invalidateMemoryCache(id: UUID) {
        let key = id.uuidString as NSString
        waveformMemoryCache.removeObject(forKey: key)
        analysisMemoryCache.removeObject(forKey: key)
        spectrogramMemoryCache.removeObject(forKey: key)
    }

    // MARK: - 读取缓存

    func waveform(for record: RecordingEntity) -> WaveformCache? {
        let key = record.id.uuidString as NSString
        if let cached = waveformMemoryCache.object(forKey: key) { return cached.value }
        guard let path = record.waveformRelativePath,
              let value = storage.read(WaveformCache.self, fromRelativePath: path) else { return nil }
        waveformMemoryCache.setObject(WaveformBox(value), forKey: key)
        return value
    }

    func analysis(for record: RecordingEntity) -> AudioAnalysisSummary? {
        let key = record.id.uuidString as NSString
        if let cached = analysisMemoryCache.object(forKey: key) { return cached.value }
        guard let path = record.analysis?.analysisRelativePath,
              !path.isEmpty,
              let value = storage.read(AudioAnalysisSummary.self, fromRelativePath: path) else { return nil }
        analysisMemoryCache.setObject(AnalysisBox(value), forKey: key)
        return value
    }

    func spectrogram(for record: RecordingEntity) -> SpectrogramCache? {
        let key = record.id.uuidString as NSString
        if let cached = spectrogramMemoryCache.object(forKey: key) { return cached.value }
        guard let path = record.analysis?.spectrogramRelativePath,
              let value = storage.read(SpectrogramCache.self, fromRelativePath: path) else { return nil }
        spectrogramMemoryCache.setObject(SpectrogramBox(value), forKey: key)
        return value
    }

    func invalidateCaches() {
        waveformMemoryCache.removeAllObjects()
        analysisMemoryCache.removeAllObjects()
        spectrogramMemoryCache.removeAllObjects()
    }

    // MARK: - 工具

    static func dbFS(_ linear: Double) -> Double {
        guard linear > 0 else { return -120 }
        return 20 * log10(max(linear, 0.000001))
    }

    /// 将波形桶的 RMS 聚合为不超过 360 个时间点，供图表使用。
    private static func makeTimeline(from waveform: WaveformCache) -> (values: [Float], interval: Double) {
        guard !waveform.buckets.isEmpty else { return ([], 0.25) }
        let target = min(360, max(40, waveform.buckets.count))
        let stride = max(1, Int(ceil(Double(waveform.buckets.count) / Double(target))))
        var values: [Float] = []
        var index = 0
        while index < waveform.buckets.count {
            let end = min(index + stride, waveform.buckets.count)
            var sum: Double = 0
            for bucket in waveform.buckets[index..<end] {
                sum += Double(bucket.rms) * Double(bucket.rms)
            }
            let rms = sqrt(sum / Double(end - index))
            values.append(Float(rms))
            index = end
        }
        let interval = values.isEmpty ? 0.25 : waveform.duration / Double(values.count)
        return (values, interval)
    }
}

// MARK: - 任务

private struct AnalysisJob {
    let recordingID: UUID
    let audioURL: URL
    let deepAnalysis: Bool
}

// MARK: - 波形分析

private enum WaveformGenerator {
    static func generate(url: URL) throws -> WaveformCache {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AnalysisError.noAudioTrack
        }
        let estimatedDuration = max(0, CMTimeGetSeconds(asset.duration))
        guard estimatedDuration > 0 else { throw AnalysisError.unreadable }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AnalysisError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw AnalysisError.unreadable }

        let bucketCount = min(1_800, max(320, Int(estimatedDuration * 12)))
        let timelineCount = 240
        let estimatedFrames = estimatedDuration * Double(max(1, track.naturalTimeScale))
        let bucketFrames = max(1, estimatedFrames / Double(bucketCount))
        let timelineFrames = max(1, estimatedFrames / Double(timelineCount))

        var mins = [Float](repeating: .greatestFiniteMagnitude, count: bucketCount)
        var maxs = [Float](repeating: -.greatestFiniteMagnitude, count: bucketCount)
        var bucketSquares = [Double](repeating: 0, count: bucketCount)
        var bucketCounts = [Int](repeating: 0, count: bucketCount)
        var timelineSquares = [Double](repeating: 0, count: timelineCount)
        var timelineCounts = [Int](repeating: 0, count: timelineCount)

        var globalFrame: Int64 = 0
        var peak: Float = 0
        var totalSquares: Double = 0
        var totalSamples: Int64 = 0
        var sampleRate: Double = 0
        var channels = 0
        var sawBuffer = false

        while let sample = output.copyNextSampleBuffer() {
            guard let format = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                continue
            }
            if sampleRate == 0 { sampleRate = asbd.mSampleRate }
            let channelCount = max(1, Int(asbd.mChannelsPerFrame))
            channels = max(channels, channelCount)

            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else { continue }
            let frameCount = min(CMSampleBufferGetNumSamples(sample), length / (MemoryLayout<Float>.size * channelCount))
            guard frameCount > 0 else { continue }
            sawBuffer = true

            let floats = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                var mono: Float = 0
                let base = frame * channelCount
                for channel in 0..<channelCount {
                    mono += floats[base + channel]
                }
                mono /= Float(channelCount)
                let amplitude = abs(mono)
                if amplitude > peak { peak = amplitude }

                let absolute = globalFrame + Int64(frame)
                let bucket = min(bucketCount - 1, max(0, Int(Double(absolute) / bucketFrames)))
                if mono < mins[bucket] { mins[bucket] = mono }
                if mono > maxs[bucket] { maxs[bucket] = mono }
                let square = Double(mono) * Double(mono)
                bucketSquares[bucket] += square
                bucketCounts[bucket] += 1

                let timelineIndex = min(timelineCount - 1, max(0, Int(Double(absolute) / timelineFrames)))
                timelineSquares[timelineIndex] += square
                timelineCounts[timelineIndex] += 1
                totalSquares += square
                totalSamples += 1
            }
            globalFrame += Int64(frameCount)
        }

        guard reader.status == .completed, sawBuffer, totalSamples > 0 else {
            throw AnalysisError.unreadable
        }

        let actualDuration = sampleRate > 0 ? Double(totalSamples) / sampleRate : estimatedDuration
        var buckets: [WaveformBucket] = []
        buckets.reserveCapacity(bucketCount)
        for index in 0..<bucketCount {
            let count = bucketCounts[index]
            if count == 0 {
                buckets.append(WaveformBucket(min: 0, max: 0, rms: 0))
            } else {
                let rms = Float(sqrt(bucketSquares[index] / Double(count)))
                buckets.append(WaveformBucket(
                    min: max(-1, mins[index]),
                    max: min(1, maxs[index]),
                    rms: rms
                ))
            }
        }

        let overallRMS = Float(sqrt(totalSquares / Double(totalSamples)))
        return WaveformCache(
            version: 1,
            duration: actualDuration,
            sampleRate: sampleRate > 0 ? sampleRate : 44_100,
            channels: max(1, channels),
            peak: min(1, peak),
            rms: overallRMS,
            buckets: buckets
        )
    }
}

// MARK: - 声谱图与频带

private enum SpectrogramGenerator {
    static let fftSize = 1024
    private static let displayBands = 48
    private static let maxColumns = 180
    private static let minFrequency = 40.0

    struct Output {
        let cache: SpectrogramCache
        let bandShares: BandShares
        let hopSize: Int
    }

    static func generate(url: URL, duration: Double) throws -> Output {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AnalysisError.noAudioTrack
        }
        let estimatedDuration = max(duration, CMTimeGetSeconds(asset.duration))
        guard estimatedDuration > 0 else { throw AnalysisError.unreadable }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AnalysisError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw AnalysisError.unreadable }

        let n = fftSize
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(n))), FFTRadix(kFFTRadix2)) else {
            throw AnalysisError.processingFailed
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var real = [Float](repeating: 0, count: n / 2)
        var imaginary = [Float](repeating: 0, count: n / 2)

        var sampleRate: Double = 44_100
        var channelCount = 1
        var didReadFormat = false
        var hop = n
        var nextWindowStart: Int64 = 0
        var pending: [Float] = []
        pending.reserveCapacity(n * 4)
        var pendingStart: Int64 = 0
        var rawColumns: [[Float]] = []
        var lowPower: Double = 0
        var midPower: Double = 0
        var highPower: Double = 0
        var bandRanges: [(Int, Int)] = []

        while let sample = output.copyNextSampleBuffer() {
            guard let format = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                continue
            }
            if !didReadFormat {
                sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44_100
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
                let totalEstimated = estimatedDuration * sampleRate
                hop = max(n, Int(totalEstimated / Double(maxColumns)))
                // 根据实际采样率准备频带边界。
                bandRanges = makeBandRanges(sampleRate: sampleRate, fftSize: n, bands: displayBands)
                didReadFormat = true
            }

            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else { continue }
            let frameCount = min(CMSampleBufferGetNumSamples(sample), length / (MemoryLayout<Float>.size * channelCount))
            guard frameCount > 0 else { continue }

            let floats = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                var mono: Float = 0
                let base = frame * channelCount
                for channel in 0..<channelCount {
                    mono += floats[base + channel]
                }
                pending.append(mono / Float(channelCount))
            }

            processAvailableWindows(
                pending: &pending,
                pendingStart: &pendingStart,
                nextWindowStart: &nextWindowStart,
                hop: hop,
                n: n,
                hann: hann,
                fftSetup: fftSetup,
                real: &real,
                imaginary: &imaginary,
                sampleRate: sampleRate,
                bandRanges: bandRanges,
                rawColumns: &rawColumns,
                lowPower: &lowPower,
                midPower: &midPower,
                highPower: &highPower
            )
        }

        // 末尾若还没有任何列，尝试从剩余样本生成一列。
        if rawColumns.isEmpty && pending.count >= n {
            let window = Array(pending.prefix(n))
            if let bands = processWindow(
                window,
                hann: hann,
                fftSetup: fftSetup,
                real: &real,
                imaginary: &imaginary,
                sampleRate: sampleRate,
                bandRanges: bandRanges,
                lowPower: &lowPower,
                midPower: &midPower,
                highPower: &highPower
            ) {
                rawColumns.append(bands)
            }
        }

        guard reader.status == .completed, !rawColumns.isEmpty else {
            throw AnalysisError.processingFailed
        }

        let columns = rawColumns.count
        let totalBands = displayBands
        var logs = [Double](repeating: -120, count: columns * totalBands)
        var maxLog = -Double.infinity
        for column in 0..<columns {
            let values = rawColumns[column]
            for band in 0..<min(totalBands, values.count) {
                let power = max(Double(values[band]), 1e-12)
                let db = 10 * log10(power)
                logs[band * columns + column] = db
                if db > maxLog { maxLog = db }
            }
        }
        if !maxLog.isFinite { maxLog = -60 }
        let floor = maxLog - 58
        var normalized = [Float](repeating: 0, count: logs.count)
        for index in logs.indices {
            let value = (logs[index] - floor) / 58
            normalized[index] = Float(max(0, min(1, value)))
        }

        let maxFrequency = min(8_000, sampleRate / 2)
        let total = lowPower + midPower + highPower
        let shares: BandShares
        if total > 0 {
            shares = BandShares(
                low: lowPower / total,
                mid: midPower / total,
                high: highPower / total
            )
        } else {
            shares = .empty
        }

        let cache = SpectrogramCache(
            version: 1,
            columns: columns,
            bands: totalBands,
            duration: estimatedDuration,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency,
            values: normalized
        )
        return Output(cache: cache, bandShares: shares, hopSize: hop)
    }

    private static func processAvailableWindows(
        pending: inout [Float],
        pendingStart: inout Int64,
        nextWindowStart: inout Int64,
        hop: Int,
        n: Int,
        hann: [Float],
        fftSetup: FFTSetup,
        real: inout [Float],
        imaginary: inout [Float],
        sampleRate: Double,
        bandRanges: [(Int, Int)],
        rawColumns: inout [[Float]],
        lowPower: inout Double,
        midPower: inout Double,
        highPower: inout Double
    ) {
        while Int64(pending.count) + pendingStart >= nextWindowStart + Int64(n) {
            let offset = Int(nextWindowStart - pendingStart)
            guard offset >= 0, offset + n <= pending.count else { break }
            let window = Array(pending[offset..<(offset + n)])
            if let bands = processWindow(
                window,
                hann: hann,
                fftSetup: fftSetup,
                real: &real,
                imaginary: &imaginary,
                sampleRate: sampleRate,
                bandRanges: bandRanges,
                lowPower: &lowPower,
                midPower: &midPower,
                highPower: &highPower
            ) {
                rawColumns.append(bands)
            }
            nextWindowStart += Int64(hop)
        }

        // 只保留下一窗口可能需要的样本，避免长录音占用大量内存。
        if nextWindowStart > pendingStart {
            let removeCount = min(pending.count, Int(nextWindowStart - pendingStart))
            if removeCount > 0 {
                pending.removeFirst(removeCount)
                pendingStart += Int64(removeCount)
            }
        }
    }

    private static func processWindow(
        _ window: [Float],
        hann: [Float],
        fftSetup: FFTSetup,
        real: inout [Float],
        imaginary: inout [Float],
        sampleRate: Double,
        bandRanges: [(Int, Int)],
        lowPower: inout Double,
        midPower: inout Double,
        highPower: inout Double
    ) -> [Float]? {
        let n = window.count
        guard n == hann.count else { return nil }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(window, 1, hann, 1, &windowed, 1, vDSP_Length(n))

        let half = n / 2
        var powers = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)

                windowed.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(n))), FFTDirection(FFT_FORWARD))

                for index in 0..<half {
                    let re = realBase[index]
                    let im = imagBase[index]
                    powers[index] = re * re + im * im
                }
            }
        }

        var bands = [Float](repeating: 0, count: displayBands)
        powers.withUnsafeBufferPointer { powerBuffer in
            guard let powerBase = powerBuffer.baseAddress else { return }
            for band in 0..<displayBands {
                let range = bandRanges[band]
                let lower = max(1, min(half - 1, range.0))
                let upper = max(lower + 1, min(half, range.1))
                var sum: Float = 0
                vDSP_sve(powerBase.advanced(by: lower), 1, &sum, vDSP_Length(upper - lower))
                bands[band] = max(0, sum / Float(upper - lower))
            }
        }

        // 统计低/中/高频能量占比。
        let binWidth = sampleRate / Double(n)
        for index in 1..<half {
            let frequency = Double(index) * binWidth
            let power = Double(powers[index])
            if frequency >= minFrequency && frequency < 250 {
                lowPower += power
            } else if frequency >= 250 && frequency < 2_000 {
                midPower += power
            } else if frequency >= 2_000 && frequency <= 8_000 {
                highPower += power
            }
        }

        return bands
    }

    private static func makeBandRanges(sampleRate: Double, fftSize: Int, bands: Int) -> [(Int, Int)] {
        let nyquist = sampleRate / 2
        let maxFrequency = min(8_000, nyquist)
        let half = fftSize / 2
        var result: [(Int, Int)] = []
        for band in 0..<bands {
            let lowerFraction = Double(band) / Double(bands)
            let upperFraction = Double(band + 1) / Double(bands)
            let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, lowerFraction)
            let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, upperFraction)
            let lowerBin = max(1, min(half - 1, Int(lowerFrequency / nyquist * Double(half))))
            let upperBin = max(lowerBin + 1, min(half, Int(upperFrequency / nyquist * Double(half))))
            result.append((lowerBin, upperBin))
        }
        return result
    }
}

// MARK: - 内存缓存包装

private final class WaveformBox: NSObject {
    let value: WaveformCache
    init(_ value: WaveformCache) { self.value = value }
}

private final class AnalysisBox: NSObject {
    let value: AudioAnalysisSummary
    init(_ value: AudioAnalysisSummary) { self.value = value }
}

private final class SpectrogramBox: NSObject {
    let value: SpectrogramCache
    init(_ value: SpectrogramCache) { self.value = value }
}

enum AnalysisError: LocalizedError {
    case noAudioTrack
    case unreadable
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "No audio track was found."
        case .unreadable: return "The recording file could not be read."
        case .processingFailed: return "Sound analysis could not be completed."
        }
    }
}
