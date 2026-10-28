//
//  BackupService.swift
//  Soundprint
//
//  完整档案 ZIP 的导出与导入。导出默认不含坐标；导入前校验格式、CRC、
//  路径与重复 UUID，并允许“跳过重复”或“作为副本导入”。
//

import CoreData
import Foundation

// MARK: - DTO

struct BackupCounts: Codable {
    var places: Int
    var recordings: Int
    var events: Int
}

struct BackupManifest: Codable {
    var format: String
    var formatVersion: Int
    var appVersion: String
    var appBuild: String
    var exportedAt: Date
    var includesExactLocation: Bool
    var counts: BackupCounts
    var files: [String]
    var skippedMissingAudio: Int
    var note: String
}

struct BackupPlace: Codable {
    var id: UUID
    var name: String
    var placeType: String
    var note: String?
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
    var locationPrecision: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}

struct BackupRecording: Codable {
    var id: UUID
    var placeID: UUID?
    var title: String
    var duration: Double
    var createdAt: Date
    var updatedAt: Date
    var format: String
    var sampleRate: Double
    var channelCount: Int
    var deviceModel: String?
    var note: String?
    var weather: String?
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
}

struct BackupEvent: Codable {
    var id: UUID
    var recordingID: UUID
    var startTime: Double
    var endTime: Double?
    var category: String
    var title: String
    var note: String?
    var source: String
    var confidence: Double?
    var createdAt: Date
    var updatedAt: Date
}

enum BackupDuplicateStrategy {
    case skip
    case copy
}

struct BackupPreview {
    let manifest: BackupManifest
    let places: [BackupPlace]
    let recordings: [BackupRecording]
    let events: [BackupEvent]
    let duplicatePlaces: Int
    let duplicateRecordings: Int
    let missingAudioCount: Int
    let extractionDirectory: URL
}

struct BackupImportResult {
    var importedPlaces: Int
    var importedRecordings: Int
    var importedEvents: Int
    var skipped: Int
    var errors: Int
}

// MARK: - 导出前快照

private struct ExportSnapshot {
    var places: [BackupPlace]
    var recordings: [BackupRecording]
    var events: [BackupEvent]
    var audioFiles: [(archivePath: String, sourceURL: URL)]
    var skippedMissingAudio: Int
    var includesLocation: Bool
}

final class BackupService {
    static let shared = BackupService()

    static let formatName = "soundprint.archive"
    static let formatVersion = 1

    private let library = LibraryService.shared
    private let storage = StorageManager.shared
    private let analysis = AudioAnalysisService.shared

    private init() {}

    // MARK: - 导出

