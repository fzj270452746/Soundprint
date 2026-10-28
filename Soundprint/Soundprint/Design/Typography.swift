//
//  Typography.swift
//  Soundprint
//
//  日文界面使用明朝体作标题、系统无衬线体作正文，技术数字使用等宽字体。
//

import UIKit

enum SPFont {
    /// 品牌字标：优先使用 New York，营造安静的编辑感。
    static func wordmark(_ size: CGFloat = 30) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: base)
        }
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font)
    }

    /// 日文大标题：Hiragino Mincho。若设备不可用则回退到系统衬线体。
    static func display(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .largeTitle) -> UIFont {
        let fallback = serifFallback(size: size)
        let base: UIFont
        if let mincho = UIFont(name: "HiraMinProN-W6", size: size) {
            base = mincho
        } else {
            base = fallback
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }

    static func text(_ size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    /// 数字与时间：等宽字体，减少跳动。
    static func mono(_ size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    static func monoTechnical(_ size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: base)
    }

    static let body = text(16, weight: .regular)
    static let bodyMedium = text(16, weight: .medium)
    static let callout = text(14, weight: .regular)
    static let caption = text(12, weight: .regular)
    static let micro = text(11, weight: .medium)

    private static func serifFallback(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

enum SPMetric {
    static let screenInset: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let controlHeight: CGFloat = 52
    static let minimumTouch: CGFloat = 44
    static let sectionGap: CGFloat = 32
    static let stackGap: CGFloat = 14
}

extension UILabel {
    /// 生成统一风格的小节标签。
    static func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: SPFont.micro,
                .foregroundColor: SPColor.secondaryInk,
                .kern: 1.4
            ]
        )
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}
