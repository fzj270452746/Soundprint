//
//  RecordingActivityAttributes.swift
//  Shared between the UIKit app and the WidgetKit Live Activity extension.
//

import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 用于 SwiftUI Text(timerInterval:) 的持续计时起点。
        var effectiveStartDate: Date
        /// 暂停时显示的累计录音时长。
        var elapsed: TimeInterval
        var isPaused: Bool
        var placeName: String?
        var statusText: String
    }

    var sessionID: String
    var qualityTitle: String
    var startedAt: Date
}
