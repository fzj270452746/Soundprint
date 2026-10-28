//
//  ArtViews.swift
//  Soundprint
//
//  品牌图形：以同心声波、断裂弧线和波形条构成“声音指纹”。
//

import UIKit

final class SPOrbitalArtView: UIView {
    enum Variant {
        case large
        case compact
        case dual
    }

    private let variant: Variant
    private let contentLayer = CALayer()
    private var isAnimating = false

    init(variant: Variant = .large) {
        self.variant = variant
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(contentLayer)
        isAccessibilityElement = true
        accessibilityLabel = "Soundprint sound mark"
        accessibilityTraits = .image

        if variant == .large {
            widthAnchor.constraint(equalToConstant: 210).isActive = true
            heightAnchor.constraint(equalToConstant: 210).isActive = true
        } else if variant == .compact {
            widthAnchor.constraint(equalToConstant: 96).isActive = true
            heightAnchor.constraint(equalToConstant: 96).isActive = true
        } else {
            widthAnchor.constraint(equalToConstant: 130).isActive = true
            heightAnchor.constraint(equalToConstant: 90).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuild()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            rebuild()
        }
    }

    func startAnimating() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        guard !isAnimating else { return }
        isAnimating = true
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 90
        rotation.repeatCount = .infinity
        contentLayer.add(rotation, forKey: "slowRotation")
    }

    func stopAnimating() {
        isAnimating = false
        contentLayer.removeAllAnimations()
    }

    private func rebuild() {
        contentLayer.frame = bounds
        contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard bounds.width > 10 else { return }

        switch variant {
        case .large:
            drawRings(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: bounds.width * 0.46)
        case .compact:
            drawRings(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: bounds.width * 0.42)
        case .dual:
            drawDualWaves()
        }
    }

    private func drawRings(center: CGPoint, radius: CGFloat) {
        let ink = SPColor.ink
        let accent = SPColor.accent

        let ringSpecs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (1.0, 0.86, -2.45, 0.95, 1.2),
            (0.74, 0.91, 0.35, 2.15, 1.5),
            (0.48, 0.72, -2.95, 0.25, 2.0),
            (0.23, 0.9, 0.55, 1.7, 2.4)
        ]

        for (fraction, widthScale, start, end, lineWidth) in ringSpecs {
            let circle = CAShapeLayer()
            circle.frame = contentLayer.bounds
            circle.fillColor = UIColor.clear.cgColor
            circle.strokeColor = ink.withAlphaComponent(widthScale).cgColor
            circle.lineWidth = lineWidth
            circle.lineCap = .round
            let path = UIBezierPath(
                arcCenter: center,
                radius: radius * fraction,
                startAngle: start,
                endAngle: end,
                clockwise: true
            )
            circle.path = path.cgPath
            contentLayer.addSublayer(circle)
        }

        // 中心的声音条
        let barCount = 5
        let barWidth: CGFloat = 4
        let gap: CGFloat = 4
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = center.x - totalWidth / 2
        let heights: [CGFloat] = [0.14, 0.38, 0.62, 0.36, 0.18].map { $0 * radius }
        for index in 0..<barCount {
            let bar = CALayer()
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: center.y - heights[index] / 2,
                width: barWidth,
                height: heights[index]
            )
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = ink.cgColor
            contentLayer.addSublayer(bar)
        }

        let dot = CAShapeLayer()
        let dotSize: CGFloat = variant == .large ? 12 : 8
        dot.frame = contentLayer.bounds
        dot.path = UIBezierPath(
            ovalIn: CGRect(
                x: center.x + radius * 0.48,
                y: center.y - radius * 0.78,
                width: dotSize,
                height: dotSize
            )
        ).cgPath
        dot.fillColor = accent.cgColor
        contentLayer.addSublayer(dot)

        // 一条跨越圆环的细线，增加档案刻度的感觉。
        let tick = CAShapeLayer()
        tick.frame = contentLayer.bounds
        tick.strokeColor = ink.withAlphaComponent(0.22).cgColor
        tick.lineWidth = 0.8
        tick.lineCap = .round
        let line = UIBezierPath()
        line.move(to: CGPoint(x: center.x - radius * 1.08, y: center.y))
        line.addLine(to: CGPoint(x: center.x - radius * 0.7, y: center.y))
        tick.path = line.cgPath
        contentLayer.addSublayer(tick)
    }

    private func drawDualWaves() {
        let accent = SPColor.accent
        let moss = SPColor.moss
        let rows: [(UIColor, CGFloat)] = [(accent, 0.34), (moss, 0.66)]
        for (rowIndex, spec) in rows.enumerated() {
            let path = UIBezierPath()
            let centerY = bounds.height * spec.1
            let amplitude = bounds.height * 0.15
            let count = 38
            let step = bounds.width / CGFloat(count)
            for i in 0..<count {
                let phase = Double(i) * 0.44 + Double(rowIndex) * 1.6
                let envelope = 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.33))
                let height = amplitude * CGFloat(envelope)
                let x = CGFloat(i) * step + step / 2
                path.move(to: CGPoint(x: x, y: centerY - height))
                path.addLine(to: CGPoint(x: x, y: centerY + height))
            }
            let layer = CAShapeLayer()
            layer.frame = contentLayer.bounds
            layer.path = path.cgPath
            layer.strokeColor = spec.0.withAlphaComponent(rowIndex == 0 ? 0.82 : 0.62).cgColor
            layer.lineWidth = 2.2
            layer.lineCap = .round
            contentLayer.addSublayer(layer)
        }
    }
}

// MARK: - 背景声波纹样

final class SPWaveBackdropView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: rect.maxX * 0.82, y: rect.midY)
        context.setStrokeColor(SPColor.ink.withAlphaComponent(0.07).cgColor)
        context.setLineWidth(0.8)
        for index in 1...6 {
            let radius = CGFloat(index) * rect.width * 0.105
            context.addArc(
                center: center,
                radius: radius,
                startAngle: -.pi * 0.85,
                endAngle: .pi * 0.5,
                clockwise: false
            )
            context.strokePath()
        }
        context.setFillColor(SPColor.accent.withAlphaComponent(0.12).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
    }
}

// MARK: - 空状态小图

final class SPSmallWaveArtView: UIView {
    var tintColorOverride: UIColor = SPColor.accent

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        let count = 17
        let step = rect.width / CGFloat(count)
        for index in 0..<count {
            let phase = Double(index) * 0.57
            let envelope = 0.22 + 0.78 * abs(sin(phase))
            let height = rect.height * 0.4 * CGFloat(envelope)
            let x = CGFloat(index) * step + step / 2
            path.move(to: CGPoint(x: x, y: rect.midY - height))
            path.addLine(to: CGPoint(x: x, y: rect.midY + height))
        }
        tintColorOverride.setStroke()
        path.lineWidth = max(1.5, step * 0.34)
        path.lineCapStyle = .round
        path.stroke()
    }
}
