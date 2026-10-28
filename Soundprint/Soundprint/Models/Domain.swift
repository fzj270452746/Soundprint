//
//  Domain.swift
//  Soundprint
//
//  界面与业务层共用的领域枚举和设置项。
//

import AVFoundation
import Foundation
import UIKit

// MARK: - 地点类型

enum PlaceKind: String, CaseIterable, Codable {
    case street
    case indoor
    case nature
    case transport
    case commercial
    case equipment
    case studio
    case other

    var title: String {
        switch self {
        case .street: return "Street"
        case .indoor: return "Indoor"
        case .nature: return "Nature"
        case .transport: return "Transport"
        case .commercial: return "Commercial"
        case .equipment: return "Equipment"
        case .studio: return "Studio"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .street: return "map"
        case .indoor: return "house.fill"
        case .nature: return "leaf.fill"
        case .transport: return "tram.fill"
        case .commercial: return "bag.fill"
        case .equipment: return "wrench.fill"
        case .studio: return "waveform"
        case .other: return "mappin.and.ellipse"
        }
    }

    var color: UIColor { SPColor.tint(for: self) }
    var softColor: UIColor { SPColor.softTint(for: self) }
}

// MARK: - 声音事件

enum EventKind: String, CaseIterable, Codable {
    case voice
    case vehicle
    case bird
    case wind
    case rain
    case water
    case machine
    case alarm
    case footsteps
    case door
    case music
    case other

    var title: String {
        switch self {
        case .voice: return "Voices"
        case .vehicle: return "Vehicles"
        case .bird: return "Birds"
        case .wind: return "Wind"
        case .rain: return "Rain"
        case .water: return "Water"
        case .machine: return "Machinery"
        case .alarm: return "Alarms"
        case .footsteps: return "Footsteps"
        case .door: return "Doors & Windows"
        case .music: return "Music"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .voice: return "person.2.fill"
        case .vehicle: return "car.fill"
        case .bird: return "bird.fill"
        case .wind: return "wind"
        case .rain: return "cloud.rain.fill"
        case .water: return "drop.fill"
        case .machine: return "gearshape.fill"
        case .alarm: return "bell.fill"
        case .footsteps: return "figure.walk"
        case .door: return "rectangle.portrait.fill"
        case .music: return "music.note"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    var color: UIColor { SPColor.tint(for: self) }
}

// MARK: - 分析状态

enum AnalysisState: String, Codable {
    case pending
    case processing
    case ready
    case failed
    case disabled

    var title: String {
        switch self {
        case .pending: return "Pending analysis"
        case .processing: return "Analyzing"
        case .ready: return "Analyzed"
        case .failed: return "Analysis failed"
        case .disabled: return "Analysis off"
        }
    }

    var isBusy: Bool { self == .pending || self == .processing }
}

// MARK: - 录音质量

enum RecordingQuality: String, CaseIterable, Codable {
    case standard
    case high
    case long

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High Quality"
        case .long: return "Long Recording"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "AAC · 44.1 kHz · 128 kbps"
        case .high: return "AAC · 48 kHz · 192 kbps"
        case .long: return "AAC · 44.1 kHz · 64 kbps"
        }
    }

    var explanation: String {
        switch self {
        case .standard: return "A balanced setting for everyday recordings."
        case .high: return "For preserving subtle detail in the sound."
        case .long: return "Records long ambient sessions with smaller files."
        }
    }

    var sampleRate: Double {
        switch self {
        case .standard, .long: return 44_100
        case .high: return 48_000
        }
    }

    var bitRate: Int {
        switch self {
        case .standard: return 128_000
        case .high: return 192_000
        case .long: return 64_000
        }
    }

    var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    /// 每小时大致占用空间（约数，用于提示）。
    var estimatedMegabytesPerHour: Int {
        Int(Double(bitRate) * 3600 / 8 / 1_000_000)
    }
}

// MARK: - 位置精度

enum LocationPrecision: String, CaseIterable, Codable {
    case none
    case approximate
    case precise

    var title: String {
        switch self {
        case .none: return "Don't Save"
        case .approximate: return "Approximate"
        case .precise: return "Precise"
        }
    }

    var detail: String {
        switch self {
        case .none: return "No location is stored"
        case .approximate: return "Rounded to about 1 km"
        case .precise: return "Stores the exact coordinates"
        }
    }
}

