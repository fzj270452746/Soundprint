//
//  RecordingLiveActivityWidget.swift
//  SoundprintLiveActivity
//
//  Live Activity UI. WidgetKit requires SwiftUI in the extension; the main app remains UIKit.
//

import ActivityKit
import SwiftUI
import WidgetKit

private extension Color {
    static let spInk = Color(red: 0.106, green: 0.102, blue: 0.082)
    static let spPaper = Color(red: 0.957, green: 0.941, blue: 0.906)
    static let spCream = Color(red: 0.945, green: 0.914, blue: 0.851)
    static let spAccent = Color(red: 0.906, green: 0.631, blue: 0.455)
    static let spRecord = Color(red: 0.878, green: 0.345, blue: 0.259)
    static let spMuted = Color(red: 0.678, green: 0.651, blue: 0.592)
    static let spDarkSurface = Color(red: 0.145, green: 0.137, blue: 0.110)
}

@available(iOS 16.1, *)
private struct TimerText: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Self.format(state.elapsed))
                .monospacedDigit()
        } else {
            Text(timerInterval: state.effectiveStartDate...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

@available(iOS 16.1, *)
private struct LockScreenRecordingView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.spRecord.opacity(0.22))
                    .frame(width: 46, height: 46)
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.spAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(context.state.isPaused ? Color.spAccent : Color.spRecord)
                        .frame(width: 6, height: 6)
                    Text(context.state.statusText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.spMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(context.attributes.qualityTitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.spMuted)
                }

                TimerText(state: context.state)
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.spPaper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let place = context.state.placeName {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 8, weight: .semibold))
                        Text(place)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.spMuted)
                }
            }

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index == 2 ? Color.spAccent : Color.spAccent.opacity(0.35))
                        .frame(width: 3, height: CGFloat(12 + index * 4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color.spInk)
        .activitySystemActionForegroundColor(Color.spCream)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Soundprint recording")
        .accessibilityValue(context.state.isPaused ? "Paused" : "Recording")
    }
}

@available(iOS 16.1, *)
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenRecordingView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        Circle()
                            .fill(Color.spRecord.opacity(0.25))
                            .frame(width: 34, height: 34)
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.spAccent)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.statusText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.spMuted)
                        TimerText(state: context.state)
                            .font(.system(size: 22, weight: .light, design: .monospaced))
                            .foregroundStyle(Color.spPaper)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Soundprint")
                            .font(.system(size: 9, weight: .medium, design: .serif))
                            .foregroundStyle(Color.spMuted)
                        if let place = context.state.placeName {
                            Text(place)
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(Color.spMuted)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9))
                        Text(context.attributes.qualityTitle)
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text("Saved on this device")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Color.spMuted)
                    .padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isPaused ? Color.spAccent : Color.spRecord)
                        .frame(width: 6, height: 6)
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.spAccent)
                }
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.spCream)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.spAccent)
            }
            .keylineTint(Color.spAccent)
            .widgetURL(URL(string: "soundprint://recording"))
        }
    }
}

@available(iOS 16.1, *)
@main
struct SoundprintLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
