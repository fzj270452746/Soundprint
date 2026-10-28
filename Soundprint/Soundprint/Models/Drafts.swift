//
//  Drafts.swift
//  Soundprint
//
//  表单与业务层之间的值对象，避免把 UI 状态直接写入 Core Data。
//

import Foundation

struct PlaceDraft {
    var name: String
    var kind: PlaceKind
    var note: String?
    var tags: [String]
    var coordinate: Coordinate?
    var precision: LocationPrecision
}

struct RecordingEditDraft {
    var title: String
    var placeID: UUID?
    var tags: [String]
    var note: String?
    var weather: String?
    var coordinate: Coordinate?
    var precision: LocationPrecision
    var markers: [RecordingMarker]?
    var createdAt: Date?
}

struct RecordingSaveDraft {
    var title: String
    var temporaryAudioURL: URL
    var placeID: UUID?
    var tags: [String]
    var note: String?
    var weather: String?
    var coordinate: Coordinate?
    var precision: LocationPrecision
    var duration: Double
    var sampleRate: Double
    var channelCount: Int
    var deviceModel: String
    var markers: [RecordingMarker]
    var createdAt: Date
}

enum PlaceDeletionStrategy {
    case deleteRecordings
    case detachRecordings
}
