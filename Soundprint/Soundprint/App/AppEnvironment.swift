
import Foundation

final class AppEnvironment {
    static let shared = AppEnvironment()

    let library = LibraryService.shared
    let storage = StorageManager.shared
    let analysis = AudioAnalysisService.shared
    let location = LocationService.shared

    private var didPrepare = false

    private init() {}

    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        if UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) == nil {
            UserDefaults.standard.set(true, forKey: SPDefaultsKey.autoAnalysis)
        }

        storage.prepareDirectories()
        storage.retryPendingDeletions()
        storage.cleanTemporaryFiles()
        library.resetStuckAnalysis()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.schedulePendingWork()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if #available(iOS 16.2, *) {
                RecordingLiveActivityManager.endStaleActivitiesIfNeeded()
            }
        }
    }

    private func schedulePendingWork() {
        let auto = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
        let records = library.fetchRecordings()

        for record in records {
            let hasWaveform: Bool = {
                guard let path = record.waveformRelativePath,
                      let url = storage.absoluteURL(forRelativePath: path) else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }()

            if auto {
                if record.analysisState == .pending || (!hasWaveform && record.analysisState != .ready) {
                    analysis.schedule(recordingID: record.id, force: false)
                }
            } else if !hasWaveform && record.analysisState != .ready {
                analysis.schedule(recordingID: record.id, force: false)
            }
        }
    }

    /// 保存新录音后，从列表中选择性地展示详情。
    func scheduleAnalysisIfNeeded(for recordID: UUID) {
        analysis.schedule(recordingID: recordID, force: false)
    }
}
