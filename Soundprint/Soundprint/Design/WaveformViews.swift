//
//  WaveformViews.swift
//  Soundprint
//
//  波形、实时电平、声谱图与录音按钮。颜色之外始终提供文字或数值说明。
//

import UIKit

struct WaveformMarkerDisplay {
    var time: Double
    var color: UIColor
    var title: String
}

final class SPWaveformView: UIControl {
    var cache: WaveformCache? {
        didSet {
            setNeedsDisplay()
            updateAccessibilityValue()
        }
    }

    var duration: Double = 0 {
        didSet { updateAccessibilityValue() }
    }

    var progress: CGFloat = 0 {
        didSet {
            let clamped = min(1, max(0, progress))
            if abs(progress - clamped) > 0.0001 {
                progress = clamped
                return
            }
            setNeedsDisplay()
            updateAccessibilityValue()
        }
    }

    var markers: [WaveformMarkerDisplay] = [] {
        didSet {
            setNeedsDisplay()
            updateMarkerAccessibilityActions()
        }
    }

    /// 比较页可切换“按峰值归一化”与“原始幅度”。
    var normalizeToPeak = true {
        didSet { setNeedsDisplay() }
    }

    var showsPlayhead = true {
        didSet { setNeedsDisplay() }
    }

    var tint: UIColor = SPColor.waveform {
        didSet { setNeedsDisplay() }
    }

    var playedTint: UIColor = SPColor.accent {
        didSet { setNeedsDisplay() }
    }

    var isLoading: Bool = false {
        didSet { setNeedsDisplay() }
    }

    var onSeek: ((Double) -> Void)?

