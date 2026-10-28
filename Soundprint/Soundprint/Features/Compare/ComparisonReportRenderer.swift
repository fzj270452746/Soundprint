//
//  ComparisonReportRenderer.swift
//  Soundprint
//
//  生成可分享的 PDF 比较报告：采集条件、共同区间、叠加波形、特征值、
//  频谱差与必要的解释性提示。
//

import UIKit

struct ComparisonReportPayload {
    let recordA: RecordingEntity
    let recordB: RecordingEntity
    let summaryA: AudioAnalysisSummary?
    let summaryB: AudioAnalysisSummary?
    let waveformA: WaveformCache?
    let waveformB: WaveformCache?
    let spectrogramA: SpectrogramCache?
    let spectrogramB: SpectrogramCache?
    let diff: SpectrogramDiffData?
    let range: ClosedRange<Double>
    let markersA: [TemporaryMarker]
    let markersB: [TemporaryMarker]
    let generatedAt: Date
}

enum ComparisonReportError: LocalizedError {
    case renderingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .renderingFailed: return "The comparison report could not be generated."
        case .writeFailed: return "The comparison report could not be saved."
        }
    }
}

final class ComparisonReportRenderer {
    static let shared = ComparisonReportRenderer()

    private let paper = UIColor(hex: 0xF4F0E7)
    private let surface = UIColor(hex: 0xFAF7F0)
    private let ink = UIColor(hex: 0x1B1A15)
    private let secondary = UIColor(hex: 0x5E5A4F)
    private let tertiary = UIColor(hex: 0x746F62)
    private let accent = UIColor(hex: 0xA64F2D)
    private let moss = UIColor(hex: 0x52674E)
    private let hairline = UIColor(hex: 0xD9D2C3)
    private let amber = UIColor(hex: 0x8E6427)

    private let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
    private let margin: CGFloat = 40

    private init() {}

