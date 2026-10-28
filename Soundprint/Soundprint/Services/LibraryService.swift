//
//  LibraryService.swift
//  Soundprint
//
//  本地档案的唯一写入口。所有音频路径均为沙盒相对路径。
//

import AVFoundation
import CoreData
import Foundation

final class LibraryService {
    static let shared = LibraryService()

    private let stack = CoreDataStack.shared
    private let storage = StorageManager.shared
    private var context: NSManagedObjectContext { stack.viewContext }

    private init() {}

    // MARK: - 读取

    func fetchPlaces(
        includeArchived: Bool = false,
        kind: PlaceKind? = nil,
        search: String = ""
    ) -> [PlaceEntity] {
        let request = NSFetchRequest<PlaceEntity>(entityName: "Place")
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]

        var predicates: [NSPredicate] = []
        if !includeArchived {
            predicates.append(NSPredicate(format: "archivedAt == nil"))
        }
        if let kind {
            predicates.append(NSPredicate(format: "placeTypeRaw == %@", kind.rawValue))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let fetched = (try? context.fetch(request)) ?? []
        let places = fetched.sorted { lhs, rhs in
            let left = lhs.sortedRecordings.first?.createdAt ?? lhs.updatedAt
            let right = rhs.sortedRecordings.first?.createdAt ?? rhs.updatedAt
            return left > right
        }
        let query = normalized(search)
        guard !query.isEmpty else { return places }
        return places.filter { place in
            contains(place.name, query) ||
            contains(place.note ?? "", query) ||
            place.tags.contains(where: { contains($0, query) }) ||
            contains(place.kind.title, query)
        }
    }