    private let feedback = UISelectionFeedbackGenerator()
    private var lastFeedbackBucket = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = "Waveform"
        accessibilityTraits = .adjustable
        isUserInteractionEnabled = true
        contentMode = .redraw
        backgroundColor = .clear
        isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        updateMarkerAccessibilityActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 96)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), rect.width > 4, rect.height > 4 else { return }
        context.clear(rect)

        let midY = rect.midY
        let usableHeight = rect.height * 0.76
        let centerLine = UIBezierPath()
        centerLine.move(to: CGPoint(x: rect.minX + 2, y: midY))
        centerLine.addLine(to: CGPoint(x: rect.maxX - 2, y: midY))
        SPColor.hairline.withAlphaComponent(0.7).setStroke()
        centerLine.lineWidth = 0.5
        centerLine.stroke()

        guard let cache, !cache.buckets.isEmpty, cache.duration > 0 else {
            drawPlaceholder(in: rect, context: context)
            return
        }

        let barCount = min(220, max(36, Int(rect.width / 4.2)))
        let barSpacing = rect.width / CGFloat(barCount)
        let barWidth = max(1, barSpacing * 0.52)
        let peakScale: Float = normalizeToPeak ? max(0.015, cache.peak) : 1
        let playedX = rect.minX + rect.width * progress

        let dimPath = UIBezierPath()
        let brightPath = UIBezierPath()

        for bar in 0..<barCount {
            let start = Int(Float(bar) / Float(barCount) * Float(cache.buckets.count))
            let end = max(start + 1, Int(Float(bar + 1) / Float(barCount) * Float(cache.buckets.count)))
            let boundedEnd = min(cache.buckets.count, end)
            guard start < boundedEnd else { continue }

            var minimum: Float = 0
            var maximum: Float = 0
            var rmsSum: Float = 0
            for idx in start..<boundedEnd {
                let bucket = cache.buckets[idx]
                minimum = min(minimum, bucket.min)
                maximum = max(maximum, bucket.max)
                rmsSum += bucket.rms
            }
            let rms = rmsSum / Float(boundedEnd - start)
            let upward = max(maximum, rms * 1.35)
            let downward = max(-minimum, rms * 1.35)
            let topAmp = min(1, CGFloat(upward / peakScale)) * usableHeight / 2
            let bottomAmp = min(1, CGFloat(downward / peakScale)) * usableHeight / 2
            let x = rect.minX + (CGFloat(bar) + 0.5) * barSpacing
            let path = x < playedX ? brightPath : dimPath
            path.move(to: CGPoint(x: x, y: midY - max(0.65, topAmp)))
            path.addLine(to: CGPoint(x: x, y: midY + max(0.65, bottomAmp)))
        }

        tint.withAlphaComponent(0.46).setStroke()
        dimPath.lineWidth = barWidth
        dimPath.lineCapStyle = .round
        dimPath.stroke()

        playedTint.setStroke()
        brightPath.lineWidth = barWidth
        brightPath.lineCapStyle = .round
        brightPath.stroke()

        if duration > 0 {
            for marker in markers {
                guard marker.time >= 0, marker.time <= duration else { continue }
                let x = rect.minX + rect.width * CGFloat(marker.time / duration)
                let line = UIBezierPath()
                line.move(to: CGPoint(x: x, y: rect.minY + 2))
                line.addLine(to: CGPoint(x: x, y: rect.maxY - 2))
                marker.color.withAlphaComponent(0.24).setStroke()
                line.lineWidth = 1
                line.stroke()

                let dot = UIBezierPath(ovalIn: CGRect(x: x - 2.5, y: rect.minY + 1, width: 5, height: 5))
                marker.color.setFill()
                dot.fill()
            }
        }

        if showsPlayhead {
            let playheadX = rect.minX + rect.width * min(1, max(0, progress))
            context.setStrokeColor(SPColor.ink.withAlphaComponent(0.48).cgColor)
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: playheadX, y: rect.minY))
            context.addLine(to: CGPoint(x: playheadX, y: rect.maxY))
            context.strokePath()
        }
    }

    private func drawPlaceholder(in rect: CGRect, context: CGContext) {
        let barCount = max(28, Int(rect.width / 4))
        let barSpacing = rect.width / CGFloat(barCount)
        let path = UIBezierPath()
        for bar in 0..<barCount {
            let phase = Double(bar) * 0.55
            let envelope = 0.25 + 0.65 * abs(sin(phase)) * abs(cos(phase * 0.47))
            let amp = rect.height * 0.24 * CGFloat(envelope)
            let x = rect.minX + (CGFloat(bar) + 0.5) * barSpacing
            path.move(to: CGPoint(x: x, y: rect.midY - amp))
            path.addLine(to: CGPoint(x: x, y: rect.midY + amp))
        }
        tint.withAlphaComponent(isLoading ? 0.16 : 0.22).setStroke()
        path.lineWidth = max(1, barSpacing * 0.45)
        path.lineCapStyle = .round
        path.stroke()
    }

    // MARK: - 交互

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        seek(at: gesture.location(in: self).x)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let x = gesture.location(in: self).x
        switch gesture.state {
        case .began:
            feedback.prepare()
            seek(at: x)
        case .changed:
            seek(at: x)
        default:
            break
        }
    }

    private func seek(at x: CGFloat) {
        guard bounds.width > 0 else { return }
        let fraction = min(1, max(0, x / bounds.width))
        progress = fraction
        let bucket = Int(fraction * 20)
        if bucket != lastFeedbackBucket {
            lastFeedbackBucket = bucket
            feedback.selectionChanged()
        }
        onSeek?(Double(fraction) * duration)
        sendActions(for: .valueChanged)
    }

    override func accessibilityIncrement() {
        progress = min(1, progress + 0.05)
        onSeek?(Double(progress) * duration)
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        progress = max(0, progress - 0.05)
        onSeek?(Double(progress) * duration)
        sendActions(for: .valueChanged)
    }

    private func updateAccessibilityValue() {
        let current = duration > 0 ? Double(progress) * duration : 0
        if duration > 0 {
            let markerText = markers.isEmpty ? "" : ", \(markers.count) events"
            accessibilityValue = "\(SPFormat.accessibleDuration(current)), \(SPFormat.accessibleDuration(duration)) total\(markerText)"
        } else {
            accessibilityValue = nil
        }
        accessibilityHint = duration > 0 ? "Swipe left or right to move the playback position. Use custom actions to jump between events." : nil
    }

    private func updateMarkerAccessibilityActions() {
        var actions: [UIAccessibilityCustomAction] = [
            UIAccessibilityCustomAction(name: "Jump to Start", target: self, selector: #selector(accessibilitySeekStart))
        ]
        if !markers.isEmpty {
            actions.append(UIAccessibilityCustomAction(name: "Next Event", target: self, selector: #selector(accessibilityNextEvent)))
            actions.append(UIAccessibilityCustomAction(name: "Previous Event", target: self, selector: #selector(accessibilityPreviousEvent)))
        }
        accessibilityCustomActions = actions
    }

    @objc private func accessibilitySeekStart() -> Bool {
        progress = 0
        onSeek?(0)
        sendActions(for: .valueChanged)
        UIAccessibility.post(notification: .announcement, argument: "Moved to start")
        return true
    }

    @objc private func accessibilityNextEvent() -> Bool {
        let current = Double(progress) * duration
        guard let marker = markers.sorted(by: { $0.time < $1.time }).first(where: { $0.time > current + 0.15 }) else {
            UIAccessibility.post(notification: .announcement, argument: "No next event")
            return false
        }
        seekToMarker(marker)
        return true
    }

    @objc private func accessibilityPreviousEvent() -> Bool {
        let current = Double(progress) * duration
        guard let marker = markers.sorted(by: { $0.time < $1.time }).last(where: { $0.time < current - 0.15 }) else {
            UIAccessibility.post(notification: .announcement, argument: "No previous event")
            return false
        }
        seekToMarker(marker)
        return true
    }

    private func seekToMarker(_ marker: WaveformMarkerDisplay) {
        guard duration > 0 else { return }
        progress = CGFloat(min(1, max(0, marker.time / duration)))
        onSeek?(marker.time)
        sendActions(for: .valueChanged)
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(marker.title), \(SPFormat.accessibleDuration(marker.time))"
        )
    }
}

// MARK: - 实时录音电平

final class SPLiveMeterView: UIView {
    private var levels = [Float](repeating: 0, count: 42)
    private var currentLevel: Float = 0
    private var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "Input level"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(levels: [Float], level: Float, active: Bool) {
        self.levels = levels
        self.currentLevel = level
        self.isActive = active
        setNeedsDisplay()
        accessibilityValue = active ? "Input detected" : "No input"
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let barCount = max(28, min(56, Int(rect.width / 7)))
        let spacing = rect.width / CGFloat(barCount)
        let maxHeight = rect.height * 0.88
        let mid = rect.midY

        context.setStrokeColor(SPColor.hairline.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: rect.minX, y: mid))
        context.addLine(to: CGPoint(x: rect.maxX, y: mid))
        context.strokePath()

        for index in 0..<barCount {
            let sampleIndex = min(levels.count - 1, max(0, levels.count - barCount + index))
            let raw = CGFloat(levels[sampleIndex])
            // 历史条越靠右越新；新条略高，形成轻缓的呼吸。
            let envelope = 0.75 + 0.25 * CGFloat(index) / CGFloat(max(1, barCount - 1))
            let amplitude = max(1.5, raw * maxHeight * envelope)
            let x = rect.minX + (CGFloat(index) + 0.5) * spacing
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: mid - amplitude))
            path.addLine(to: CGPoint(x: x, y: mid + amplitude))
            path.lineWidth = max(2, spacing * 0.44)
            path.lineCapStyle = .round
            let isRecent = index >= barCount - 6
            if isRecent && isActive {
                SPColor.record.setStroke()
            } else {
                SPColor.waveform.withAlphaComponent(isActive ? 0.58 : 0.3).setStroke()
            }
            path.stroke()
        }

        if isActive {
            let dotRadius = 3 + CGFloat(currentLevel) * 3
            let dotRect = CGRect(
                x: rect.maxX - 2 - dotRadius,
                y: rect.minY + 4 - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            SPColor.record.setFill()
            UIBezierPath(ovalIn: dotRect).fill()
        }
    }
}

// MARK: - 声谱图

final class SPSpectrogramView: UIView {
    var cache: SpectrogramCache? {
        didSet {
            setNeedsDisplay()
            updateSpectrogramAccessibility()
        }
    }

    /// 比较时只显示共同区间对应的列。
    var visibleStartFraction: CGFloat = 0 { didSet { setNeedsDisplay() } }
    var visibleEndFraction: CGFloat = 1 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "Simplified spectrogram"
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 138)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        context.saveGState()
        path.addClip()

        SPColor.sunken.setFill()
        context.fill(rect)

        guard let cache, cache.columns > 0, cache.bands > 0, !cache.values.isEmpty else {
            drawGrid(context: context, rect: rect)
            context.restoreGState()
            return
        }

        let startFraction = max(0, min(1, visibleStartFraction))
        let endFraction = max(startFraction, max(startFraction + 0.001, min(1, visibleEndFraction)))
        let startColumn = max(0, min(cache.columns - 1, Int(floor(Double(startFraction) * Double(cache.columns)))))
        let endColumn = max(startColumn + 1, min(cache.columns, Int(ceil(Double(endFraction) * Double(cache.columns)))))
        let visibleColumns = max(1, endColumn - startColumn)
        let columnWidth = rect.width / CGFloat(visibleColumns)
        let bandHeight = rect.height / CGFloat(cache.bands)
        let lowColor = UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: 0x2E2A22)
                : UIColor(hex: 0xEEE5D5)
        })
        let midColor = SPColor.amber
        let highColor = SPColor.accent

        for band in 0..<cache.bands {
            for column in startColumn..<endColumn {
                let index = band * cache.columns + column
                guard index < cache.values.count else { continue }
                let value = CGFloat(max(0, min(1, cache.values[index])))
                guard value > 0.015 else { continue }
                let color: UIColor
                if value < 0.55 {
                    color = lowColor.blended(with: midColor, fraction: value / 0.55)
                } else {
                    color = midColor.blended(with: highColor, fraction: (value - 0.55) / 0.45)
                }
                context.setFillColor(color.withAlphaComponent(0.18 + 0.82 * value).cgColor)
                let y = rect.height - CGFloat(band + 1) * bandHeight
                context.fill(CGRect(
                    x: CGFloat(column - startColumn) * columnWidth,
                    y: y,
                    width: columnWidth + 0.6,
                    height: bandHeight + 0.4
                ))
            }
        }

        drawGrid(context: context, rect: rect)
        context.restoreGState()
    }

    private func updateSpectrogramAccessibility() {
        guard let cache, cache.columns > 0, cache.bands > 0, !cache.values.isEmpty else {
            accessibilityLabel = "Simplified spectrogram"
            accessibilityValue = "No data"
            return
        }
        var low: Double = 0, mid: Double = 0, high: Double = 0
        for band in 0..<cache.bands {
            for column in 0..<cache.columns {
                let index = band * cache.columns + column
                guard index < cache.values.count else { continue }
                let value = Double(cache.values[index])
                if band < cache.bands / 3 {
                    low += value
                } else if band < cache.bands * 2 / 3 {
                    mid += value
                } else {
                    high += value
                }
            }
        }
        let total = low + mid + high
        let lowPercent = total > 0 ? Int((low / total * 100).rounded()) : 0
        let midPercent = total > 0 ? Int((mid / total * 100).rounded()) : 0
        let highPercent = total > 0 ? Int((high / total * 100).rounded()) : 0
        accessibilityLabel = "Simplified spectrogram. 0 to \(Int(cache.maxFrequency)) hertz."
        accessibilityValue = "Low band \(lowPercent) percent, mid band \(midPercent) percent, high band \(highPercent) percent. A normalized relative view."
        accessibilityHint = "Shows relative energy over time and frequency."
    }

    private func drawGrid(context: CGContext, rect: CGRect) {
        context.setStrokeColor(SPColor.hairline.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(0.5)
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.height * CGFloat(fraction)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        context.strokePath()
    }
}