    func generate(payload: ComparisonReportPayload) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: "Soundprint Comparison Report",
                kCGPDFContextCreator as String: "Soundprint",
                kCGPDFContextAuthor as String: "Soundprint"
            ]
            return format
        }())

        let data = renderer.pdfData { context in
            context.beginPage()
            drawFirstPage(payload: payload, context: context.cgContext)
            if payload.diff != nil || (payload.spectrogramA != nil && payload.spectrogramB != nil) {
                context.beginPage()
                drawSpectrumPage(payload: payload, context: context.cgContext)
            }
        }
        guard !data.isEmpty else { throw ComparisonReportError.renderingFailed }

        let formatter = DateFormatter()
        formatter.locale = SPFormat.displayLocale
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let fileName = "Soundprint-Comparison-\(formatter.string(from: payload.generatedAt))"
        let url = StorageManager.shared.tempFileURL(name: fileName, extension: "pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ComparisonReportError.writeFailed
        }
    }

    // MARK: - 第一页

    private func drawFirstPage(payload: ComparisonReportPayload, context: CGContext) {
        paper.setFill()
        context.fill(pageRect)

        let display = serifFont(25)
        draw("Soundprint", at: CGPoint(x: margin, y: 38), font: display, color: ink)
        draw("Comparison Report", at: CGPoint(x: margin, y: 72), font: sansFont(12, weight: .semibold), color: accent)

        let dateString = SPFormat.dateTime(payload.generatedAt)
        drawRight(dateString, right: pageRect.width - margin, y: 75, font: monoFont(8), color: tertiary)

        drawLine(from: CGPoint(x: margin, y: 98), to: CGPoint(x: pageRect.width - margin, y: 98), color: hairline)

        let columnWidth = (pageRect.width - margin * 2 - 14) / 2
        drawRecordingHeader(
            letter: "A",
            color: accent,
            record: payload.recordA,
            summary: payload.summaryA,
            rect: CGRect(x: margin, y: 114, width: columnWidth, height: 122)
        )
        drawRecordingHeader(
            letter: "B",
            color: moss,
            record: payload.recordB,
            summary: payload.summaryB,
            rect: CGRect(x: margin + columnWidth + 14, y: 114, width: columnWidth, height: 122)
        )

        let rangeText = "Common range  \(formatTime(payload.range.lowerBound))–\(formatTime(payload.range.upperBound))  /  \(formatTime(payload.range.upperBound - payload.range.lowerBound))"
        draw(rangeText, at: CGPoint(x: margin, y: 250), font: monoFont(9), color: accent)
        draw(
            "Feature values cover the entire recording; waveforms and spectral difference cover the selected common range.",
            at: CGPoint(x: margin, y: 266),
            width: pageRect.width - margin * 2,
            font: sansFont(8.5),
            color: tertiary
        )

        let waveRect = CGRect(x: margin, y: 289, width: pageRect.width - margin * 2, height: 122)
        drawWaveform(payload: payload, in: waveRect, context: context)

        drawStats(payload: payload, origin: CGPoint(x: margin, y: 432), width: pageRect.width - margin * 2)

        let caveatY: CGFloat = 613
        let caveatRect = CGRect(x: margin, y: caveatY, width: pageRect.width - margin * 2, height: 94)
        let caveat = UIBezierPath(roundedRect: caveatRect, cornerRadius: 8)
        UIColor(hex: 0xEAE4D7).setFill()
        caveat.fill()
        draw(
            "Comparison Caveats",
            at: CGPoint(x: margin + 12, y: caveatY + 11),
            font: sansFont(9, weight: .semibold),
            color: secondary
        )
        draw(
            "RMS · peak · band values are comparison values from the recording signal. Values vary with microphone model, distance, automatic gain, recording quality, and device orientation. They are not calibrated sound pressure levels (dB SPL), so they cannot establish how loud the ambient sound was. Record at the same place, distance, and device settings whenever possible.",
            at: CGPoint(x: margin + 12, y: caveatY + 27),
            width: pageRect.width - margin * 2 - 24,
            font: sansFont(7.8),
            color: secondary,
            lineLimit: 5
        )

        drawMarkers(payload: payload, y: 724)

        draw(
            "Soundprint — Sound Archive",
            at: CGPoint(x: margin, y: pageRect.height - 34),
            font: sansFont(7.5, weight: .medium),
            color: tertiary
        )
        drawRight(
            "1 / \(payload.diff == nil ? 1 : 2)",
            right: pageRect.width - margin,
            y: pageRect.height - 34,
            font: monoFont(7.5),
            color: tertiary
        )
    }

    private func drawRecordingHeader(
        letter: String,
        color: UIColor,
        record: RecordingEntity,
        summary: AudioAnalysisSummary?,
        rect: CGRect
    ) {
        let card = UIBezierPath(roundedRect: rect, cornerRadius: 9)
        surface.setFill()
        card.fill()
        hairline.setStroke()
        card.lineWidth = 0.4
        card.stroke()

        let badgeRect = CGRect(x: rect.minX + 10, y: rect.minY + 10, width: 17, height: 17)
        let badge = UIBezierPath(roundedRect: badgeRect, cornerRadius: 5)
        color.setFill()
        badge.fill()
        draw(letter, at: CGPoint(x: badgeRect.midX - 2.5, y: badgeRect.minY + 3.5), font: monoFont(8, weight: .bold), color: .white)

        draw(
            record.title,
            at: CGPoint(x: rect.minX + 34, y: rect.minY + 9),
            width: rect.width - 44,
            font: sansFont(11, weight: .semibold),
            color: ink,
            lineLimit: 2
        )
        var lines: [String] = []
        lines.append(SPFormat.shortDate.string(from: record.createdAt))
        lines.append(record.place?.name ?? "Unassigned")
        lines.append(SPFormat.duration(record.duration))
        lines.append(String(format: "%.1f kHz / %@", record.sampleRate / 1000, record.channelCount == 1 ? "Mono" : "\(record.channelCount)ch"))
        if let device = record.deviceModel {
            lines.append(device)
        }
        if let summary {
            lines.append(String(format: "Average RMS %.1f dBFS", summary.rmsDBFS))
        }
        let detail = lines.joined(separator: " · ")
        draw(
            detail,
            at: CGPoint(x: rect.minX + 12, y: rect.minY + 47),
            width: rect.width - 24,
            font: sansFont(7.8),
            color: secondary,
            lineLimit: 4
        )
    }

    private func drawWaveform(payload: ComparisonReportPayload, in rect: CGRect, context: CGContext) {
        let card = UIBezierPath(roundedRect: rect, cornerRadius: 9)
        surface.setFill()
        card.fill()
        hairline.setStroke()
        card.lineWidth = 0.4
        card.stroke()

        let plot = rect.insetBy(dx: 12, dy: 15)
        let midY = plot.midY
        hairline.setStroke()
        let center = UIBezierPath()
        center.move(to: CGPoint(x: plot.minX, y: midY))
        center.addLine(to: CGPoint(x: plot.maxX, y: midY))
        center.lineWidth = 0.4
        center.stroke()

        let barCount = 210
        let spacing = plot.width / CGFloat(barCount)
        let cacheA = payload.waveformA
        let cacheB = payload.waveformB
        let peakA = max(0.015, cacheA?.peak ?? 0.015)
        let peakB = max(0.015, cacheB?.peak ?? 0.015)
        let height = plot.height * 0.44

        for index in 0..<barCount {
            let fraction = (Double(index) + 0.5) / Double(barCount)
            let time = payload.range.lowerBound + fraction * (payload.range.upperBound - payload.range.lowerBound)
            let x = plot.minX + CGFloat(fraction) * plot.width
            if let amp = sample(cache: cacheA, time: time, peak: peakA) {
                accent.withAlphaComponent(0.85).setStroke()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: x, y: midY - 0.5))
                p.addLine(to: CGPoint(x: x, y: midY - max(0.4, CGFloat(amp) * height)))
                p.lineWidth = max(0.6, spacing * 0.55)
                p.stroke()
            }
            if let amp = sample(cache: cacheB, time: time, peak: peakB) {
                moss.withAlphaComponent(0.8).setStroke()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: x, y: midY + 0.5))
                p.addLine(to: CGPoint(x: x, y: midY + max(0.4, CGFloat(amp) * height)))
                p.lineWidth = max(0.6, spacing * 0.55)
                p.stroke()
            }
        }

        draw("A", at: CGPoint(x: plot.minX, y: rect.minY + 4), font: monoFont(7.5, weight: .bold), color: accent)
        draw("B", at: CGPoint(x: plot.minX + 14, y: rect.minY + 4), font: monoFont(7.5, weight: .bold), color: moss)
        drawRight(formatTime(payload.range.upperBound), right: rect.maxX - 12, y: rect.maxY - 14, font: monoFont(7), color: tertiary)
    }

    private func sample(cache: WaveformCache?, time: Double, peak: Float) -> Float? {
        guard let cache, !cache.buckets.isEmpty, cache.duration > 0, time >= 0, time <= cache.duration else { return nil }
        let index = min(cache.buckets.count - 1, max(0, Int(time / cache.duration * Double(cache.buckets.count))))
        let bucket = cache.buckets[index]
        let amplitude = max(abs(bucket.min), abs(bucket.max), bucket.rms * 1.25)
        return min(1, amplitude / max(0.001, peak))
    }

    private func drawStats(payload: ComparisonReportPayload, origin: CGPoint, width: CGFloat) {
        draw("Sound Features (Entire Recording)", at: origin, font: sansFont(10, weight: .semibold), color: ink)
        let headerY = origin.y + 20
        let labelWidth = width - 160
        draw("Metric", at: CGPoint(x: origin.x + 8, y: headerY), font: sansFont(7.5, weight: .semibold), color: tertiary)
        draw("A", at: CGPoint(x: origin.x + labelWidth + 30, y: headerY), font: monoFont(7.5, weight: .bold), color: accent)
        draw("B", at: CGPoint(x: origin.x + labelWidth + 110, y: headerY), font: monoFont(7.5, weight: .bold), color: moss)
        drawLine(from: CGPoint(x: origin.x, y: headerY + 14), to: CGPoint(x: origin.x + width, y: headerY + 14), color: hairline)

        let a = payload.summaryA
        let b = payload.summaryB
        let rows: [(String, String, String)] = [
            ("Average RMS", value(a?.rmsDBFS, suffix: " dBFS"), value(b?.rmsDBFS, suffix: " dBFS")),
            ("Digital Peak", value(a?.peakDBFS, suffix: " dBFS"), value(b?.peakDBFS, suffix: " dBFS")),
            ("Low Band Ratio", a.map { SPFormat.percent($0.bands.low) } ?? "—", b.map { SPFormat.percent($0.bands.low) } ?? "—"),
            ("Mid Band Ratio", a.map { SPFormat.percent($0.bands.mid) } ?? "—", b.map { SPFormat.percent($0.bands.mid) } ?? "—"),
            ("High Band Ratio", a.map { SPFormat.percent($0.bands.high) } ?? "—", b.map { SPFormat.percent($0.bands.high) } ?? "—"),
            ("Duration", SPFormat.duration(payload.recordA.duration), SPFormat.duration(payload.recordB.duration)),
            ("Sample Rate", String(format: "%.1f kHz", payload.recordA.sampleRate / 1000), String(format: "%.1f kHz", payload.recordB.sampleRate / 1000))
        ]
        var y = headerY + 21
        for (index, row) in rows.enumerated() {
            if index % 2 == 0 {
                UIColor(hex: 0xF1ECE2).setFill()
                UIBezierPath(rect: CGRect(x: origin.x, y: y - 3, width: width, height: 18)).fill()
            }
            draw(row.0, at: CGPoint(x: origin.x + 8, y: y), font: sansFont(7.8), color: secondary)
            draw(row.1, at: CGPoint(x: origin.x + labelWidth + 30, y: y), font: monoFont(7.5), color: accent)
            draw(row.2, at: CGPoint(x: origin.x + labelWidth + 110, y: y), font: monoFont(7.5), color: moss)
            y += 18
        }
        drawLine(from: CGPoint(x: origin.x, y: y - 3), to: CGPoint(x: origin.x + width, y: y - 3), color: hairline)

        let note = a == nil || b == nil
            ? "Note: Analysis is incomplete for one or both recordings. Regenerate after analysis finishes."
            : "Note: Values are signal values that include recording gain."
        draw(note, at: CGPoint(x: origin.x, y: y + 3), width: width, font: sansFont(7.2), color: tertiary)
    }

    private func drawMarkers(payload: ComparisonReportPayload, y: CGFloat) {
        var lines: [String] = []
        if !payload.markersA.isEmpty {
            lines.append("Temporary markers A: " + payload.markersA.map { formatTime($0.time) }.joined(separator: ", "))
        }
        if !payload.markersB.isEmpty {
            lines.append("Temporary markers B: " + payload.markersB.map { formatTime($0.time) }.joined(separator: ", "))
        }
        guard !lines.isEmpty else { return }
        draw(
            lines.joined(separator: "\n"),
            at: CGPoint(x: margin, y: y),
            width: pageRect.width - margin * 2,
            font: monoFont(7.5),
            color: secondary,
            lineLimit: 2
        )
    }

    // MARK: - 第二页：频谱

    private func drawSpectrumPage(payload: ComparisonReportPayload, context: CGContext) {
        paper.setFill()
        context.fill(pageRect)
        draw("Soundprint", at: CGPoint(x: margin, y: 38), font: serifFont(22), color: ink)
        draw("Spectrum Comparison", at: CGPoint(x: margin, y: 69), font: sansFont(12, weight: .semibold), color: accent)
        drawRight("2 / 2", right: pageRect.width - margin, y: 74, font: monoFont(8), color: tertiary)
        drawLine(from: CGPoint(x: margin, y: 92), to: CGPoint(x: pageRect.width - margin, y: 92), color: hairline)

        draw(
            "Simplified spectra normalized to each recording's peak, shown side by side over the common range. The lower panel shows the difference, B − A.",
            at: CGPoint(x: margin, y: 108),
            width: pageRect.width - margin * 2,
            font: sansFont(8.5),
            color: secondary
        )

        let imageWidth = (pageRect.width - margin * 2 - 12) / 2
        let startA = payload.recordA.duration > 0 ? CGFloat(payload.range.lowerBound / payload.recordA.duration) : 0
        let endA = payload.recordA.duration > 0 ? CGFloat(payload.range.upperBound / payload.recordA.duration) : 1
        let startB = payload.recordB.duration > 0 ? CGFloat(payload.range.lowerBound / payload.recordB.duration) : 0
        let endB = payload.recordB.duration > 0 ? CGFloat(payload.range.upperBound / payload.recordB.duration) : 1
        drawSpectrogram(payload.spectrogramA, letter: "A", color: accent, rect: CGRect(x: margin, y: 140, width: imageWidth, height: 140), visibleStart: startA, visibleEnd: endA)
        drawSpectrogram(payload.spectrogramB, letter: "B", color: moss, rect: CGRect(x: margin + imageWidth + 12, y: 140, width: imageWidth, height: 140), visibleStart: startB, visibleEnd: endB)

        draw("Spectral Difference (B − A)", at: CGPoint(x: margin, y: 308), font: sansFont(9.5, weight: .semibold), color: ink)
        let diffRect = CGRect(x: margin, y: 327, width: pageRect.width - margin * 2, height: 160)
        drawDiff(payload.diff, in: diffRect)

        let legendY = diffRect.maxY + 10
        drawLegend(text: "Stronger A", color: accent, at: CGPoint(x: margin, y: legendY))
        drawLegend(text: "Small Difference", color: hairline, at: CGPoint(x: margin + 90, y: legendY))
        drawLegend(text: "Stronger B", color: moss, at: CGPoint(x: margin + 190, y: legendY))

        if let summary = payload.diff?.summary {
            draw(summary, at: CGPoint(x: margin, y: legendY + 24), width: pageRect.width - margin * 2, font: sansFont(9), color: secondary)
        }

        let note = "The spectral difference is a display of each recording normalized independently. It varies with recording gain, device, distance, and the composition of surrounding sound. It does not establish a difference in sound pressure level or the type of sound."
        draw(note, at: CGPoint(x: margin, y: legendY + 50), width: pageRect.width - margin * 2, font: sansFont(8), color: secondary, lineLimit: 4)

        let infoY: CGFloat = 620
        let infoRect = CGRect(x: margin, y: infoY, width: pageRect.width - margin * 2, height: 78)
        UIColor(hex: 0xEAE4D7).setFill()
        UIBezierPath(roundedRect: infoRect, cornerRadius: 8).fill()
        draw("Recording Conditions", at: CGPoint(x: margin + 12, y: infoY + 10), font: sansFont(9, weight: .semibold), color: secondary)
        let conditionText = [
            "A: \(payload.recordA.deviceModel ?? "Unknown device") · \(String(format: "%.1f kHz", payload.recordA.sampleRate / 1000)) · \(payload.recordA.channelCount)ch",
            "B: \(payload.recordB.deviceModel ?? "Unknown device") · \(String(format: "%.1f kHz", payload.recordB.sampleRate / 1000)) · \(payload.recordB.channelCount)ch"
        ].joined(separator: "\n")
        draw(conditionText, at: CGPoint(x: margin + 12, y: infoY + 26), width: pageRect.width - margin * 2 - 24, font: monoFont(7.5), color: secondary, lineLimit: 3)

        draw("Soundprint — Sound Archive", at: CGPoint(x: margin, y: pageRect.height - 34), font: sansFont(7.5, weight: .medium), color: tertiary)
    }

    private func drawSpectrogram(
        _ cache: SpectrogramCache?,
        letter: String,
        color: UIColor,
        rect: CGRect,
        visibleStart: CGFloat,
        visibleEnd: CGFloat
    ) {
        let background = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        surface.setFill()
        background.fill()
        hairline.setStroke()
        background.lineWidth = 0.4
        background.stroke()
        draw(letter, at: CGPoint(x: rect.minX + 8, y: rect.minY + 6), font: monoFont(8, weight: .bold), color: color)
        guard let cache, cache.columns > 0, cache.bands > 0 else {
            draw("Pending analysis", at: CGPoint(x: rect.minX + 12, y: rect.midY - 4), font: sansFont(8), color: tertiary)
            return
        }
        let plot = rect.insetBy(dx: 8, dy: 20)
        let low = UIColor(hex: 0xDDCBB2)
        let mid = amber
        let high = accent
        let start = max(0, min(1, visibleStart))
        let end = max(start + 0.001, min(1, visibleEnd))
        let startColumn = max(0, min(cache.columns - 1, Int(floor(Double(start) * Double(cache.columns)))))
        let endColumn = max(startColumn + 1, min(cache.columns, Int(ceil(Double(end) * Double(cache.columns)))))
        let visibleColumns = max(1, endColumn - startColumn)
        let colWidth = plot.width / CGFloat(visibleColumns)
        let bandHeight = plot.height / CGFloat(cache.bands)
        for band in 0..<cache.bands {
            for column in startColumn..<endColumn {
                let index = band * cache.columns + column
                guard index < cache.values.count else { continue }
                let value = CGFloat(max(0, min(1, cache.values[index])))
                guard value > 0.02 else { continue }
                let cellColor: UIColor
                if value < 0.55 {
                    cellColor = low.blended(with: mid, fraction: value / 0.55)
                } else {
                    cellColor = mid.blended(with: high, fraction: (value - 0.55) / 0.45)
                }
                cellColor.withAlphaComponent(0.15 + 0.85 * value).setFill()
                let y = plot.maxY - CGFloat(band + 1) * bandHeight
                UIRectFill(CGRect(x: plot.minX + CGFloat(column - startColumn) * colWidth, y: y, width: colWidth + 0.5, height: bandHeight + 0.4))
            }
        }
        draw("Selected range", at: CGPoint(x: plot.minX, y: rect.maxY - 13), font: monoFont(6.5), color: tertiary)
        drawRight("\(Int(cache.duration))s", right: rect.maxX - 8, y: rect.maxY - 13, font: monoFont(6.5), color: tertiary)
    }

    private func drawDiff(_ data: SpectrogramDiffData?, in rect: CGRect) {
        let background = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor(hex: 0xF1ECE2).setFill()
        background.fill()
        guard let data, data.columns > 0, data.bands > 0 else {
            draw("Shown when analysis is complete", at: CGPoint(x: rect.minX + 12, y: rect.midY - 4), font: sansFont(8), color: tertiary)
            return
        }
        let plot = rect.insetBy(dx: 8, dy: 8)
        let colWidth = plot.width / CGFloat(data.columns)
        let bandHeight = plot.height / CGFloat(data.bands)
        for band in 0..<data.bands {
            for column in 0..<data.columns {
                let index = band * data.columns + column
                guard index < data.values.count else { continue }
                let diff = CGFloat(max(-1, min(1, data.values[index])))
                guard abs(diff) > 0.02 else { continue }
                let color = diff >= 0 ? moss : accent
                color.withAlphaComponent(0.12 + 0.88 * min(1, abs(diff))).setFill()
                let y = plot.maxY - CGFloat(band + 1) * bandHeight
                UIRectFill(CGRect(x: plot.minX + CGFloat(column) * colWidth, y: y, width: colWidth + 0.5, height: bandHeight + 0.4))
            }
        }
        hairline.withAlphaComponent(0.4).setStroke()
        for fraction in [0.25, 0.5, 0.75] {
            let p = UIBezierPath()
            let y = plot.minY + plot.height * CGFloat(fraction)
            p.move(to: CGPoint(x: plot.minX, y: y))
            p.addLine(to: CGPoint(x: plot.maxX, y: y))
            p.lineWidth = 0.3
            p.stroke()
        }
    }

    // MARK: - 绘制工具

    private func value(_ double: Double?, suffix: String) -> String {
        guard let double else { return "—" }
        return String(format: "%.1f%@", double, suffix)
    }

    private func formatTime(_ seconds: Double) -> String {
        SPFormat.duration(max(0, seconds))
    }

    @discardableResult
    private func draw(
        _ text: String,
        at point: CGPoint,
        width: CGFloat? = nil,
        font: UIFont,
        color: UIColor,
        lineLimit: Int = 1
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineLimit > 1 ? .byWordWrapping : .byTruncatingTail
        paragraph.lineSpacing = 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let availableWidth = width ?? (pageRect.width - point.x - margin)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = min(bounding.height, CGFloat(lineLimit) * font.lineHeight + CGFloat(max(0, lineLimit - 1)) * 1.5)
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: availableWidth, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return height
    }

    private func drawRight(_ text: String, right: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: right - size.width, y: y), withAttributes: attributes)
    }

    private func drawLine(from: CGPoint, to: CGPoint, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        color.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawLegend(text: String, color: UIColor, at point: CGPoint) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x, y: point.y + 2, width: 5, height: 5)).fill()
        draw(text, at: CGPoint(x: point.x + 9, y: point.y), font: sansFont(7.5), color: secondary)
    }

    private func serifFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "HiraMinProN-W6", size: size) ?? UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    private func sansFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func monoFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}
