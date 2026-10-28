//
//  RecordingExportService.swift
//  Soundprint
//
//  单段录音导出。文件名使用可读标题与日期，不暴露内部 UUID。
//

import Foundation

struct RecordingExportOptions {
    var includeMetadata: Bool
    var includeExactLocation: Bool
}

struct RecordingExportPackage {
    let items: [Any]
    let temporaryDirectory: URL
}

final class RecordingExportService {
    static let shared = RecordingExportService()

    private let storage = StorageManager.shared
    private let library = LibraryService.shared
    private let analysisService = AudioAnalysisService.shared

    private init() {}

    func createExport(for record: RecordingEntity, options: RecordingExportOptions) throws -> RecordingExportPackage {
        let directory = try storage.makeExportDirectory(name: record.title)
        var items: [Any] = []
        let baseName = friendlyBaseName(for: record)

        if let audioURL = storage.audioURL(for: record),
           FileManager.default.fileExists(atPath: audioURL.path) {
            let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
            let destination = directory.appendingPathComponent("\(baseName).\(ext)")
            try FileManager.default.copyItem(at: audioURL, to: destination)
            items.append(destination)
        } else if !options.includeMetadata {
            throw ExportError.audioMissing
        }

        if options.includeMetadata {
            let metadata = makeMetadata(record: record, includeLocation: options.includeExactLocation)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            let metadataURL = directory.appendingPathComponent("\(baseName)-metadata.json")
            try data.write(to: metadataURL, options: .atomic)
            items.append(metadataURL)
        }

        guard !items.isEmpty else { throw ExportError.audioMissing }
        return RecordingExportPackage(items: items, temporaryDirectory: directory)
    }

    func friendlyBaseName(for record: RecordingEntity) -> String {
        let date = SPFormat.filenameDate.string(from: record.createdAt)
        let title = SPFormat.safeFilename(record.title, fallback: "Recording")
        return "\(title)_\(date)"
    }

    // MARK: - 元数据

    private func makeMetadata(record: RecordingEntity, includeLocation: Bool) -> RecordingMetadataExport {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let events = record.sortedEvents.map { event in
            EventExport(
                id: event.id.uuidString,
                startTime: event.startTime,
                endTime: event.endTimeValue,
                category: event.kind.rawValue,
                categoryLabel: event.kind.title,
                title: event.title,
                note: event.note,
                source: event.sourceRaw
            )
        }

        let analysis = analysisService.analysis(for: record)
        let summary: AnalysisExport? = analysis.map {
            AnalysisExport(
                algorithmVersion: $0.algorithmVersion,
                duration: $0.duration,
                sampleRate: $0.sampleRate,
                channels: $0.channels,
                peak: $0.peak,
                peakDBFS: $0.peakDBFS,
                rmsMean: $0.rmsMean,
                rmsDBFS: $0.rmsDBFS,
                bandLow: $0.bands.low,
                bandMid: $0.bands.mid,
                bandHigh: $0.bands.high,
                note: "RMS and band energy are values of the recorded signal, not calibrated dB SPL."
            )
        }

        return RecordingMetadataExport(
            format: "soundprint.recording-metadata",
            formatVersion: 1,
            exportedAt: Date(),
            appVersion: appVersion,
            appBuild: build,
            recording: RecordingInfoExport(
                id: record.id.uuidString,
                title: record.title,
                createdAt: record.createdAt,
                duration: record.duration,
                placeID: record.place?.id.uuidString,
                placeName: record.place?.name,
                tags: record.tags,
                note: record.note,
                weather: record.weather,
                fileName: storage.audioURL(for: record)?.lastPathComponent,
                format: record.audioFormat,
                sampleRate: record.sampleRate,
                channelCount: Int(record.channelCount),
                fileSize: record.fileSize,
                deviceModel: record.deviceModel,
                latitude: includeLocation ? record.coordinate?.latitude : nil,
                longitude: includeLocation ? record.coordinate?.longitude : nil,
                locationIncluded: includeLocation && record.coordinate != nil
            ),
            events: events,
            analysis: summary,
            privacyNote: "Soundprint does not send recordings to a server. This file was explicitly exported by the user."
        )
    }
}

// MARK: - DTO

struct RecordingMetadataExport: Codable {
    var format: String
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var appBuild: String
    var recording: RecordingInfoExport
    var events: [EventExport]
    var analysis: AnalysisExport?
    var privacyNote: String
}

struct RecordingInfoExport: Codable {
    var id: String
    var title: String
    var createdAt: Date
    var duration: Double
    var placeID: String?
    var placeName: String?
    var tags: [String]
    var note: String?
    var weather: String?
    var fileName: String?
    var format: String
    var sampleRate: Double
    var channelCount: Int
    var fileSize: Int64
    var deviceModel: String?
    var latitude: Double?
    var longitude: Double?
    var locationIncluded: Bool
}

struct EventExport: Codable {
    var id: String
    var startTime: Double
    var endTime: Double?
    var category: String
    var categoryLabel: String
    var title: String
    var note: String?
    var source: String
}

struct AnalysisExport: Codable {
    var algorithmVersion: String
    var duration: Double
    var sampleRate: Double
    var channels: Int
    var peak: Double
    var peakDBFS: Double
    var rmsMean: Double
    var rmsDBFS: Double
    var bandLow: Double
    var bandMid: Double
    var bandHigh: Double
    var note: String
}

enum ExportError: LocalizedError {
    case audioMissing
    case noData

    var errorDescription: String? {
        switch self {
        case .audioMissing: return "The audio file was not found. To export metadata only, include the record information."
        case .noData: return "There is no data to export."
        }
    }
}
