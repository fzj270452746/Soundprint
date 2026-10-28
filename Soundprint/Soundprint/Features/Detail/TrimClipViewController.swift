//
//  TrimClipViewController.swift
//  Soundprint
//
//  Non-destructive excerpt: exports an audio range as a new recording. The original recording is never modified.
//

import AVFoundation
import UIKit

final class TrimClipViewController: SPViewController {
    var onSaved: ((RecordingEntity) -> Void)?

    private let record: RecordingEntity
    private let library = LibraryService.shared
    private let storage = StorageManager.shared
    private let audioURL: URL?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 16)
    private let waveform = SPWaveformView()
    private let selectionOverlay = SPScopeSelectionOverlay()
    private lazy var startSlider = SPTimeSliderView(title: "Start", value: initialStart, duration: record.duration)
    private lazy var endSlider = SPTimeSliderView(title: "End", value: initialEnd, duration: record.duration)
    private let startValue = UILabel()
    private let endValue = UILabel()
    private let lengthValue = UILabel()
    private let previewButton = SPButton(title: "Play Selection", symbol: "play.fill", style: .secondary)
    private let saveButton = SPButton(title: "Save Excerpt", symbol: "scissors", style: .primary)

    private var previewPlayer: AVAudioPlayer?
    private var previewTimer: Timer?
    private var isSaving = false
    private var initialStart: Double
    private var initialEnd: Double

    init(record: RecordingEntity) {
        self.record = record
        let url = StorageManager.shared.audioURL(for: record)
        self.audioURL = url
        let duration = record.duration
        let start = 0.0
        let end = max(0.5, min(duration, duration))
        self.initialStart = start
        self.initialEnd = end
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Create Excerpt"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        buildInterface()
        configureAudio()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopPreview()
    }

    deinit {
        previewTimer?.invalidate()
        previewPlayer?.stop()
    }

    // MARK: - 界面

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(SPInfoBanner(
            title: "The Original Recording Won't Change",
            message: "Saves the selected range as a new recording. The original audio, events, and analysis results stay as they are.",
            tone: .neutral,
            symbol: "scissors"
        ))
        contentStack.addArrangedSubview(makeRangeCard())
        contentStack.addArrangedSubview(makeSummaryCard())
        contentStack.addArrangedSubview(previewButton)
        contentStack.addArrangedSubview(saveButton)

        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func makeRangeCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)

        let titleRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Select a Range"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(UIView())
        let note = UILabel()
        note.text = "Minimum 0.5 seconds"
        note.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(note)
        stack.addArrangedSubview(titleRow)

        let waveformContainer = UIView()
        waveformContainer.translatesAutoresizingMaskIntoConstraints = false
        waveformContainer.heightAnchor.constraint(equalToConstant: 132).isActive = true
        waveform.cache = AudioAnalysisService.shared.waveform(for: record)
        waveform.duration = record.duration
        waveform.progress = 1
        waveform.showsPlayhead = false
        waveform.isUserInteractionEnabled = false
        waveform.tint = SPColor.secondaryInk
        waveform.playedTint = SPColor.secondaryInk
        waveformContainer.addSubview(waveform)
        waveform.pinEdges(to: waveformContainer, insets: UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0))

        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay.isUserInteractionEnabled = false
        waveformContainer.addSubview(selectionOverlay)
        selectionOverlay.pinEdges(to: waveform)
        selectionOverlay.startFraction = 0
        selectionOverlay.endFraction = 1
        stack.addArrangedSubview(waveformContainer)

        startSlider.onChange = { [weak self] value in
            guard let self else { return }
            self.stopPreview()
            var start = value
            let minLength: Double = 0.5
            if start > self.initialEnd - minLength {
                start = max(0, self.initialEnd - minLength)
                self.startSlider.value = start
            }
            self.initialStart = start
            self.updateRangeViews()
        }
        endSlider.onChange = { [weak self] value in
            guard let self else { return }
            self.stopPreview()
            var end = value
            let minLength: Double = 0.5
            if end < self.initialStart + minLength {
                end = min(self.record.duration, self.initialStart + minLength)
                self.endSlider.value = end
            }
            self.initialEnd = end
            self.updateRangeViews()
        }
        stack.addArrangedSubview(startSlider)
        stack.addArrangedSubview(endSlider)

        card.addContent(stack, insets: UIEdgeInsets(top: 15, left: 16, bottom: 16, right: 16))
        updateRangeViews()
        return card
    }

    private func makeSummaryCard() -> UIView {
        let card = SPCardView(style: .sunken)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        let row = UIStackView(axis: .horizontal, spacing: 8, distribution: .fillEqually)
        row.addArrangedSubview(metric(title: "Start", value: startValue))
        row.addArrangedSubview(metric(title: "End", value: endValue))
        row.addArrangedSubview(metric(title: "Length", value: lengthValue))
        stack.addArrangedSubview(row)
        card.addContent(stack, insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        return card
    }

    private func metric(title: String, value: UILabel) -> UIView {
        value.font = SPFont.mono(16, weight: .medium, relativeTo: .subheadline)
        value.textColor = SPColor.ink
        value.textAlignment = .center
        value.adjustsFontForContentSizeCategory = true
        let label = UILabel()
        label.text = title
        label.font = SPFont.text(9.5, weight: .medium, relativeTo: .caption2)
        label.textColor = SPColor.tertiaryInk
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(axis: .vertical, spacing: 3, alignment: .center)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(value)
        return stack
    }

    private func updateRangeViews() {
        let start = min(initialStart, initialEnd)
        let end = max(initialStart, initialEnd)
        startValue.text = SPFormat.duration(start)
        endValue.text = SPFormat.duration(end)
        lengthValue.text = SPFormat.duration(max(0, end - start))
        selectionOverlay.startFraction = record.duration > 0 ? CGFloat(start / record.duration) : 0
        selectionOverlay.endFraction = record.duration > 0 ? CGFloat(end / record.duration) : 1
        selectionOverlay.playheadFraction = nil
        previewButton.title = "Play Selection"
        previewButton.setSymbol("play.fill")
        updateAccessibilitySummary()
    }

    private func updateAccessibilitySummary() {
        let start = min(initialStart, initialEnd)
        let end = max(initialStart, initialEnd)
        selectionOverlay.accessibilityLabel = "Excerpt range"
        selectionOverlay.accessibilityValue = "\(SPFormat.accessibleDuration(start)) to \(SPFormat.accessibleDuration(end)), length \(SPFormat.accessibleDuration(max(0, end - start)))"
    }

    // MARK: - 预览

    private func configureAudio() {
        guard let audioURL, FileManager.default.fileExists(atPath: audioURL.path) else {
            previewButton.isEnabled = false
            saveButton.isEnabled = false
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            previewPlayer = player
        } catch {
            previewButton.isEnabled = false
            saveButton.isEnabled = false
        }
    }

    @objc private func previewTapped() {
        guard let player = previewPlayer else { return }
        if player.isPlaying {
            stopPreview()
            return
        }
        let start = min(initialStart, initialEnd)
        let end = max(initialStart, initialEnd)
        guard end - start >= 0.5 else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            presentAlert(title: "Can't Play", message: "Couldn't start the audio session.")
            return
        }
        player.currentTime = start
        player.play()
        previewButton.title = "Stop Preview"
        previewButton.setSymbol("stop.fill")
        selectionOverlay.playheadFraction = record.duration > 0 ? CGFloat(start / record.duration) : 0
        startPreviewTimer(start: start, end: end)
    }

    private func startPreviewTimer(start: Double, end: Double) {
        previewTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let player = self.previewPlayer else { return }
            if player.currentTime >= end || !player.isPlaying {
                self.stopPreview()
                return
            }
            self.selectionOverlay.playheadFraction = self.record.duration > 0
                ? CGFloat(player.currentTime / self.record.duration)
                : nil
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewPlayer?.stop()
        previewPlayer?.currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        previewButton.title = "Play Selection"
        previewButton.setSymbol("play.fill")
        selectionOverlay.playheadFraction = nil
    }

    // MARK: - 保存

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        guard !isSaving, let audioURL else { return }
        let start = min(initialStart, initialEnd)
        let end = max(initialStart, initialEnd)
        guard end - start >= 0.5 else {
            presentAlert(title: "Range Too Short", message: "Select a range of at least 0.5 seconds.")
            return
        }
        stopPreview()
        isSaving = true
        saveButton.isEnabled = false
        let overlay = SPLoadingOverlay(message: "Creating excerpt…")
        overlay.show(in: view)

        let asset = AVURLAsset(url: audioURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            overlay.hide()
            isSaving = false
            saveButton.isEnabled = true
            presentAlert(title: "Can't Create Excerpt", message: "This recording format doesn't support excerpt export.")
            return
        }
        let tempURL = storage.newTemporaryRecordingURL()
        exporter.outputURL = tempURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        exporter.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                overlay.hide()
                guard let self else { return }
                self.isSaving = false
                self.saveButton.isEnabled = true
                guard exporter.status == .completed else {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.presentAlert(
                        title: "Couldn't Create Excerpt",
                        message: exporter.error?.localizedDescription ?? "The export couldn't be completed."
                    )
                    return
                }
                self.finishSave(tempURL: tempURL, start: start, end: end)
            }
        }
    }

    private func finishSave(tempURL: URL, start: Double, end: Double) {
        let file = try? AVAudioFile(forReading: tempURL)
        let sampleRate = file?.processingFormat.sampleRate ?? record.sampleRate
        let channels = file.map { Int($0.processingFormat.channelCount) } ?? Int(record.channelCount)
        let duration = file.map { Double($0.length) / max(1, $0.processingFormat.sampleRate) } ?? (end - start)

        let markers = record.sortedEvents.compactMap { event -> RecordingMarker? in
            guard event.startTime < end else { return nil }
            let eventEnd = event.endTimeValue ?? event.startTime
            guard eventEnd > start || event.startTime >= start else { return nil }
            let clippedStart = max(event.startTime, start) - start
            return RecordingMarker(
                id: UUID(),
                time: min(max(0, clippedStart), duration),
                kind: event.kind,
                title: event.title
            )
        }

        let rangeLabel = "\(SPFormat.duration(start))–\(SPFormat.duration(end))"
        var noteParts: [String] = ["Excerpt of \(rangeLabel) from “\(record.title)”."]
        if let originalNote = record.note, !originalNote.isEmpty {
            noteParts.append(originalNote)
        }
        let draft = RecordingSaveDraft(
            title: "\(record.title) (Excerpt)",
            temporaryAudioURL: tempURL,
            placeID: record.place?.id,
            tags: TagCodec.cleanedTags(record.tags + ["Excerpt"]),
            note: noteParts.joined(separator: "\n"),
            weather: record.weather,
            coordinate: record.coordinate,
            precision: record.coordinate == nil ? .none : .precise,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channels,
            deviceModel: record.deviceModel ?? DeviceInfo.displayName,
            markers: markers,
            createdAt: Date()
        )
        do {
            let newRecord = try library.saveRecording(draft)
            SPHaptic.success()
            dismiss(animated: true) { [onSaved] in
                onSaved?(newRecord)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            presentError(error, title: "Couldn't Save Excerpt")
        }
    }
}