    func exportBackup(
        includeExactLocation: Bool,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let snapshot = makeSnapshot(includeExactLocation: includeExactLocation)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try self.writeBackup(snapshot: snapshot)
                DispatchQueue.main.async {
                    completion(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func makeSnapshot(includeExactLocation: Bool) -> ExportSnapshot {
        let places = library.fetchPlaces(includeArchived: true)
        let allRecordings = library.fetchRecordings()
        var recordings: [BackupRecording] = []
        var events: [BackupEvent] = []
        var audioFiles: [(String, URL)] = []
        var skipped = 0

        for record in allRecordings {
            guard let audioURL = storage.audioURL(for: record),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                skipped += 1
                continue
            }
            let coordinate = includeExactLocation ? record.coordinate : nil
            recordings.append(BackupRecording(
                id: record.id,
                placeID: record.place?.id,
                title: record.title,
                duration: record.duration,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                format: record.audioFormat,
                sampleRate: record.sampleRate,
                channelCount: Int(record.channelCount),
                deviceModel: record.deviceModel,
                note: record.note,
                weather: record.weather,
                tags: record.tags,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            ))
            audioFiles.append(("audio/\(record.id.uuidString).m4a", audioURL))
        }

        let includedIDs = Set(recordings.map(\.id))
        for record in allRecordings where includedIDs.contains(record.id) {
            for event in record.sortedEvents {
                events.append(BackupEvent(
                    id: event.id,
                    recordingID: record.id,
                    startTime: event.startTime,
                    endTime: event.endTimeValue,
                    category: event.categoryRaw,
                    title: event.title,
                    note: event.note,
                    source: event.sourceRaw,
                    confidence: event.hasConfidence ? event.confidence : nil,
                    createdAt: event.createdAt,
                    updatedAt: event.updatedAt
                ))
            }
        }

        let placeDTOs = places.map { place -> BackupPlace in
            let coordinate = includeExactLocation ? place.coordinate : nil
            return BackupPlace(
                id: place.id,
                name: place.name,
                placeType: place.placeTypeRaw,
                note: place.note,
                tags: place.tags,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude,
                locationPrecision: coordinate == nil ? LocationPrecision.none.rawValue : place.locationPrecisionRaw,
                createdAt: place.createdAt,
                updatedAt: place.updatedAt,
                archivedAt: place.archivedAt
            )
        }

        return ExportSnapshot(
            places: placeDTOs,
            recordings: recordings,
            events: events,
            audioFiles: audioFiles,
            skippedMissingAudio: skipped,
            includesLocation: includeExactLocation
        )
    }

    private func writeBackup(snapshot: ExportSnapshot) throws -> URL {
        let directory = try storage.makeExportDirectory(name: "Soundprint-Backup")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let placesData = try encoder.encode(snapshot.places)
        let recordingsData = try encoder.encode(snapshot.recordings)
        let eventsData = try encoder.encode(snapshot.events)
        let csvData = makeCSV(snapshot: snapshot).data(using: .utf8) ?? Data()

        var files = ["places.json", "recordings.json", "events.json", "recordings.csv"]
        files.append(contentsOf: snapshot.audioFiles.map(\.archivePath))
        files.sort()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let manifest = BackupManifest(
            format: Self.formatName,
            formatVersion: Self.formatVersion,
            appVersion: version,
            appBuild: build,
            exportedAt: Date(),
            includesExactLocation: snapshot.includesLocation,
            counts: BackupCounts(
                places: snapshot.places.count,
                recordings: snapshot.recordings.count,
                events: snapshot.events.count
            ),
            files: files,
            skippedMissingAudio: snapshot.skippedMissingAudio,
            note: "A local Soundprint backup. Contains audio and record information. Analysis cache is not included."
        )
        let manifestData = try encoder.encode(manifest)

        var entries: [ZipArchiveWriter.Entry] = [
            .data(path: "manifest.json", data: manifestData),
            .data(path: "places.json", data: placesData),
            .data(path: "recordings.json", data: recordingsData),
            .data(path: "events.json", data: eventsData),
            .data(path: "recordings.csv", data: csvData)
        ]
        for audio in snapshot.audioFiles {
            entries.append(.file(path: audio.archivePath, url: audio.sourceURL))
        }

        let nameFormatter = DateFormatter()
        nameFormatter.locale = Locale(identifier: "en_US_POSIX")
        nameFormatter.dateFormat = "yyyy-MM-dd"
        let nameDate = nameFormatter.string(from: Date())
        let time = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let zipURL = directory.appendingPathComponent(
            String(format: "Soundprint-Backup-%@-%02d%02d.zip", nameDate, time, minute)
        )
        try ZipArchiveWriter.write(entries: entries, to: zipURL)
        return zipURL
    }

    private func makeCSV(snapshot: ExportSnapshot) -> String {
        var lines = ["id,title,place_id,place_name,duration_seconds,created_at,tags,weather,latitude,longitude"]
        let placesByID = Dictionary(uniqueKeysWithValues: snapshot.places.map { ($0.id, $0) })
        for record in snapshot.recordings {
            let placeName = record.placeID.flatMap { placesByID[$0]?.name } ?? ""
            let fields = [
                record.id.uuidString,
                record.title,
                record.placeID?.uuidString ?? "",
                placeName,
                String(format: "%.3f", record.duration),
                ISO8601DateFormatter().string(from: record.createdAt),
                record.tags.joined(separator: "|"),
                record.weather ?? "",
                record.latitude.map { String(format: "%.6f", $0) } ?? "",
                record.longitude.map { String(format: "%.6f", $0) } ?? ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - 导入准备

    func prepareImport(from zipURL: URL, completion: @escaping (Result<BackupPreview, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let accessed = zipURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { zipURL.stopAccessingSecurityScopedResource() }
            }
            let extraction = self.storage.tempDirectory
                .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
            do {
                try ZipArchiveReader.extract(zipURL: zipURL, to: extraction)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try self.decode(BackupManifest.self, file: "manifest.json", root: extraction, decoder: decoder)
                guard manifest.format == Self.formatName else {
                    throw BackupError.invalidFormat
                }
                guard manifest.formatVersion <= Self.formatVersion else {
                    throw BackupError.unsupportedVersion
                }
                let places = try self.decode([BackupPlace].self, file: "places.json", root: extraction, decoder: decoder)
                let recordings = try self.decode([BackupRecording].self, file: "recordings.json", root: extraction, decoder: decoder)
                let events = try self.decode([BackupEvent].self, file: "events.json", root: extraction, decoder: decoder)
                guard places.count <= 10_000, recordings.count <= 10_000, events.count <= 50_000 else {
                    throw BackupError.tooManyItems
                }
                let missingAudio = recordings.reduce(into: 0) { count, record in
                    let url = extraction
                        .appendingPathComponent("audio", isDirectory: true)
                        .appendingPathComponent("\(record.id.uuidString).m4a")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        count += 1
                    }
                }

                DispatchQueue.main.async {
                    let existingPlaceIDs = Set(self.library.fetchPlaces(includeArchived: true).map(\.id))
                    let existingRecordingIDs = Set(self.library.fetchRecordings().map(\.id))
                    let duplicatePlaces = places.filter { existingPlaceIDs.contains($0.id) }.count
                    let duplicateRecordings = recordings.filter { existingRecordingIDs.contains($0.id) }.count
                    let preview = BackupPreview(
                        manifest: manifest,
                        places: places,
                        recordings: recordings,
                        events: events,
                        duplicatePlaces: duplicatePlaces,
                        duplicateRecordings: duplicateRecordings,
                        missingAudioCount: missingAudio,
                        extractionDirectory: extraction
                    )
                    completion(.success(preview))
                }
            } catch {
                try? FileManager.default.removeItem(at: extraction)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func discard(preview: BackupPreview) {
        try? FileManager.default.removeItem(at: preview.extractionDirectory)
    }

    // MARK: - 导入

    func importBackup(
        preview: BackupPreview,
        strategy: BackupDuplicateStrategy,
        completion: @escaping (Result<BackupImportResult, Error>) -> Void
    ) {
        let existingPlaceIDs = Set(library.fetchPlaces(includeArchived: true).map(\.id))
        let existingRecordingIDs = Set(library.fetchRecordings().map(\.id))

        // 先决定 ID 映射与音频复制目标。
        var placeTarget: [UUID: UUID] = [:]
        for place in preview.places {
            if existingPlaceIDs.contains(place.id) {
                if strategy == .skip {
                    placeTarget[place.id] = place.id
                } else {
                    let newID = UUID()
                    placeTarget[place.id] = newID
                }
            } else {
                placeTarget[place.id] = place.id
            }
        }

        var recordingTarget: [UUID: UUID] = [:]
        var recordingsToImport: [BackupRecording] = []
        let extraction = preview.extractionDirectory
        for record in preview.recordings {
            let source = extraction
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("\(record.id.uuidString).m4a")
            guard FileManager.default.fileExists(atPath: source.path) else {
                continue
            }
            if existingRecordingIDs.contains(record.id) {
                if strategy == .skip {
                    continue
                }
                let newID = UUID()
                recordingTarget[record.id] = newID
                recordingsToImport.append(record)
            } else {
                recordingTarget[record.id] = record.id
                recordingsToImport.append(record)
            }
        }

        // 复制音频在后台完成，Core Data 写入回到主线程。
        DispatchQueue.global(qos: .userInitiated).async {
            var copied: [(targetID: UUID, relativePath: String)] = []
            for record in recordingsToImport {
                guard let targetID = recordingTarget[record.id] else { continue }
                let source = extraction
                    .appendingPathComponent("audio", isDirectory: true)
                    .appendingPathComponent("\(record.id.uuidString).m4a")
                do {
                    let relative = try self.storage.importAudio(from: source, for: targetID)
                    copied.append((targetID, relative))
                } catch {
                    if let index = recordingTarget.index(forKey: record.id) {
                        recordingTarget.remove(at: index)
                    }
                }
            }

            DispatchQueue.main.async {
                do {
                    let result = try self.insertImportedData(
                        preview: preview,
                        placeTarget: placeTarget,
                        recordingTarget: recordingTarget,
                        recordingsToImport: recordingsToImport.filter { recordingTarget[$0.id] != nil },
                        copied: copied
                    )
                    try? FileManager.default.removeItem(at: extraction)
                    completion(.success(result))
                } catch {
                    CoreDataStack.shared.viewContext.rollback()
                    for item in copied {
                        self.storage.deleteRelativeFile(item.relativePath)
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    private func insertImportedData(
        preview: BackupPreview,
        placeTarget: [UUID: UUID],
        recordingTarget: [UUID: UUID],
        recordingsToImport: [BackupRecording],
        copied: [(targetID: UUID, relativePath: String)]
    ) throws -> BackupImportResult {
        let context = CoreDataStack.shared.viewContext
        var existingPlaces: [UUID: PlaceEntity] = [:]
        for place in library.fetchPlaces(includeArchived: true) {
            existingPlaces[place.id] = place
        }

        var placeEntities: [UUID: PlaceEntity] = [:]
        var importedPlaces = 0
        for dto in preview.places {
            guard let targetID = placeTarget[dto.id] else { continue }
            if let existing = existingPlaces[targetID] {
                placeEntities[dto.id] = existing
                continue
            }
            let entity = PlaceEntity(context: context)
            entity.id = targetID
            entity.name = dto.name
            entity.placeTypeRaw = dto.placeType
            entity.note = dto.note
            entity.tags = dto.tags
            entity.hasCoordinates = dto.latitude != nil && dto.longitude != nil
            entity.latitude = dto.latitude ?? 0
            entity.longitude = dto.longitude ?? 0
            entity.locationPrecisionRaw = entity.hasCoordinates ? dto.locationPrecision : LocationPrecision.none.rawValue
            entity.createdAt = dto.createdAt
            entity.updatedAt = dto.updatedAt
            entity.archivedAt = dto.archivedAt
            placeEntities[dto.id] = entity
            importedPlaces += 1
        }

        let relativeByTarget = Dictionary(uniqueKeysWithValues: copied.map { ($0.targetID, $0.relativePath) })
        var recordEntities: [UUID: RecordingEntity] = [:]
        var importedRecordings = 0
        for dto in recordingsToImport {
            guard let targetID = recordingTarget[dto.id],
                  let relativePath = relativeByTarget[targetID],
                  library.fetchRecording(id: targetID) == nil else { continue }
            let entity = RecordingEntity(context: context)
            entity.id = targetID
            entity.title = dto.title
            entity.duration = max(0, dto.duration)
            entity.createdAt = dto.createdAt
            entity.updatedAt = dto.updatedAt
            entity.relativeAudioPath = relativePath
            entity.audioFormat = dto.format.isEmpty ? "m4a" : dto.format
            entity.sampleRate = dto.sampleRate
            entity.channelCount = Int16(max(0, min(Int(Int16.max), dto.channelCount)))
            entity.deviceModel = dto.deviceModel
            entity.note = dto.note
            entity.weather = dto.weather
            entity.tags = dto.tags
            entity.hasCoordinates = dto.latitude != nil && dto.longitude != nil
            entity.latitude = dto.latitude ?? 0
            entity.longitude = dto.longitude ?? 0
            if let placeID = dto.placeID, let place = placeEntities[placeID] {
                entity.place = place
            }
            if let fileURL = storage.absoluteURL(forRelativePath: relativePath) {
                entity.fileSize = storage.fileSize(at: fileURL)
            }
            let auto = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
            entity.analysisStatusRaw = auto ? AnalysisState.pending.rawValue : AnalysisState.disabled.rawValue
            recordEntities[dto.id] = entity
            importedRecordings += 1
        }

        var importedEvents = 0
        for dto in preview.events {
            guard let record = recordEntities[dto.recordingID] else { continue }
            let event = SoundEventEntity(context: context)
            event.id = UUID()
            event.startTime = max(0, min(dto.startTime, max(0, record.duration)))
            if let end = dto.endTime, end >= dto.startTime {
                event.endTimeValue = min(end, max(0, record.duration))
            } else {
                event.endTimeValue = nil
            }
            event.kind = EventKind(rawValue: dto.category) ?? .other
            event.title = dto.title
            event.note = dto.note
            event.sourceRaw = dto.source == "suggested" ? "suggested" : "manual"
            if let confidence = dto.confidence {
                event.confidence = confidence
                event.hasConfidence = true
            } else {
                event.confidence = 0
                event.hasConfidence = false
            }
            event.createdAt = dto.createdAt
            event.updatedAt = dto.updatedAt
            event.recording = record
            importedEvents += 1
        }

        do {
            try CoreDataStack.shared.saveViewContext()
        } catch {
            for item in copied {
                storage.deleteRelativeFile(item.relativePath)
            }
            throw error
        }

        NotificationCenter.default.post(name: SPNotification.libraryDidChange, object: nil)
        NotificationCenter.default.post(name: SPNotification.analysisDidChange, object: nil)
        NotificationCenter.default.post(name: SPNotification.storageDidChange, object: nil)
        for record in recordEntities.values {
            analysis.schedule(recordingID: record.id, force: false)
        }

        return BackupImportResult(
            importedPlaces: importedPlaces,
            importedRecordings: importedRecordings,
            importedEvents: importedEvents,
            skipped: max(0, preview.recordings.count - importedRecordings),
            errors: 0
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, file: String, root: URL, decoder: JSONDecoder) throws -> T {
        let url = root.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BackupError.missingFile(file)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }
}

enum BackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case missingFile(String)
    case tooManyItems

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "This is not a Soundprint backup, or its format could not be read."
        case .unsupportedVersion:
            return "This backup uses a newer format than the current app. Update the app."
        case .missingFile(let name):
            return "\(name) was not found in the backup."
        case .tooManyItems:
            return "The backup contains more items than the limit allows."
        }
    }
}
