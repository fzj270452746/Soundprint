//
//  RecordingLiveActivityManager.swift
//  Soundprint
//
//  锁屏 / 灵动岛录音状态。主 App 仍使用 UIKit；仅系统 Live Activity 扩展使用 SwiftUI。
//

import ActivityKit
import Foundation

@available(iOS 16.2, *)
@MainActor
final class RecordingLiveActivityManager {
    static let shared = RecordingLiveActivityManager()

    private var activity: Activity<RecordingActivityAttributes>?

    var isActive: Bool { activity != nil }

    private init() {}

    func start(placeName: String?, quality: RecordingQuality) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let attributes = RecordingActivityAttributes(
            sessionID: UUID().uuidString,
            qualityTitle: quality.title,
            startedAt: Date()
        )
        let state = RecordingActivityAttributes.ContentState(
            effectiveStartDate: Date(),
            elapsed: 0,
            isPaused: false,
            placeName: placeName,
            statusText: "Recording"
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            NSLog("Live Activity start failed: %@", String(describing: error))
        }
    }

    func update(elapsed: TimeInterval, isPaused: Bool, placeName: String?) {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            effectiveStartDate: Date().addingTimeInterval(-max(0, elapsed)),
            elapsed: max(0, elapsed),
            isPaused: isPaused,
            placeName: placeName,
            statusText: isPaused ? "Paused" : "Recording"
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(statusText: String = "Saved") {
        guard let activity else { return }
        self.activity = nil
        let state = RecordingActivityAttributes.ContentState(
            effectiveStartDate: Date(),
            elapsed: 0,
            isPaused: true,
            placeName: nil,
            statusText: statusText
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    /// App 启动时没有活动的录音流程，清理上次异常退出遗留的 Live Activity。
    static func endStaleActivitiesIfNeeded() {
        Task { @MainActor in
            guard !RecordingFlowCoordinator.shared.isActive else { return }
            let activities = Activity<RecordingActivityAttributes>.activities
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