// MARK: - 选区叠加

private final class SPScopeSelectionOverlay: UIView {
    var startFraction: CGFloat = 0 { didSet { setNeedsDisplay() } }
    var endFraction: CGFloat = 1 { didSet { setNeedsDisplay() } }
    var playheadFraction: CGFloat? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = "Excerpt range"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard rect.width > 4 else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let startX = rect.width * min(1, max(0, startFraction))
        let endX = rect.width * min(1, max(0, endFraction))
        let left = min(startX, endX)
        let right = max(startX, endX)

        context.setFillColor(SPColor.paper.withAlphaComponent(0.55).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: left, height: rect.height))
        context.fill(CGRect(x: right, y: 0, width: rect.width - right, height: rect.height))

        context.setStrokeColor(SPColor.accent.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: left, y: 0))
        context.addLine(to: CGPoint(x: left, y: rect.height))
        context.move(to: CGPoint(x: right, y: 0))
        context.addLine(to: CGPoint(x: right, y: rect.height))
        context.strokePath()

        for x in [left, right] {
            let handle = CGRect(x: x - 4, y: rect.midY - 15, width: 8, height: 30)
            let path = UIBezierPath(roundedRect: handle, cornerRadius: 4)
            SPColor.accent.setFill()
            path.fill()
        }

        if let playheadFraction {
            let x = rect.width * min(1, max(0, playheadFraction))
            context.setStrokeColor(SPColor.ink.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: rect.height))
            context.strokePath()
        }
    }
}