// MARK: - 录音按钮

final class SPRecordButton: UIControl {
    private let ringLayer = CAShapeLayer()
    private let innerLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let micView = UIImageView()
    private var pulseLayer: CAShapeLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 86).isActive = true
        heightAnchor.constraint(equalToConstant: 86).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = "Start Recording"
        accessibilityTraits = .button

        layer.addSublayer(ringLayer)
        layer.addSublayer(innerLayer)
        layer.addSublayer(dotLayer)

        micView.translatesAutoresizingMaskIntoConstraints = false
        micView.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium))
        micView.contentMode = .scaleAspectFit
        micView.isUserInteractionEnabled = false
        addSubview(micView)
        NSLayoutConstraint.activate([
            micView.centerXAnchor.constraint(equalTo: centerXAnchor),
            micView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                let scale: CGFloat = self.isHighlighted && !UIAccessibility.isReduceMotionEnabled ? 0.94 : 1
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ringRadius = min(bounds.width, bounds.height) / 2 - 3
        let innerRadius = ringRadius - 12

        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(
            arcCenter: center,
            radius: ringRadius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        ).cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 1
        ringLayer.strokeColor = SPColor.accent.withAlphaComponent(0.35).cgColor

        innerLayer.frame = bounds
        innerLayer.path = UIBezierPath(
            arcCenter: center,
            radius: innerRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
        innerLayer.fillColor = SPColor.accent.cgColor

        dotLayer.frame = bounds
        let dotSize: CGFloat = 9
        dotLayer.path = UIBezierPath(
            ovalIn: CGRect(
                x: bounds.maxX - 20,
                y: 10,
                width: dotSize,
                height: dotSize
            )
        ).cgPath
        dotLayer.fillColor = SPColor.record.cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateColors()
            setNeedsLayout()
        }
    }

    private func updateColors() {
        micView.tintColor = SPColor.onAccent
        setNeedsLayout()
    }

    func pulseIfNeeded() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        pulseLayer?.removeFromSuperlayer()
        let pulse = CAShapeLayer()
        pulse.frame = bounds
        pulse.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).cgPath
        pulse.fillColor = UIColor.clear.cgColor
        pulse.strokeColor = SPColor.accent.withAlphaComponent(0.4).cgColor
        pulse.lineWidth = 1
        layer.insertSublayer(pulse, at: 0)
        pulseLayer = pulse

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.18
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.7
        opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 1.6
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.repeatCount = 1
        pulse.add(group, forKey: "pulse")
    }
}

