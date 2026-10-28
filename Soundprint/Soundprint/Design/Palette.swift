//
//  Palette.swift
//  Soundprint
//
//  声音地点档案的视觉基调：温暖纸张、墨色文字、陶土色强调。
//

import UIKit

enum SPColor {
    // MARK: - 基础色

    /// 页面底色。浅色为暖纸色，深色为低饱和炭黑。
    static let paper = dynamic(light: 0xF4F0E7, dark: 0x11120F)
    /// 卡片底色，比页面略亮/略深。
    static let surface = dynamic(light: 0xFAF7F0, dark: 0x1A1C17)
    /// 次级容器，用于内嵌区块。
    static let sunken = dynamic(light: 0xEAE4D7, dark: 0x24271F)
    /// 主文字。
    static let ink = dynamic(light: 0x1B1A15, dark: 0xF1EDE2)
    /// 次级文字。
    static let secondaryInk = dynamic(light: 0x5E5A4F, dark: 0xAAA598)
    /// 三级文字与辅助信息。
    static let tertiaryInk = dynamic(light: 0x746F62, dark: 0x938E80)
    /// 分隔线。
    static let hairline = dynamic(light: 0xD9D2C3, dark: 0x33362D)
    /// 强分隔线。
    static let strongHairline = dynamic(light: 0xC4BAAB, dark: 0x44483C)
    /// 陶土色强调色。
    static let accent = dynamic(light: 0xA64F2D, dark: 0xE7A174)
    /// 强调色的柔和背景。
    static let accentSoft = dynamic(light: 0xF0DED2, dark: 0x3A251C)
    /// 录音状态的朱红色。
    static let record = dynamic(light: 0xC34830, dark: 0xF07861)
    /// 苔绿色，表示完成或自然。
    static let moss = dynamic(light: 0x52674E, dark: 0x9DB594)
    static let mossSoft = dynamic(light: 0xE0E6D9, dark: 0x263024)
    /// 提醒用的赭黄。
    static let amber = dynamic(light: 0x8E6427, dark: 0xE2B66C)
    static let amberSoft = dynamic(light: 0xF2E6CE, dark: 0x342B1A)
    /// 危险操作。
    static let danger = dynamic(light: 0xB5392F, dark: 0xEE867D)
    static let dangerSoft = dynamic(light: 0xF4DEDA, dark: 0x3A211E)
    /// 反色文字（放在强调色上）。
    static let onAccent = dynamic(light: 0xFFFBF3, dark: 0x23150F)
    /// 覆盖层。
    static let scrim = UIColor.black.withAlphaComponent(0.38)

    // MARK: - 波形与频谱

    static let waveform = dynamic(light: 0x4D4A41, dark: 0xD6D0C2)
    static let waveformPlayed = accent
    static let waveformMuted = dynamic(light: 0xD5CEC0, dark: 0x3B3E34)
    static let spectrogramLow = dynamic(light: 0xE8D9C4, dark: 0x201F1A)
    static let spectrogramHigh = accent

    // MARK: - 类型颜色

    static func tint(for kind: PlaceKind) -> UIColor {
        switch kind {
        case .street:      return dynamic(light: 0x7A5A46, dark: 0xD4AC8F)
        case .indoor:      return dynamic(light: 0x646A55, dark: 0xBFC8A9)
        case .nature:      return dynamic(light: 0x4D6A56, dark: 0xA7C9AE)
        case .transport:   return dynamic(light: 0x50647F, dark: 0xACC4E0)
        case .commercial:  return dynamic(light: 0x8B5C55, dark: 0xE2AEA6)
        case .equipment:   return dynamic(light: 0x6B6252, dark: 0xCBC1AC)
        case .studio:      return dynamic(light: 0x6B5578, dark: 0xCBB6D8)
        case .other:       return secondaryInk
        }
    }

    static func softTint(for kind: PlaceKind) -> UIColor {
        tint(for: kind).withAlphaComponent(0.13)
    }

    static func tint(for event: EventKind) -> UIColor {
        switch event {
        case .voice:      return dynamic(light: 0x8B5C55, dark: 0xE2AEA6)
        case .vehicle:    return dynamic(light: 0x50647F, dark: 0xACC4E0)
        case .bird:       return dynamic(light: 0x4D6A56, dark: 0xA7C9AE)
        case .wind:       return dynamic(light: 0x5A6F70, dark: 0xB2CFD0)
        case .rain:       return dynamic(light: 0x4D6375, dark: 0xA9C4D8)
        case .water:      return dynamic(light: 0x426A72, dark: 0xA0CCD4)
        case .machine:    return dynamic(light: 0x6B6252, dark: 0xCBC1AC)
        case .alarm:      return dynamic(light: 0xA64F2D, dark: 0xE7A174)
        case .footsteps:  return dynamic(light: 0x7A5A46, dark: 0xD4AC8F)
        case .door:       return dynamic(light: 0x6B5578, dark: 0xCBB6D8)
        case .music:      return dynamic(light: 0x6D5B82, dark: 0xD2BCE8)
        case .other:      return secondaryInk
        }
    }

    // MARK: - 工具

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