    func fetchPlace(id: UUID) -> PlaceEntity? {
        let request = NSFetchRequest<PlaceEntity>(entityName: "Place")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    func fetchRecordings(
        placeID: UUID? = nil,
        includeDetached: Bool = false,
        search: String = "",
        limit: Int? = nil
    ) -> [RecordingEntity] {
        let request = NSFetchRequest<RecordingEntity>(entityName: "Recording")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        if let placeID {
            if includeDetached {
                request.predicate = NSPredicate(
                    format: "place.id == %@ OR place == nil",
                    placeID as CVarArg
                )
            } else {
                request.predicate = NSPredicate(format: "place.id == %@", placeID as CVarArg)
            }
        }

        let records = (try? context.fetch(request)) ?? []
        let query = normalized(search)
        let filtered: [RecordingEntity]
        if query.isEmpty {
            filtered = records
        } else {
            filtered = records.filter { record in
                contains(record.title, query) ||
                contains(record.note ?? "", query) ||
                contains(record.weather ?? "", query) ||
                contains(record.place?.name ?? "", query) ||
                record.tags.contains(where: { contains($0, query) }) ||
                record.sortedEvents.contains(where: { contains($0.title, query) || contains($0.kind.title, query) })
            }
        }
        if let limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func fetchRecording(id: UUID) -> RecordingEntity? {
        let request = NSFetchRequest<RecordingEntity>(entityName: "Recording")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    func fetchDetachedRecordings(search: String = "") -> [RecordingEntity] {
        let request = NSFetchRequest<RecordingEntity>(entityName: "Recording")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.predicate = NSPredicate(format: "place == nil")
        let records = (try? context.fetch(request)) ?? []
        let query = normalized(search)
        guard !query.isEmpty else { return records }
        return records.filter {
            contains($0.title, query) ||
            contains($0.note ?? "", query) ||
            $0.tags.contains(where: { contains($0, query) })
        }
    }

    func recordingsCount() -> Int {
        let request = NSFetchRequest<RecordingEntity>(entityName: "Recording")
        return (try? context.count(for: request)) ?? 0
    }

    func placesCount() -> Int {
        let request = NSFetchRequest<PlaceEntity>(entityName: "Place")
        request.predicate = NSPredicate(format: "archivedAt == nil")
        return (try? context.count(for: request)) ?? 0
    }

    func recentPlaces(limit: Int = 5) -> [PlaceEntity] {
        let places = fetchPlaces()
        return Array(places.sorted { lhs, rhs in
            let lhsDate = lhs.sortedRecordings.first?.createdAt ?? lhs.updatedAt
            let rhsDate = rhs.sortedRecordings.first?.createdAt ?? rhs.updatedAt
            return lhsDate > rhsDate
        }.prefix(limit))
    }

    func latestRecordingDate(for place: PlaceEntity) -> Date? {
        place.sortedRecordings.first?.createdAt
    }

    func allTags() -> [String] {
        let recordingTags = fetchRecordings().flatMap(\.tags)
        let placeTags = fetchPlaces(includeArchived: true).flatMap(\.tags)
        return Array(Set(recordingTags + placeTags)).sorted()
    }

    // MARK: - 地点

    @discardableResult
    func createPlace(_ draft: PlaceDraft) throws -> PlaceEntity {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.placeNameRequired }

        let place = PlaceEntity(context: context)
        place.id = UUID()
        place.name = trimmed
        place.kind = draft.kind
        place.note = cleaned(draft.note)
        place.tags = TagCodec.cleanedTags(draft.tags)
        applyLocation(
            coordinate: draft.coordinate,
            precision: draft.precision,
            to: place
        )
        place.createdAt = Date()
        place.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
        return place
    }

    @discardableResult
    func updatePlace(_ place: PlaceEntity, with draft: PlaceDraft) throws -> PlaceEntity {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.placeNameRequired }

        place.name = trimmed
        place.kind = draft.kind
        place.note = cleaned(draft.note)
        place.tags = TagCodec.cleanedTags(draft.tags)
        applyLocation(coordinate: draft.coordinate, precision: draft.precision, to: place)
        place.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
        return place
    }

    func setPlaceArchived(_ place: PlaceEntity, archived: Bool) throws {
        place.archivedAt = archived ? Date() : nil
        place.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
    }

    func deletePlace(_ place: PlaceEntity, strategy: PlaceDeletionStrategy) throws {
        let recordings = Array(place.recordings)
        let fileSnapshots: [(audio: String, waveform: String?, analysis: String?, spectrogram: String?, suggestions: String)] = recordings.map {
            (
                audio: $0.relativeAudioPath,
                waveform: $0.waveformRelativePath,
                analysis: $0.analysis?.analysisRelativePath,
                spectrogram: $0.analysis?.spectrogramRelativePath,
                suggestions: storage.relativePathSuggestions(for: $0.id)
            )
        }

        switch strategy {
        case .deleteRecordings:
            // 先提交数据库删除，成功后再清理文件，避免保存失败却丢失音频。
            for record in recordings {
                context.delete(record)
            }
        case .detachRecordings:
            for record in recordings {
                record.place = nil
                record.updatedAt = Date()
            }
        }
        context.delete(place)
        try saveContext()

        if strategy == .deleteRecordings {
            for snapshot in fileSnapshots {
                if let url = storage.absoluteURL(forRelativePath: snapshot.audio) {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        storage.queuePendingDeletion(snapshot.audio)
                    }
                }
                storage.deleteRelativeFile(snapshot.waveform)
                storage.deleteRelativeFile(snapshot.analysis)
                storage.deleteRelativeFile(snapshot.spectrogram)
                storage.deleteRelativeFile(snapshot.suggestions)
            }
        }
        notifyLibraryChanged()
    }

    func assignRecordings(_ recordings: [RecordingEntity], to place: PlaceEntity?) throws {
        for record in recordings {
            record.place = place
            record.updatedAt = Date()
        }
        place?.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
    }

    // MARK: - 录音