// MARK: - 颜色混合

extension UIColor {
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        let t = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return self
        }
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}

// MARK: - RMS 趋势

final class SPRMSTrendView: UIView {
    private var values: [Float] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "RMS level trend"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(values: [Float]) {
        self.values = values
        setNeedsDisplay()
        guard let maxValue = values.max(), let minValue = values.min(), maxValue > 0 else {
            accessibilityValue = "No data"
            return
        }
        let maxPercent = Int((Double(maxValue) * 100).rounded())
        let minPercent = Int((Double(minValue) * 100).rounded())
        let first = values.prefix(values.count / 4).reduce(0, +) / Float(max(1, values.count / 4))
        let last = values.suffix(values.count / 4).reduce(0, +) / Float(max(1, values.count / 4))
        let trend: String
        if last > first * 1.1 {
            trend = "rising toward the end"
        } else if last < first * 0.9 {
            trend = "falling toward the end"
        } else {
            trend = "little overall change"
        }
        accessibilityValue = "Peak \(maxPercent) percent, minimum \(minPercent) percent, \(trend)."
        accessibilityHint = "Relative level trend of the recorded signal."
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let inset = rect.insetBy(dx: 1, dy: 6)
        let rounded = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        context.saveGState()
        rounded.addClip()
        SPColor.sunken.setFill()
        context.fill(rect)

        context.setStrokeColor(SPColor.hairline.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)
        for fraction in [0.25, 0.5, 0.75] {
            let y = inset.minY + inset.height * CGFloat(fraction)
            context.move(to: CGPoint(x: inset.minX, y: y))
            context.addLine(to: CGPoint(x: inset.maxX, y: y))
        }
        context.strokePath()

        guard values.count > 1 else {
            context.restoreGState()
            return
        }
        let maxValue = max(0.001, values.max() ?? 0)
        let step = inset.width / CGFloat(values.count - 1)
        let line = UIBezierPath()
        let fill = UIBezierPath()
        fill.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        for (index, value) in values.enumerated() {
            let normalized = CGFloat(max(0, value)) / CGFloat(maxValue)
            let point = CGPoint(
                x: inset.minX + CGFloat(index) * step,
                y: inset.maxY - normalized * inset.height * 0.88
            )
            if index == 0 {
                line.move(to: point)
            } else {
                line.addLine(to: point)
            }
            fill.addLine(to: point)
        }
        fill.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        fill.close()

        SPColor.accent.withAlphaComponent(0.12).setFill()
        fill.fill()
        SPColor.accent.setStroke()
        line.lineWidth = 1.5
        line.lineJoinStyle = .round
        line.stroke()
        context.restoreGState()
    }
}