// MARK: - 录音状态

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case paused
    case finalizing
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .finalizing: return "Finalizing"
        case .failed: return "Recording failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .recording, .paused, .preparing, .finalizing: return true
        case .idle, .failed: return false
        }
    }
}

// MARK: - 录音中的临时事件标记

struct RecordingMarker: Identifiable, Equatable, Codable {
    let id: UUID
    var time: Double
    var kind: EventKind
    var title: String
}

// MARK: - 对比工作区的临时标记

struct TemporaryMarker: Identifiable, Equatable {
    let id: UUID
    var time: Double
    var title: String
}

// MARK: - 应用设置

enum SPDefaultsKey {
    static let onboardingCompleted = "sp.onboarding.completed"
    static let recordingQuality = "sp.recording.quality"
    static let autoAnalysis = "sp.analysis.automatic"
    static let suggestEvents = "sp.analysis.suggestEvents"
    static let lastExportIncludeLocation = "sp.export.includeLocation"
    static let pendingDeletions = "sp.storage.pendingDeletions"
}

enum SPNotification {
    static let libraryDidChange = Notification.Name("sp.library.didChange")
    static let analysisDidChange = Notification.Name("sp.analysis.didChange")
    static let suggestionsDidChange = Notification.Name("sp.analysis.suggestionsDidChange")
    static let storageDidChange = Notification.Name("sp.storage.didChange")
    static let recordingInterrupted = Notification.Name("sp.recording.interrupted")
    static let recordingResumed = Notification.Name("sp.recording.resumed")
}

// MARK: - 标签建议

enum SPSuggestions {
    static let tags = ["Morning", "Night", "Quiet", "Lively", "Rain", "Wind", "Nature", "Traffic", "Machinery", "Waterside", "Birds", "Indoor", "Outdoors", "Construction"]
    static let weather = ["Sunny", "Cloudy", "Rain", "Wind", "Snow", "Humid"]
    static let eventTitles: [EventKind: [String]] = [
        .voice: ["Conversation", "Cheers", "Children's voices"],
        .vehicle: ["Car", "Train", "Aircraft", "Bicycle"],
        .bird: ["Small birds", "Crows", "Waterfowl"],
        .wind: ["Breeze", "Gust"],
        .rain: ["Light rain", "Heavy rain", "Dripping"],
        .water: ["River", "Waves", "Fountain"],
        .machine: ["Motor", "Air conditioning", "Construction"],
        .alarm: ["Alarm", "Chime"],
        .footsteps: ["Footsteps", "Multiple footsteps"],
        .door: ["Door", "Window", "Shutter"],
        .music: ["Music", "Instrument", "Singing"],
        .other: ["Other sounds"]
    ]
}

// MARK: - 格式化

enum SPFormat {
    static let displayLocale = Locale(identifier: "en_US")

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d (EEE)"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M/d/yyyy"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func duration(_ seconds: Double, includeHours: Bool = true) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 && includeHours {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// 用于短事件候选，显示到 0.1 秒。
    static func preciseDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
        let totalTenths = Int((seconds * 10).rounded())
        let minutes = totalTenths / 600
        let secs = Double(totalTenths % 600) / 10
        return String(format: "%d:%04.1f", minutes, secs)
    }

    static func accessibleDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0 sec" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sec") }
        return parts.joined(separator: " ")
    }

    static func relativeDate(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch days {
        case ..<0: return mediumDate.string(from: date)
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        case 7...29: return "\(days / 7) weeks ago"
        default:
            return shortDate.string(from: date)
        }
    }

    static func lastRecorded(_ date: Date?) -> String {
        guard let date else { return "No recordings yet" }
        return "Last recorded \(relativeDate(date))"
    }

    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func decibel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    static func durationLabel(_ seconds: Double) -> String {
        "\(duration(seconds, includeHours: false))"
    }

    static func dateTime(_ date: Date) -> String {
        "\(fullDate.string(from: date)) \(time.string(from: date))"
    }

    static func safeFilename(_ raw: String, fallback: String = "Soundprint") -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = raw.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(60))
        return limited.isEmpty ? fallback : limited
    }

    static func todayLine() -> String {
        let now = Date()
        return "\(fullDate.string(from: now))"
    }
}
