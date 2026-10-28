//
//  ManagedObjects.swift
//  Soundprint
//
//  Core Data 实体。原始音频不进入数据库，只保存沙盒内相对路径。
//

import CoreData
import Foundation

@objc(PlaceEntity)
final class PlaceEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var placeTypeRaw: String
    @NSManaged var note: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var hasCoordinates: Bool
    @NSManaged var locationPrecisionRaw: String
    @NSManaged var tagsData: Data?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var archivedAt: Date?
    @NSManaged var recordings: Set<RecordingEntity>

    var kind: PlaceKind {
        get { PlaceKind(rawValue: placeTypeRaw) ?? .other }
        set { placeTypeRaw = newValue.rawValue }
    }

    var precision: LocationPrecision {
        get { LocationPrecision(rawValue: locationPrecisionRaw) ?? .none }
        set { locationPrecisionRaw = newValue.rawValue }
    }

    var tags: [String] {
        get { TagCodec.decode(tagsData) }
        set { tagsData = TagCodec.encode(newValue) }
    }

    var sortedRecordings: [RecordingEntity] {
        recordings.sorted { $0.createdAt > $1.createdAt }
    }

    var coordinate: Coordinate? {
        guard hasCoordinates else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

@objc(RecordingEntity)
final class RecordingEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var duration: Double
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var relativeAudioPath: String
    @NSManaged var fileSize: Int64
    @NSManaged var audioFormat: String
    @NSManaged var sampleRate: Double
    @NSManaged var channelCount: Int16
    @NSManaged var deviceModel: String?
    @NSManaged var note: String?
    @NSManaged var weather: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var hasCoordinates: Bool
    @NSManaged var waveformRelativePath: String?
    @NSManaged var analysisStatusRaw: String
    @NSManaged var tagsData: Data?
    @NSManaged var place: PlaceEntity?
    @NSManaged var events: Set<SoundEventEntity>
    @NSManaged var analysis: AudioAnalysisEntity?

    var analysisState: AnalysisState {
        get { AnalysisState(rawValue: analysisStatusRaw) ?? .pending }
        set { analysisStatusRaw = newValue.rawValue }
    }

    var tags: [String] {
        get { TagCodec.decode(tagsData) }
        set { tagsData = TagCodec.encode(newValue) }
    }

    var sortedEvents: [SoundEventEntity] {
        events.sorted { $0.startTime < $1.startTime }
    }

    var coordinate: Coordinate? {
        guard hasCoordinates else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

@objc(SoundEventEntity)
final class SoundEventEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var startTime: Double
    @NSManaged var endTime: Double
    @NSManaged var hasEndTime: Bool
    @NSManaged var categoryRaw: String
    @NSManaged var title: String
    @NSManaged var note: String?
    @NSManaged var sourceRaw: String
    @NSManaged var confidence: Double
    @NSManaged var hasConfidence: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var recording: RecordingEntity?

    var kind: EventKind {
        get { EventKind(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var isSuggested: Bool { sourceRaw == "suggested" }

    var endTimeValue: Double? {
        get { hasEndTime ? endTime : nil }
        set {
            if let newValue {
                endTime = newValue
                hasEndTime = true
            } else {
                endTime = 0
                hasEndTime = false
            }
        }
    }
}

@objc(AudioAnalysisEntity)
final class AudioAnalysisEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var algorithmVersion: String
    @NSManaged var windowSize: Int32
    @NSManaged var hopSize: Int32
    @NSManaged var peakValue: Double
    @NSManaged var rmsMean: Double
    @NSManaged var rmsDBFS: Double
    @NSManaged var bandLow: Double
    @NSManaged var bandMid: Double
    @NSManaged var bandHigh: Double
    @NSManaged var analysisRelativePath: String
    @NSManaged var spectrogramRelativePath: String?
    @NSManaged var createdAt: Date
    @NSManaged var recording: RecordingEntity?
}

// MARK: - 值类型

struct Coordinate: Equatable {
    var latitude: Double
    var longitude: Double

    /// 记录“大致位置”时进行约 1 km 的网格化。
    func roundedForApproximate() -> Coordinate {
        Coordinate(
            latitude: (latitude * 100).rounded() / 100,
            longitude: (longitude * 100).rounded() / 100
        )
    }
}

enum TagCodec {
    static func encode(_ tags: [String]) -> Data? {
        let cleaned = cleanedTags(tags)
        guard !cleaned.isEmpty else { return nil }
        return try? JSONEncoder().encode(cleaned)
    }

    static func decode(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func cleanedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 24, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return Array(result.prefix(12))
    }
}