// MARK: - 播放按钮

final class SPPlayButton: UIButton {
    var isPlaying: Bool = false {
        didSet { update() }
    }

    init(size: CGFloat = 52) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        layer.cornerRadius = size / 2
        backgroundColor = SPColor.ink
        tintColor = SPColor.paper
        accessibilityLabel = "Play"
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    func update() {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        accessibilityLabel = isPlaying ? "Pause" : "Play"
    }
}

// MARK: - A/B 叠加波形

final class SPOverlayWaveformView: UIControl {
    var cacheA: WaveformCache? { didSet { setNeedsDisplay() } }
    var cacheB: WaveformCache? { didSet { setNeedsDisplay() } }
    var durationA: Double = 0
    var durationB: Double = 0
    var rangeStart: Double = 0 { didSet { setNeedsDisplay() } }
    var rangeLength: Double = 1 { didSet { setNeedsDisplay() } }
    var currentTime: Double = 0 {
        didSet {
            setNeedsDisplay()
            updateAccessibility()
        }
    }
    var normalizeToPeak = true { didSet { setNeedsDisplay() } }
    var onSeek: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Overlaid waveforms A and B. A points up, B points down."
        accessibilityTraits = .adjustable
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 126)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), rect.width > 8, rect.height > 8 else { return }
        let midY = rect.midY
        let usableHeight = rect.height * 0.72 / 2
        let barCount = min(240, max(48, Int(rect.width / 3.6)))
        let spacing = rect.width / CGFloat(barCount)
        let barWidth = max(1, spacing * 0.58)

        context.setStrokeColor(SPColor.hairline.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: rect.minX, y: midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: midY))
        context.strokePath()

        guard let cacheA, let cacheB, rangeLength > 0 else { return }
        let peakA = normalizeToPeak ? max(0.015, cacheA.peak) : 1
        let peakB = normalizeToPeak ? max(0.015, cacheB.peak) : 1

        for index in 0..<barCount {
            let fraction = (CGFloat(index) + 0.5) / CGFloat(barCount)
            let time = rangeStart + Double(fraction) * rangeLength
            let x = rect.minX + fraction * rect.width
            let ampA = sampleAmplitude(cache: cacheA, time: time, peak: peakA) * usableHeight
            let ampB = sampleAmplitude(cache: cacheB, time: time, peak: peakB) * usableHeight
            if ampA > 0.5 {
                SPColor.accent.withAlphaComponent(0.86).setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: midY - 1))
                path.addLine(to: CGPoint(x: x, y: midY - max(0.7, ampA)))
                path.lineWidth = barWidth
                path.lineCapStyle = .round
                path.stroke()
            }
            if ampB > 0.5 {
                SPColor.moss.withAlphaComponent(0.82).setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: midY + 1))
                path.addLine(to: CGPoint(x: x, y: midY + max(0.7, ampB)))
                path.lineWidth = barWidth
                path.lineCapStyle = .round
                path.stroke()
            }
        }

        let end = rangeStart + rangeLength
        if currentTime >= rangeStart, currentTime <= end {
            let fraction = CGFloat((currentTime - rangeStart) / rangeLength)
            let x = rect.minX + rect.width * min(1, max(0, fraction))
            context.setStrokeColor(SPColor.ink.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(0.9)
            context.move(to: CGPoint(x: x, y: rect.minY + 2))
            context.addLine(to: CGPoint(x: x, y: rect.maxY - 2))
            context.strokePath()
        }
    }

    private func sampleAmplitude(cache: WaveformCache, time: Double, peak: Float) -> CGFloat {
        guard !cache.buckets.isEmpty, cache.duration > 0, time >= 0, time <= cache.duration else { return 0 }
        let index = min(cache.buckets.count - 1, max(0, Int(time / cache.duration * Double(cache.buckets.count))))
        let bucket = cache.buckets[index]
        let amplitude = max(abs(bucket.min), abs(bucket.max), bucket.rms * 1.25)
        return CGFloat(min(1, amplitude / max(0.001, peak)))
    }

    private func seek(at x: CGFloat) {
        guard bounds.width > 0, rangeLength > 0 else { return }
        let fraction = min(1, max(0, x / bounds.width))
        currentTime = rangeStart + Double(fraction) * rangeLength
        onSeek?(currentTime)
        sendActions(for: .valueChanged)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        seek(at: gesture.location(in: self).x)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            seek(at: gesture.location(in: self).x)
        default:
            break
        }
    }

    override func accessibilityIncrement() {
        seek(at: bounds.width * min(1, CGFloat((currentTime - rangeStart) / max(0.001, rangeLength)) + 0.05))
    }

    override func accessibilityDecrement() {
        seek(at: bounds.width * max(0, CGFloat((currentTime - rangeStart) / max(0.001, rangeLength)) - 0.05))
    }

    private func updateAccessibility() {
        let local = max(0, min(rangeLength, currentTime - rangeStart))
        accessibilityValue = "Selected range \(SPFormat.accessibleDuration(rangeStart)) to \(SPFormat.accessibleDuration(rangeStart + rangeLength)). Current \(SPFormat.accessibleDuration(rangeStart + local))"
        accessibilityHint = "Swipe left or right to move the playback position"
    }
}