    @discardableResult
    func saveRecording(_ draft: RecordingSaveDraft) throws -> RecordingEntity {
        let id = UUID()
        let audioAttributes = (try? FileManager.default.attributesOfItem(atPath: draft.temporaryAudioURL.path)) ?? [:]
        let fileSize = (audioAttributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else { throw StorageError.recordingUnreadable }

        let placement = fetchPlace(id: draft.placeID ?? UUID())
        let record = RecordingEntity(context: context)
        record.id = id
        record.title = cleaned(draft.title) ?? defaultTitle(for: placement, date: draft.createdAt)
        record.duration = max(0, draft.duration)
        record.createdAt = draft.createdAt
        record.updatedAt = Date()
        record.fileSize = fileSize
        record.audioFormat = "m4a"
        record.sampleRate = draft.sampleRate
        record.channelCount = Int16(max(0, draft.channelCount))
        record.deviceModel = draft.deviceModel
        record.note = cleaned(draft.note)
        record.weather = cleaned(draft.weather)
        record.tags = TagCodec.cleanedTags(draft.tags)
        record.place = placement
        applyLocation(coordinate: draft.coordinate, precision: draft.precision, to: record)

        let autoAnalysis = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
        record.analysisStatusRaw = autoAnalysis ? AnalysisState.pending.rawValue : AnalysisState.disabled.rawValue

        // 先落盘音频，再提交数据库，避免出现只能播放一半的坏状态。
        let relativePath = try storage.moveRecording(from: draft.temporaryAudioURL, to: id)
        record.relativeAudioPath = relativePath

        for marker in draft.markers {
            let event = SoundEventEntity(context: context)
            event.id = marker.id
            event.startTime = max(0, min(marker.time, max(0, draft.duration)))
            event.endTime = 0
            event.hasEndTime = false
            event.kind = marker.kind
            event.title = marker.title.isEmpty ? marker.kind.title : marker.title
            event.note = nil
            event.sourceRaw = "manual"
            event.confidence = 0
            event.hasConfidence = false
            event.createdAt = Date()
            event.updatedAt = Date()
            event.recording = record
        }

        do {
            try saveContext()
        } catch {
            NSLog("Soundprint Core Data save failed: %@", String(describing: error))
            storage.deleteRelativeFile(relativePath)
            throw error
        }

        notifyLibraryChanged()
        AudioAnalysisService.shared.schedule(recordingID: id, force: false)
        return record
    }

    func updateRecording(_ record: RecordingEntity, with draft: RecordingEditDraft) throws {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.title = trimmed.isEmpty ? defaultTitle(for: record.place, date: record.createdAt) : trimmed
        record.tags = TagCodec.cleanedTags(draft.tags)
        record.note = cleaned(draft.note)
        record.weather = cleaned(draft.weather)
        if let createdAt = draft.createdAt {
            record.createdAt = createdAt
        }
        record.place = fetchPlace(id: draft.placeID ?? UUID())
        applyLocation(coordinate: draft.coordinate, precision: draft.precision, to: record)

        if let markers = draft.markers {
            replaceEvents(on: record, with: markers)
        }

        record.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
    }

    func deleteRecording(_ record: RecordingEntity) throws {
        let audioPath = record.relativeAudioPath
        let waveformPath = record.waveformRelativePath
        let analysisPath = record.analysis?.analysisRelativePath
        let spectrogramPath = record.analysis?.spectrogramRelativePath
        let suggestionPath = storage.relativePathSuggestions(for: record.id)

        context.delete(record)
        try saveContext()

        if let url = storage.absoluteURL(forRelativePath: audioPath) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                storage.queuePendingDeletion(audioPath)
            }
        }
        storage.deleteRelativeFile(waveformPath)
        storage.deleteRelativeFile(analysisPath)
        storage.deleteRelativeFile(spectrogramPath)
        storage.deleteRelativeFile(suggestionPath)
        notifyLibraryChanged()
    }

    func replaceEvents(on record: RecordingEntity, with markers: [RecordingMarker]) {
        for event in record.events {
            context.delete(event)
        }
        for marker in markers {
            let event = SoundEventEntity(context: context)
            event.id = marker.id
            event.startTime = max(0, min(marker.time, max(0.01, record.duration)))
            event.endTime = 0
            event.hasEndTime = false
            event.kind = marker.kind
            event.title = marker.title.isEmpty ? marker.kind.title : marker.title
            event.note = nil
            event.sourceRaw = "manual"
            event.confidence = 0
            event.hasConfidence = false
            event.createdAt = Date()
            event.updatedAt = Date()
            event.recording = record
        }
    }

    @discardableResult
    func addEvent(
        to record: RecordingEntity,
        kind: EventKind,
        title: String,
        startTime: Double,
        endTime: Double?,
        note: String?
    ) throws -> SoundEventEntity {
        let event = SoundEventEntity(context: context)
        event.id = UUID()
        event.startTime = max(0, min(startTime, max(0, record.duration)))
        event.endTimeValue = endTime.map { max(startTime, min($0, max(0, record.duration))) }
        event.kind = kind
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title
        event.note = cleaned(note)
        event.sourceRaw = "manual"
        event.confidence = 0
        event.hasConfidence = false
        event.createdAt = Date()
        event.updatedAt = Date()
        event.recording = record
        try saveContext()
        notifyLibraryChanged()
        return event
    }

    func updateEvent(
        _ event: SoundEventEntity,
        kind: EventKind,
        title: String,
        startTime: Double,
        endTime: Double?,
        note: String?
    ) throws {
        guard let record = event.recording else { return }
        event.startTime = max(0, min(startTime, max(0, record.duration)))
        event.endTimeValue = endTime.map { max(startTime, min($0, max(0, record.duration))) }
        event.kind = kind
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : title
        event.note = cleaned(note)
        event.updatedAt = Date()
        try saveContext()
        notifyLibraryChanged()
    }

    func deleteEvent(_ event: SoundEventEntity) throws {
        context.delete(event)
        try saveContext()
        notifyLibraryChanged()
    }

    // MARK: - 分析状态

    func setAnalysisState(_ state: AnalysisState, for recordingID: UUID) {
        guard let record = fetchRecording(id: recordingID) else { return }
        record.analysisState = state
        record.updatedAt = Date()
        try? stack.saveViewContext()
        notifyAnalysisChanged()
    }

    func updateWaveformPath(for recordingID: UUID, path: String) {
        guard let record = fetchRecording(id: recordingID) else { return }
        record.waveformRelativePath = path
        record.updatedAt = Date()
        try? stack.saveViewContext()
        notifyAnalysisChanged()
    }

    func updateAnalysisMetadata(
        for recordingID: UUID,
        waveformPath: String?,
        analysisResult: AudioAnalysisSummary?,
        analysisPath: String?,
        spectrogramPath: String?
    ) {
        guard let record = fetchRecording(id: recordingID) else { return }
        if let waveformPath {
            record.waveformRelativePath = waveformPath
        }
        record.analysisState = analysisResult == nil
            ? ((UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true) ? .pending : .disabled)
            : .ready

        if let summary = analysisResult {
            let analysis = record.analysis ?? AudioAnalysisEntity(context: context)
            if record.analysis == nil {
                analysis.id = UUID()
                analysis.recording = record
            }
            analysis.algorithmVersion = summary.algorithmVersion
            analysis.windowSize = Int32(summary.windowSize)
            analysis.hopSize = Int32(summary.hopSize)
            analysis.peakValue = summary.peak
            analysis.rmsMean = summary.rmsMean
            analysis.rmsDBFS = summary.rmsDBFS
            analysis.bandLow = summary.bands.low
            analysis.bandMid = summary.bands.mid
            analysis.bandHigh = summary.bands.high
            analysis.analysisRelativePath = analysisPath ?? ""
            analysis.spectrogramRelativePath = spectrogramPath
            analysis.createdAt = Date()
        }

        record.updatedAt = Date()
        try? stack.saveViewContext()
        notifyAnalysisChanged()
    }

    func resetStuckAnalysis() {
        let request = NSFetchRequest<RecordingEntity>(entityName: "Recording")
        request.predicate = NSPredicate(format: "analysisStatusRaw == %@", AnalysisState.processing.rawValue)
        guard let records = try? context.fetch(request), !records.isEmpty else { return }
        for record in records {
            record.analysisState = .pending
        }
        try? stack.saveViewContext()
        notifyAnalysisChanged()
    }

    // MARK: - 缓存与整理

    func clearCachesAndScheduleRegeneration() throws {
        let records = fetchRecordings()
        try storage.clearAnalysisCaches()
        for record in records {
            record.waveformRelativePath = nil
            if let analysis = record.analysis {
                context.delete(analysis)
            }
            let auto = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
            record.analysisState = auto ? .pending : .disabled
        }
        try saveContext()
        notifyAnalysisChanged()
        notifyStorageChanged()
        for record in records {
            AudioAnalysisService.shared.schedule(recordingID: record.id, force: true)
        }
    }

    func integrityReport(completion: @escaping (StorageIntegrityReport) -> Void) {
        // 仅在主线程读取 Core Data，后台只处理不可变快照和文件系统。
        let snapshots = fetchRecordings().map {
            (id: $0.id, title: $0.title, path: $0.relativeAudioPath)
        }
        let knownPaths = Set(snapshots.map(\.path))
        let knownIDs = Set(snapshots.map { $0.id.uuidString.uppercased() })

        DispatchQueue.global(qos: .utility).async {
            var report = StorageIntegrityReport()
            for record in snapshots {
                guard let url = self.storage.absoluteURL(forRelativePath: record.path) else {
                    report.missingAudio.append((record.id, record.title, record.path))
                    continue
                }
                if !FileManager.default.fileExists(atPath: url.path) {
                    report.missingAudio.append((record.id, record.title, record.path))
                }
            }

            let audioFiles = (try? FileManager.default.contentsOfDirectory(
                at: self.storage.audioDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in audioFiles where url.pathExtension.lowercased() == "m4a" {
                let relative = "Audio/\(url.lastPathComponent)"
                if !knownPaths.contains(relative) {
                    report.orphanAudio.append(url)
                }
            }

            for directory in [self.storage.waveformDirectory, self.storage.analysisDirectory] {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )) ?? []
                for url in files {
                    let base = url.deletingPathExtension().lastPathComponent
                    let id = (base.components(separatedBy: ".").first ?? base).uppercased()
                    if !knownIDs.contains(id) {
                        report.orphanCache.append(url)
                    }
                }
            }
            report.pendingDeletions = self.storage.pendingDeletions

            DispatchQueue.main.async {
                completion(report)
            }
        }
    }

    func cleanOrphans(completion: @escaping (Int, Int) -> Void) {
        let paths = Set(fetchRecordings().map(\.relativeAudioPath))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let result = (try? self.storage.removeOrphanFiles(knownAudioPaths: paths)) ?? (audio: 0, cache: 0)
            self.storage.retryPendingDeletions()
            DispatchQueue.main.async(execute: DispatchWorkItem {
                completion(result.audio, result.cache)
                self.notifyStorageChanged()
            })
        }
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    func deleteAllData() throws {
        let recordings = fetchRecordings()
        let places = fetchPlaces(includeArchived: true)

        for record in recordings {
            context.delete(record)
        }
        for place in places {
            context.delete(place)
        }
        try saveContext()

        try storage.deleteAllAudioAndCache()
        CompareSelectionStore.shared.clear()
        notifyLibraryChanged()
        notifyAnalysisChanged()
        notifyStorageChanged()
    }

    // MARK: - 内部工具

    /// 保存失败时回滚上下文，避免一个无效对象让后续所有保存持续失败。
    private func saveContext() throws {
        do {
            try stack.saveViewContext()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func applyLocation(
        coordinate: Coordinate?,
        precision: LocationPrecision,
        to place: PlaceEntity
    ) {
        guard precision != .none, let coordinate else {
            place.hasCoordinates = false
            place.latitude = 0
            place.longitude = 0
            place.locationPrecisionRaw = LocationPrecision.none.rawValue
            return
        }
        let final = precision == .approximate ? coordinate.roundedForApproximate() : coordinate
        place.hasCoordinates = true
        place.latitude = final.latitude
        place.longitude = final.longitude
        place.locationPrecisionRaw = precision.rawValue
    }

    private func applyLocation(
        coordinate: Coordinate?,
        precision: LocationPrecision,
        to record: RecordingEntity
    ) {
        guard precision != .none, let coordinate else {
            record.hasCoordinates = false
            record.latitude = 0
            record.longitude = 0
            return
        }
        let final = precision == .approximate ? coordinate.roundedForApproximate() : coordinate
        record.hasCoordinates = true
        record.latitude = final.latitude
        record.longitude = final.longitude
    }

    private func defaultTitle(for place: PlaceEntity?, date: Date) -> String {
        let datePart = SPFormat.mediumDate.string(from: date)
        let timePart = SPFormat.time.string(from: date)
        if let place, !place.name.isEmpty {
            return "\(place.name) · \(datePart) \(timePart)"
        }
        return "Recording \(datePart) \(timePart)"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: SPFormat.displayLocale)
    }

    private func contains(_ source: String, _ query: String) -> Bool {
        normalized(source).contains(query)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func notifyLibraryChanged() {
        NotificationCenter.default.post(name: SPNotification.libraryDidChange, object: nil)
        notifyStorageChanged()
    }

    private func notifyAnalysisChanged() {
        NotificationCenter.default.post(name: SPNotification.analysisDidChange, object: nil)
    }

    private func notifyStorageChanged() {
        NotificationCenter.default.post(name: SPNotification.storageDidChange, object: nil)
    }
}

enum LibraryError: LocalizedError {
    case placeNameRequired
    case recordingNotFound

    var errorDescription: String? {
        switch self {
        case .placeNameRequired: return "Enter a name for the place."
        case .recordingNotFound: return "The recording was not found."
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 对比选择

final class CompareSelectionStore {
    static let shared = CompareSelectionStore()

    private let keyA = "sp.compare.a"
    private let keyB = "sp.compare.b"

    var recordingAID: UUID? {
        get { uuid(forKey: keyA) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: keyA) }
    }

    var recordingBID: UUID? {
        get { uuid(forKey: keyB) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: keyB) }
    }

    func swap() {
        let a = recordingAID
        recordingAID = recordingBID
        recordingBID = a
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: keyA)
        UserDefaults.standard.removeObject(forKey: keyB)
    }

    private func uuid(forKey key: String) -> UUID? {
        guard let value = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: value)
    }
}