// MARK: - 频谱差异热图

struct SpectrogramDiffData {
    var columns: Int
    var bands: Int
    var values: [Float]
    var summary: String
    var startTime: Double
    var endTime: Double
}

final class SPDiffSpectrogramView: UIView {
    var data: SpectrogramDiffData? {
        didSet {
            setNeedsDisplay()
            if let data {
                accessibilityLabel = "Spectral difference. \(data.summary). \(SPFormat.accessibleDuration(data.startTime)) to \(SPFormat.accessibleDuration(data.endTime))."
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "Spectral difference"
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 118)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let rounded = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        context.saveGState()
        rounded.addClip()
        SPColor.sunken.setFill()
        context.fill(rect)

        guard let data, data.columns > 0, data.bands > 0 else {
            drawEmptyGrid(context: context, rect: rect)
            context.restoreGState()
            return
        }
        let cellWidth = rect.width / CGFloat(data.columns)
        let cellHeight = rect.height / CGFloat(data.bands)
        let neutral = SPColor.sunken

        for band in 0..<data.bands {
            for column in 0..<data.columns {
                let index = band * data.columns + column
                guard index < data.values.count else { continue }
                let diff = CGFloat(max(-1, min(1, data.values[index])))
                if abs(diff) < 0.025 { continue }
                let base = diff >= 0 ? SPColor.moss : SPColor.accent
                let color = base.withAlphaComponent(0.14 + 0.86 * min(1, abs(diff)))
                context.setFillColor(color.cgColor)
                let y = rect.height - CGFloat(band + 1) * cellHeight
                context.fill(CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: y,
                    width: cellWidth + 0.6,
                    height: cellHeight + 0.4
                ))
            }
        }
        // 中央线提示这是零差异切面。
        context.setStrokeColor(neutral.withAlphaComponent(0.1).cgColor)
        context.setLineWidth(0.5)
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.height * CGFloat(fraction)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawEmptyGrid(context: CGContext, rect: CGRect) {
        context.setStrokeColor(SPColor.hairline.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.height * CGFloat(fraction)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        context.strokePath()
    }
}
