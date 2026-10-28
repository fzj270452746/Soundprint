//
//  CompareWorkspaceViewController.swift
//  Soundprint
//
//  双录音比较工作区：同步播放、波形、临时标记、特征与采集条件。
//

import UIKit

final class CompareWorkspaceViewController: SPViewController {
    private var recordingAID: UUID
    private var recordingBID: UUID
    private let library = LibraryService.shared
    private let analysisService = AudioAnalysisService.shared
    private let storage = StorageManager.shared
    private let selection = CompareSelectionStore.shared
    private let playback = ComparisonPlaybackService()

    private var recordA: RecordingEntity?
    private var recordB: RecordingEntity?
    private var summaryA: AudioAnalysisSummary?
    private var summaryB: AudioAnalysisSummary?
    private var markersA: [TemporaryMarker] = []
    private var markersB: [TemporaryMarker] = []
    private var waveformA: SPWaveformView?
    private var waveformB: SPWaveformView?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 18)
    private let playerBar = UIView()
    private let playButton = SPPlayButton(size: 48)
    private let slider = UISlider()
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private var modeChips: [SPFilterChip] = []
    private var normalizationToggle: SPToggleRow?
    private var isSeeking = false
    private var didLoadAudio = false
    private var reloadWorkItem: DispatchWorkItem?
    private var normalizationEnabled = false
    private var waveformNormalized = true
    private var playbackMode: ComparisonPlaybackService.Mode = .both

    private enum CommonRangePreset: Int {
        case full
        case tenSeconds
        case thirtySeconds

        var title: String {
            switch self {
            case .full: return "Full Common Range"
            case .tenSeconds: return "10 sec"
            case .thirtySeconds: return "30 sec"
            }
        }

        var seconds: Double? {
            switch self {
            case .full: return nil
            case .tenSeconds: return 10
            case .thirtySeconds: return 30
            }
        }
    }

    private var rangePreset: CommonRangePreset = .full
    private var rangeStart: Double = 0
    private var overlayWaveform: SPOverlayWaveformView?
    private var spectrogramAView: SPSpectrogramView?
    private var spectrogramBView: SPSpectrogramView?
    private var diffView: SPDiffSpectrogramView?
    private var diffData: SpectrogramDiffData?
    private var rangeSummaryLabel: UILabel?
    private var rangeChips: [SPFilterChip] = []
    private var rangeSlider: SPTimeSliderView?
    private var diffSummaryLabel: UILabel?

    init(recordingAID: UUID, recordingBID: UUID) {
        self.recordingAID = recordingAID
        self.recordingBID = recordingBID
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compare"
        buildPlayerBar()
        buildScroll()
        bindPlayback()
        observe()
        load(resetPlayback: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Play / Pause",
                image: UIImage(systemName: "playpause"),
                action: #selector(keyboardTogglePlayback),
                input: " ",
                modifierFlags: [],
                propertyList: nil
            ),
            UIKeyCommand(
                title: "Back 5 Seconds",
                image: UIImage(systemName: "gobackward.5"),
                action: #selector(keyboardBackward),
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                propertyList: nil
            ),
            UIKeyCommand(
                title: "Forward 5 Seconds",
                image: UIImage(systemName: "goforward.5"),
                action: #selector(keyboardForward),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                propertyList: nil
            ),
            UIKeyCommand(
                title: "Play A + B",
                image: nil,
                action: #selector(keyboardModeBoth),
                input: "0",
                modifierFlags: [],
                propertyList: nil
            ),
            UIKeyCommand(
                title: "Play A Only",
                image: nil,
                action: #selector(keyboardModeA),
                input: "1",
                modifierFlags: [],
                propertyList: nil
            ),
            UIKeyCommand(
                title: "Play B Only",
                image: nil,
                action: #selector(keyboardModeB),
                input: "2",
                modifierFlags: [],
                propertyList: nil
            )
        ]
    }

    @objc private func keyboardTogglePlayback() {
        playTapped()
    }

    @objc private func keyboardModeBoth() { setMode(.both) }
    @objc private func keyboardModeA() { setMode(.aOnly) }
    @objc private func keyboardModeB() { setMode(.bOnly) }

    private func setMode(_ mode: ComparisonPlaybackService.Mode) {
        playbackMode = mode
        playback.mode = mode
        let selectedIndex: Int
        switch mode {
        case .both: selectedIndex = 0
        case .aOnly: selectedIndex = 1
        case .bOnly: selectedIndex = 2
        }
        for (index, chip) in modeChips.enumerated() {
            chip.selectedState = index == selectedIndex
        }
        let message: String
        switch mode {
        case .both: message = "Playing A and B together"
        case .aOnly: message = "Playing A only"
        case .bOnly: message = "Playing B only"
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func keyboardBackward() {
        guard let range = playback.playRange else { playback.seek(to: playback.currentTime - 5); return }
        playback.seek(to: max(range.lowerBound, playback.currentTime - 5))
    }

    @objc private func keyboardForward() {
        guard let range = playback.playRange else { playback.seek(to: playback.currentTime + 5); return }
        playback.seek(to: min(range.upperBound, playback.currentTime + 5))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            playback.pause()
            selection.recordingAID = recordingAID
            selection.recordingBID = recordingBID
        }
    }

    // MARK: - 基础界面

    private func buildScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: playerBar.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -26),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func buildPlayerBar() {
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        playerBar.backgroundColor = SPColor.surface
        let border = UIView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.backgroundColor = SPColor.hairline
        playerBar.addSubview(border)
        view.addSubview(playerBar)

        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playerBar.addSubview(playButton)
        playButton.isEnabled = false

        currentLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        currentLabel.textColor = SPColor.secondaryInk
        currentLabel.text = "0:00"
        currentLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        durationLabel.textColor = SPColor.tertiaryInk
        durationLabel.text = "0:00"
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let timeRow = UIStackView(axis: .horizontal, spacing: 8)
        timeRow.addArrangedSubview(currentLabel)
        timeRow.addArrangedSubview(UIView())
        timeRow.addArrangedSubview(durationLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = SPColor.accent
        slider.maximumTrackTintColor = SPColor.hairline
        slider.setThumbImage(SPImage.sliderThumb(), for: .normal)
        slider.setThumbImage(SPImage.sliderThumb(diameter: 20), for: .highlighted)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.accessibilityLabel = "Comparison playback position"
        slider.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let stack = UIStackView(axis: .vertical, spacing: 1)
        stack.addArrangedSubview(timeRow)
        stack.addArrangedSubview(slider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        playerBar.addSubview(stack)

        NSLayoutConstraint.activate([
            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerBar.topAnchor.constraint(equalTo: playButton.topAnchor, constant: -13),
            border.leadingAnchor.constraint(equalTo: playerBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: playerBar.trailingAnchor),
            border.topAnchor.constraint(equalTo: playerBar.topAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
            playButton.leadingAnchor.constraint(equalTo: playerBar.leadingAnchor, constant: SPMetric.screenInset),
            playButton.topAnchor.constraint(equalTo: playerBar.topAnchor, constant: 13),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -11),
            stack.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: playerBar.trailingAnchor, constant: -SPMetric.screenInset),
            stack.centerYAnchor.constraint(equalTo: playButton.centerYAnchor)
        ])
    }

    private func bindPlayback() {
        playback.onUpdate = { [weak self] current, duration, isPlaying in
            guard let self else { return }
            self.currentLabel.text = SPFormat.duration(current)
            self.durationLabel.text = SPFormat.duration(duration)
            self.playButton.isPlaying = isPlaying
            if duration > 0 {
                let lower = self.playback.playRange?.lowerBound ?? 0
                let upper = self.playback.playRange?.upperBound ?? duration
                self.slider.minimumValue = Float(lower)
                self.slider.maximumValue = Float(max(lower + 0.01, upper))
                if !self.isSeeking {
                    self.slider.value = Float(min(upper, max(lower, current)))
                }
                self.waveformA?.progress = self.recordA.map { CGFloat(min(1, current / max(0.01, $0.duration))) } ?? 0
                self.waveformB?.progress = self.recordB.map { CGFloat(min(1, current / max(0.01, $0.duration))) } ?? 0
                self.overlayWaveform?.currentTime = current
                self.durationLabel.text = SPFormat.duration(upper)
                self.slider.accessibilityValue = "\(SPFormat.accessibleDuration(current)) / \(SPFormat.accessibleDuration(upper))"
            }
        }
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.analysisDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.libraryDidChange,
            object: nil
        )
    }

    @objc private func dataChanged() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.load(resetPlayback: false) }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    // MARK: - 加载

    private func load(resetPlayback: Bool) {
        guard let a = library.fetchRecording(id: recordingAID),
              let b = library.fetchRecording(id: recordingBID) else {
            navigationController?.popViewController(animated: true)
            return
        }
        recordA = a
        recordB = b
        summaryA = analysisService.analysis(for: a)
        summaryB = analysisService.analysis(for: b)
        configureMenu()

        if resetPlayback || !didLoadAudio {
            loadAudio(a: a, b: b)
        } else {
            applyPlaybackOptions()
        }
        rebuildContent(preserveScroll: !resetPlayback)
    }

    private func loadAudio(a: RecordingEntity, b: RecordingEntity) {
        guard let urlA = storage.audioURL(for: a),
              let urlB = storage.audioURL(for: b),
              FileManager.default.fileExists(atPath: urlA.path),
              FileManager.default.fileExists(atPath: urlB.path) else {
            didLoadAudio = false
            playButton.isEnabled = false
            slider.isEnabled = false
            return
        }
        if playback.load(aURL: urlA, bURL: urlB) {
            didLoadAudio = true
            playButton.isEnabled = true
            slider.isEnabled = true
            currentLabel.text = "0:00"
            durationLabel.text = SPFormat.duration(playback.maxDuration)
            slider.maximumValue = Float(max(0.01, playback.maxDuration))
            playback.mode = playbackMode
            applyPlaybackOptions()
        } else {
            didLoadAudio = false
            playButton.isEnabled = false
            slider.isEnabled = false
        }
    }

    private func configureMenu() {
        let changeA = UIAction(title: "Change Recording A", image: UIImage(systemName: "a.circle")) { [weak self] _ in
            self?.changeSlot(.a)
        }
        let changeB = UIAction(title: "Change Recording B", image: UIImage(systemName: "b.circle")) { [weak self] _ in
            self?.changeSlot(.b)
        }
        let swap = UIAction(title: "Swap A and B", image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
            self?.swapSlots()
        }
        let share = UIAction(title: "Share Comparison Notes", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.shareReport()
        }
        let pdf = UIAction(title: "Export PDF Report", image: UIImage(systemName: "doc.richtext")) { [weak self] _ in
            self?.exportPDFReport()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [changeA, changeB, swap, pdf, share])
        )
    }

    private func rebuildContent(preserveScroll: Bool) {
        let offset = preserveScroll ? scrollView.contentOffset : .zero
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        waveformA = nil
        waveformB = nil
        guard let a = recordA, let b = recordB else { return }

        contentStack.addArrangedSubview(makeHeader(a: a, b: b))
        contentStack.addArrangedSubview(makeConditionBanner(a: a, b: b))
        clampRangeStart()
        contentStack.addArrangedSubview(makeRangeCard(a: a, b: b))
        contentStack.addArrangedSubview(makeOverlayCard(a: a, b: b))
        contentStack.addArrangedSubview(makeTrackCard(
            letter: "A",
            color: SPColor.accent,
            record: a,
            markers: markersA,
            slot: .a
        ))
        contentStack.addArrangedSubview(makeTrackCard(
            letter: "B",
            color: SPColor.moss,
            record: b,
            markers: markersB,
            slot: .b
        ))
        contentStack.addArrangedSubview(makeSpectrogramCompareCard(a: a, b: b))
        contentStack.addArrangedSubview(makePlaybackOptionsCard())
        contentStack.addArrangedSubview(makeStatsSection(a: a, b: b))
        contentStack.addArrangedSubview(makeConditionsCard(a: a, b: b))
        contentStack.addArrangedSubview(makeReportButton())
        contentStack.addArrangedSubview(SPInfoBanner(
            title: "Comparison Caveats",
            message: "RMS · peak · band values are recording signal values. If the device, distance, or gain differs, not every difference can be interpreted as an environmental change.",
            tone: .neutral,
            symbol: "info.circle"
        ))

        applyPlaybackRange()
        updateSpectrogramWindows(a: a, b: b)
        if preserveScroll {
            view.layoutIfNeeded()
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(offset.y, maxOffset)), animated: false)
        }
    }

    private func makeHeader(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: 8)
        let kicker = UILabel()
        kicker.attributedText = NSAttributedString(
            string: "A / B Comparison",
            attributes: [
                .font: SPFont.text(10.5, weight: .semibold, relativeTo: .caption2),
                .foregroundColor: SPColor.accent,
                .kern: 1.3
            ]
        )
        let title = UILabel()
        let samePlace = a.place?.id != nil && a.place?.id == b.place?.id
        title.text = samePlace ? "\(a.place?.name ?? "") Changes" : "Compare Two Recordings"
        title.font = SPFont.display(28, relativeTo: .title1)
        title.textColor = SPColor.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true

        let dates = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        dates.addArrangedSubview(makeLegend(letter: "A", date: SPFormat.shortDate.string(from: a.createdAt), color: SPColor.accent))
        dates.addArrangedSubview(makeLegend(letter: "B", date: SPFormat.shortDate.string(from: b.createdAt), color: SPColor.moss))
        dates.addArrangedSubview(UIView())

        stack.addArrangedSubview(kicker)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(10, after: title)
        stack.addArrangedSubview(dates)
        return stack
    }

    private func makeLegend(letter: String, date: String, color: UIColor) -> UIView {
        let badge = UILabel()
        badge.text = letter
        badge.font = SPFont.mono(9, weight: .bold, relativeTo: .caption2)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = color
        badge.layer.cornerRadius = 8
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 16).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let label = UILabel()
        label.text = date
        label.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
        label.textColor = SPColor.secondaryInk
        let stack = UIStackView(axis: .horizontal, spacing: 5, alignment: .center)
        stack.addArrangedSubview(badge)
        stack.addArrangedSubview(label)
        return stack
    }

    private func makeConditionBanner(a: RecordingEntity, b: RecordingEntity) -> UIView {
        var warnings: [String] = []
        if a.place?.id != b.place?.id {
            warnings.append("The places are different")
        }
        if let da = a.deviceModel, let db = b.deviceModel, da != db {
            warnings.append("The recording devices are different")
        }
        if abs(a.sampleRate - b.sampleRate) > 1 {
            warnings.append("The sample rates are different")
        }
        if warnings.isEmpty {
            return SPInfoBanner(
                title: "Recording Conditions Are Similar",
                message: "Even so, volume differences include the effects of automatic device gain and distance.",
                tone: .success
            )
        }
        return SPInfoBanner(
            title: "Recording Conditions Differ",
            message: warnings.joined(separator: ". ") + ". Do not attribute volume or frequency differences to the environment alone.",
            tone: .warning
        )
    }

    // MARK: - Common Range / Overlaid Waveform / Spectral Difference

    private var commonDuration: Double {
        guard let a = recordA, let b = recordB else { return 0 }
        return max(0, min(a.duration, b.duration))
    }

    private var selectedRangeLength: Double {
        let common = commonDuration
        guard let preset = rangePreset.seconds else { return common }
        return min(common, preset)
    }

    private var selectedRange: ClosedRange<Double>? {
        let length = selectedRangeLength
        guard length > 0.1 else { return nil }
        let maxStart = max(0, commonDuration - length)
        let start = min(max(0, rangeStart), maxStart)
        return start...(start + length)
    }

    private func clampRangeStart() {
        if let seconds = rangePreset.seconds, seconds >= commonDuration {
            rangePreset = .full
        }
        let maxStart = max(0, commonDuration - selectedRangeLength)
        rangeStart = min(max(0, rangeStart), maxStart)
    }

    private func makeRangeCard(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let titleRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Common Range"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(UIView())
        let lengthLabel = UILabel()
        lengthLabel.font = SPFont.mono(10, weight: .medium, relativeTo: .caption2)
        lengthLabel.textColor = SPColor.accent
        lengthLabel.text = "Overlap length \(SPFormat.duration(commonDuration))"
        lengthLabel.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(lengthLabel)
        stack.addArrangedSubview(titleRow)

        let explanation = UILabel()
        explanation.text = "Playback and comparison cover only the range where A and B overlap. Feature values apply to the entire recording."
        explanation.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption1)
        explanation.textColor = SPColor.tertiaryInk
        explanation.numberOfLines = 0
        explanation.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(explanation)

        let chips = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
        rangeChips = []
        var availablePresets: [CommonRangePreset] = [.full]
        if commonDuration >= 10.5 { availablePresets.append(.tenSeconds) }
        if commonDuration >= 30.5 { availablePresets.append(.thirtySeconds) }
        if !availablePresets.contains(rangePreset) { rangePreset = .full }
        for preset in availablePresets {
            let chip = SPFilterChip(title: preset.title)
            chip.tag = preset.rawValue
            chip.selectedState = preset == rangePreset
            chip.addTarget(self, action: #selector(rangeChipTapped(_:)), for: .touchUpInside)
            rangeChips.append(chip)
            chips.addArrangedSubview(chip)
        }
        chips.addArrangedSubview(UIView())
        stack.addArrangedSubview(chips)

        let summary = UILabel()
        summary.font = SPFont.mono(11, weight: .medium, relativeTo: .caption1)
        summary.textColor = SPColor.secondaryInk
        summary.numberOfLines = 0
        summary.adjustsFontForContentSizeCategory = true
        rangeSummaryLabel = summary
        stack.addArrangedSubview(summary)

        let maxStart = max(0, commonDuration - selectedRangeLength)
        if maxStart > 0.15, let range = selectedRange {
            let slider = SPTimeSliderView(
                title: "Common range start",
                value: range.lowerBound,
                duration: max(0.1, maxStart)
            )
            slider.onChange = { [weak self] value in
                guard let self else { return }
                self.rangeStart = min(max(0, value), maxStart)
                self.updateRangeDependentViews()
            }
            rangeSlider = slider
            stack.addArrangedSubview(slider)
        } else {
            rangeSlider = nil
        }

        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15))
        updateRangeSummary()
        return card
    }

    private func updateRangeSummary() {
        guard let range = selectedRange else {
            rangeSummaryLabel?.text = "No common range is available to compare"
            return
        }
        rangeSummaryLabel?.text = "\(SPFormat.duration(range.lowerBound))–\(SPFormat.duration(range.upperBound)) · Length \(SPFormat.duration(range.upperBound - range.lowerBound))"
    }

    @objc private func rangeChipTapped(_ sender: SPFilterChip) {
        guard let preset = CommonRangePreset(rawValue: sender.tag) else { return }
        rangePreset = preset
        rangeStart = 0
        SPHaptic.selection()
        rebuildContent(preserveScroll: true)
        UIAccessibility.post(notification: .announcement, argument: "Changed comparison range to \(preset.title)")
    }

    private func updateRangeDependentViews() {
        guard let range = selectedRange else { return }
        updateRangeSummary()
        overlayWaveform?.rangeStart = range.lowerBound
        overlayWaveform?.rangeLength = range.upperBound - range.lowerBound
        overlayWaveform?.currentTime = min(range.upperBound, max(range.lowerBound, playback.currentTime))
        applyPlaybackRange()
        updateSpectrogramWindows(a: recordA, b: recordB)
    }

    private func applyPlaybackRange() {
        guard didLoadAudio, let range = selectedRange else {
            playback.setPlayRange(nil)
            return
        }
        playback.setPlayRange(range)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(max(range.lowerBound + 0.01, range.upperBound))
        if !isSeeking {
            slider.value = Float(min(range.upperBound, max(range.lowerBound, playback.currentTime)))
        }
        durationLabel.text = SPFormat.duration(range.upperBound)
    }

    private func makeOverlayCard(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        let titleRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Compare Overlaid Waveforms"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(UIView())
        titleRow.addArrangedSubview(makeOverlayLegend())
        stack.addArrangedSubview(titleRow)

        guard let cacheA = analysisService.waveform(for: a),
              let cacheB = analysisService.waveform(for: b),
              let range = selectedRange else {
            let empty = UILabel()
            empty.text = "Preparing waveform."
            empty.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
            empty.textColor = SPColor.tertiaryInk
            stack.addArrangedSubview(empty)
            card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15))
            return card
        }

        let overlay = SPOverlayWaveformView()
        overlay.cacheA = cacheA
        overlay.cacheB = cacheB
        overlay.durationA = a.duration
        overlay.durationB = b.duration
        overlay.rangeStart = range.lowerBound
        overlay.rangeLength = range.upperBound - range.lowerBound
        overlay.normalizeToPeak = waveformNormalized
        overlay.currentTime = playback.currentTime
        overlay.onSeek = { [weak self] time in self?.seekBoth(to: time) }
        overlay.heightAnchor.constraint(equalToConstant: 126).isActive = true
        stack.addArrangedSubview(overlay)
        overlayWaveform = overlay

        let footer = UILabel()
        footer.text = "A points up, B points down. Both are shown on the same time axis for the common range."
        footer.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
        footer.textColor = SPColor.tertiaryInk
        footer.numberOfLines = 0
        footer.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(footer)

        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 13, right: 15))
        return card
    }

    private func makeOverlayLegend() -> UIView {
        let row = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        for (letter, color) in [("A", SPColor.accent), ("B", SPColor.moss)] {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = color
            dot.layer.cornerRadius = 2.5
            dot.widthAnchor.constraint(equalToConstant: 5).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 5).isActive = true
            let label = UILabel()
            label.text = letter
            label.font = SPFont.mono(9.5, weight: .semibold, relativeTo: .caption2)
            label.textColor = color
            let item = UIStackView(axis: .horizontal, spacing: 4, alignment: .center)
            item.addArrangedSubview(dot)
            item.addArrangedSubview(label)
            row.addArrangedSubview(item)
        }
        return row
    }

    private func makeSpectrogramCompareCard(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 10)
        let header = SPSectionHeaderView(title: "Spectrum Comparison", subtitle: "Common range shown on the same frequency axis")
        section.addArrangedSubview(header)

        guard let cacheA = analysisService.spectrogram(for: a),
              let cacheB = analysisService.spectrogram(for: b) else {
            section.addArrangedSubview(SPInfoBanner(
                title: "Pending Analysis",
                message: "Once both recordings are analyzed, you can review the side-by-side spectra and their difference.",
                tone: .neutral
            ))
            return section
        }

        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        let sideBySide = UIStackView(axis: .horizontal, spacing: 8, distribution: .fillEqually)
        sideBySide.addArrangedSubview(makeSpectrogramColumn(letter: "A", color: SPColor.accent, cache: cacheA, isA: true))
        sideBySide.addArrangedSubview(makeSpectrogramColumn(letter: "B", color: SPColor.moss, cache: cacheB, isA: false))
        stack.addArrangedSubview(sideBySide)

        let diffTitle = UILabel()
        diffTitle.text = "Spectral Difference (Selected Range)"
        diffTitle.font = SPFont.text(11, weight: .semibold, relativeTo: .caption1)
        diffTitle.textColor = SPColor.secondaryInk
        diffTitle.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(diffTitle)

        let diff = SPDiffSpectrogramView()
        diff.heightAnchor.constraint(equalToConstant: 112).isActive = true
        diffData = makeDiffData(a: a, b: b)
        diff.data = diffData
        stack.addArrangedSubview(diff)
        diffView = diff

        let legend = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        legend.addArrangedSubview(makeColorLegend(title: "Stronger A", color: SPColor.accent))
        legend.addArrangedSubview(makeColorLegend(title: "Stronger B", color: SPColor.moss))
        legend.addArrangedSubview(makeColorLegend(title: "Small Difference", color: SPColor.hairline))
        legend.addArrangedSubview(UIView())
        stack.addArrangedSubview(legend)

        let summary = UILabel()
        summary.text = diffData?.summary
        summary.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        summary.textColor = SPColor.tertiaryInk
        summary.numberOfLines = 0
        summary.adjustsFontForContentSizeCategory = true
        summary.isHidden = diffData == nil
        diffSummaryLabel = summary
        stack.addArrangedSubview(summary)

        let note = UILabel()
        note.text = "Difference between simplified spectra normalized to each recording's peak. It includes differences in recording gain and equipment, and does not indicate a difference in sound pressure level."
        note.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(note)

        card.addContent(stack, insets: UIEdgeInsets(top: 13, left: 13, bottom: 13, right: 13))
        section.addArrangedSubview(card)
        updateSpectrogramWindows(a: a, b: b)
        return section
    }

    private func makeSpectrogramColumn(letter: String, color: UIColor, cache: SpectrogramCache, isA: Bool) -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: 4)
        let label = UILabel()
        label.text = "\(letter)  0–\(Int(cache.maxFrequency / 1000)) kHz"
        label.font = SPFont.mono(9, weight: .medium, relativeTo: .caption2)
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        let view = SPSpectrogramView()
        view.cache = cache
        view.heightAnchor.constraint(equalToConstant: 92).isActive = true
        if isA { spectrogramAView = view } else { spectrogramBView = view }
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(view)
        return stack
    }

    private func makeColorLegend(title: String, color: UIColor) -> UIView {
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = color
        dot.layer.cornerRadius = 2.5
        dot.widthAnchor.constraint(equalToConstant: 5).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 5).isActive = true
        let label = UILabel()
        label.text = title
        label.font = SPFont.text(9, weight: .regular, relativeTo: .caption2)
        label.textColor = SPColor.tertiaryInk
        let row = UIStackView(axis: .horizontal, spacing: 4, alignment: .center)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(label)
        return row
    }

    private func updateSpectrogramWindows(a: RecordingEntity?, b: RecordingEntity?) {
        guard let a, let b, let range = selectedRange else { return }
        if let view = spectrogramAView {
            view.visibleStartFraction = a.duration > 0 ? CGFloat(range.lowerBound / a.duration) : 0
            view.visibleEndFraction = a.duration > 0 ? CGFloat(range.upperBound / a.duration) : 1
        }
        if let view = spectrogramBView {
            view.visibleStartFraction = b.duration > 0 ? CGFloat(range.lowerBound / b.duration) : 0
            view.visibleEndFraction = b.duration > 0 ? CGFloat(range.upperBound / b.duration) : 1
        }
        let newData = makeDiffData(a: a, b: b)
        diffData = newData
        diffView?.data = newData
        diffSummaryLabel?.text = newData?.summary
        diffSummaryLabel?.isHidden = newData == nil
    }

    private func makeDiffData(a: RecordingEntity, b: RecordingEntity) -> SpectrogramDiffData? {
        guard let cacheA = analysisService.spectrogram(for: a),
              let cacheB = analysisService.spectrogram(for: b),
              let range = selectedRange,
              cacheA.columns > 0, cacheB.columns > 0 else { return nil }

        let columns = 72
        let bands = min(48, min(cacheA.bands, cacheB.bands))
        guard bands > 0 else { return nil }
        var values = [Float](repeating: 0, count: columns * bands)
        var lowSum: Double = 0, midSum: Double = 0, highSum: Double = 0

        for column in 0..<columns {
            let time = range.lowerBound + (Double(column) + 0.5) / Double(columns) * (range.upperBound - range.lowerBound)
            let fractionA = a.duration > 0 ? max(0, min(1, time / a.duration)) : 0
            let fractionB = b.duration > 0 ? max(0, min(1, time / b.duration)) : 0
            let columnA = min(cacheA.columns - 1, Int(fractionA * Double(cacheA.columns)))
            let columnB = min(cacheB.columns - 1, Int(fractionB * Double(cacheB.columns)))
            for band in 0..<bands {
                let ratio = (Double(band) + 0.5) / Double(bands)
                let bandA = min(cacheA.bands - 1, Int(ratio * Double(cacheA.bands)))
                let bandB = min(cacheB.bands - 1, Int(ratio * Double(cacheB.bands)))
                let idxA = bandA * cacheA.columns + columnA
                let idxB = bandB * cacheB.columns + columnB
                guard idxA < cacheA.values.count, idxB < cacheB.values.count else { continue }
                let diff = cacheB.values[idxB] - cacheA.values[idxA]
                values[band * columns + column] = diff
                if band < bands / 3 {
                    lowSum += Double(diff)
                } else if band < (bands * 2) / 3 {
                    midSum += Double(diff)
                } else {
                    highSum += Double(diff)
                }
            }
        }

        let divisor = Double(max(1, columns * bands / 3))
        let low = lowSum / divisor
        let mid = midSum / divisor
        let high = highSum / divisor
        let candidates: [(String, Double)] = [("low band", low), ("mid band", mid), ("high band", high)]
        let strongest = candidates.max { abs($0.1) < abs($1.1) } ?? ("band", 0)
        let summary: String
        if abs(strongest.1) < 0.018 {
            summary = "No major difference is visible in the spectral balance of the selected range."
        } else if strongest.1 > 0 {
            summary = "The \(strongest.0) shows a relatively stronger B component."
        } else {
            summary = "The \(strongest.0) shows a relatively stronger A component."
        }

        return SpectrogramDiffData(
            columns: columns,
            bands: bands,
            values: values,
            summary: summary,
            startTime: range.lowerBound,
            endTime: range.upperBound
        )
    }

    private enum Slot { case a, b }

    private func makeTrackCard(
        letter: String,
        color: UIColor,
        record: RecordingEntity,
        markers: [TemporaryMarker],
        slot: Slot
    ) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 8)

        let badge = UILabel()
        badge.text = letter
        badge.font = SPFont.mono(11, weight: .bold, relativeTo: .caption1)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = color
        badge.layer.cornerRadius = 10
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 20).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let title = UILabel()
        title.text = record.title
        title.font = SPFont.text(14, weight: .semibold, relativeTo: .subheadline)
        title.textColor = SPColor.ink
        title.numberOfLines = 1
        title.adjustsFontForContentSizeCategory = true
        let meta = UILabel()
        meta.text = "\(record.place?.name ?? "Unassigned") · \(SPFormat.dateTime(record.createdAt)) · \(SPFormat.duration(record.duration))"
        meta.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
        meta.textColor = SPColor.tertiaryInk
        meta.numberOfLines = 1
        meta.adjustsFontForContentSizeCategory = true
        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(meta)
        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        header.addArrangedSubview(badge)
        header.addArrangedSubview(textStack)
        header.addArrangedSubview(UIView())
        let status = record.analysisState == .ready
            ? SPStatusBadge(text: "Analyzed", color: SPColor.moss)
            : SPStatusBadge(text: record.analysisState.title, color: SPColor.amber)
        header.addArrangedSubview(status)
        stack.addArrangedSubview(header)

        let wave = SPWaveformView()
        wave.cache = analysisService.waveform(for: record)
        wave.duration = record.duration
        wave.showsPlayhead = true
        wave.normalizeToPeak = waveformNormalized
        wave.tint = SPColor.secondaryInk
        wave.playedTint = color
        wave.progress = playback.maxDuration > 0
            ? CGFloat(min(1, playback.currentTime / max(0.01, record.duration)))
            : 0
        var displayMarkers = record.sortedEvents.map {
            WaveformMarkerDisplay(time: $0.startTime, color: $0.kind.color.withAlphaComponent(0.7), title: $0.title)
        }
        displayMarkers += markers.map {
            WaveformMarkerDisplay(time: $0.time, color: color, title: $0.title)
        }
        wave.markers = displayMarkers
        wave.onSeek = { [weak self] time in self?.seekBoth(to: time) }
        wave.accessibilityLabel = "\(letter) waveform"
        wave.accessibilityHint = "Tap or swipe to move the playback position within the common range"
        wave.heightAnchor.constraint(equalToConstant: 76).isActive = true
        wave.isUserInteractionEnabled = didLoadAudio
        stack.addArrangedSubview(wave)
        if slot == .a { waveformA = wave } else { waveformB = wave }

        let footer = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let addMarker = UIButton(type: .system)
        addMarker.setImage(UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)), for: .normal)
        addMarker.setTitle(" Add Marker Here", for: .normal)
        addMarker.titleLabel?.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        addMarker.tintColor = color
        addMarker.addTarget(self, action: #selector(addMarkerTapped(_:)), for: .touchUpInside)
        addMarker.tag = slot == .a ? 0 : 1
        footer.addArrangedSubview(addMarker)
        footer.addArrangedSubview(UIView())
        let markerCount = UILabel()
        markerCount.text = markers.isEmpty ? "No temporary markers" : "Temporary markers: \(markers.count)"
        markerCount.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
        markerCount.textColor = SPColor.tertiaryInk
        markerCount.adjustsFontForContentSizeCategory = true
        footer.addArrangedSubview(markerCount)
        stack.addArrangedSubview(footer)

        if !markers.isEmpty {
            let chipRow = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
            chipRow.addArrangedSubview(UIView())
            for marker in markers {
                let chip = SPTagView(
                    text: SPFormat.duration(marker.time),
                    symbol: "bookmark.fill",
                    color: color,
                    background: color.withAlphaComponent(0.11),
                    removable: true
                )
                let markerID = marker.id
                chip.onTap = { [weak self] in
                    guard let self else { return }
                    if slot == .a {
                        self.markersA.removeAll { $0.id == markerID }
                    } else {
                        self.markersB.removeAll { $0.id == markerID }
                    }
                    self.rebuildContent(preserveScroll: true)
                }
                chipRow.addArrangedSubview(chip)
            }
            chipRow.addArrangedSubview(UIView())
            stack.addArrangedSubview(chipRow)
        }

        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 12, right: 15))
        return card
    }

    private func makePlaybackOptionsCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)
        let title = UILabel()
        title.text = "Preview"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)

        let chips = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
        modeChips = []
        for (index, title) in ["A + B", "A only", "B only"].enumerated() {
            let chip = SPFilterChip(title: title)
            chip.tag = index
            let selectedMode: Int
            switch playbackMode {
            case .both: selectedMode = 0
            case .aOnly: selectedMode = 1
            case .bOnly: selectedMode = 2
            }
            chip.selectedState = index == selectedMode
            chip.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
            modeChips.append(chip)
            chips.addArrangedSubview(chip)
        }
        chips.addArrangedSubview(UIView())
        stack.addArrangedSubview(chips)

        let canNormalize = summaryA != nil && summaryB != nil
        let toggle = SPToggleRow(
            title: "Match Volume for Preview",
            subtitle: canNormalize
                ? "Adjusts playback volume only. Analysis values are unchanged."
                : "Available once both recordings are analyzed.",
            isOn: normalizationEnabled,
            symbol: "slider.horizontal.3"
        )
        toggle.toggle.isEnabled = canNormalize
        toggle.alpha = canNormalize ? 1 : 0.45
        toggle.onChange = { [weak self] isOn in
            self?.setNormalization(isOn)
        }
        normalizationToggle = toggle
        stack.addArrangedSubview(toggle)
        stack.addArrangedSubview(SPDivider())
        let waveformToggle = SPToggleRow(
            title: "Normalize Waveform Display",
            subtitle: "On: align height to peak / Off: show original amplitude.",
            isOn: waveformNormalized,
            symbol: "waveform"
        )
        waveformToggle.onChange = { [weak self] isOn in
            guard let self else { return }
            self.waveformNormalized = isOn
            self.waveformA?.normalizeToPeak = isOn
            self.waveformB?.normalizeToPeak = isOn
            self.overlayWaveform?.normalizeToPeak = isOn
            UIAccessibility.post(notification: .announcement, argument: isOn ? "Showing normalized waveforms" : "Showing waveforms at original amplitude")
        }
        stack.addArrangedSubview(waveformToggle)

        let note = UILabel()
        note.text = "Playback stops at the end of the selected common range. A and B may differ by a few milliseconds in start timing."
        note.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(note)

        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15))
        return card
    }

    private func makeStatsSection(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 10)
        let header = SPSectionHeaderView(title: "Feature Comparison", subtitle: "Recording signal values compared on the same basis")
        section.addArrangedSubview(header)

        guard let sa = summaryA, let sb = summaryB else {
            let card = SPCardView(style: .sunken)
            let stack = UIStackView(axis: .vertical, spacing: 6)
            let title = UILabel()
            title.text = "Preparing the value comparison"
            title.font = SPFont.text(13, weight: .semibold, relativeTo: .subheadline)
            title.textColor = SPColor.secondaryInk
            let body = UILabel()
            body.text = "Waveform comparison and playback are still available. When analysis finishes, RMS · peak · frequency band differences will appear."
            body.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
            body.textColor = SPColor.tertiaryInk
            body.numberOfLines = 0
            body.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(title)
            stack.addArrangedSubview(body)
            card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
            section.addArrangedSubview(card)
            return section
        }

        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        stack.addArrangedSubview(makeComparisonHeader())
        stack.addArrangedSubview(SPDivider())
        let delta = sb.rmsDBFS - sa.rmsDBFS
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Average RMS",
            a: "\(SPFormat.decibel(sa.rmsDBFS)) dBFS",
            b: "\(SPFormat.decibel(sb.rmsDBFS)) dBFS"
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Digital Peak",
            a: "\(SPFormat.decibel(sa.peakDBFS)) dBFS",
            b: "\(SPFormat.decibel(sb.peakDBFS)) dBFS"
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Low Band Ratio",
            a: SPFormat.percent(sa.bands.low),
            b: SPFormat.percent(sb.bands.low)
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Mid Band Ratio",
            a: SPFormat.percent(sa.bands.mid),
            b: SPFormat.percent(sb.bands.mid)
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "High Band Ratio",
            a: SPFormat.percent(sa.bands.high),
            b: SPFormat.percent(sb.bands.high)
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Duration",
            a: SPFormat.duration(a.duration),
            b: SPFormat.duration(b.duration)
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Sample Rate",
            a: "\(SPFormat.decimal(a.sampleRate / 1000)) kHz",
            b: "\(SPFormat.decimal(b.sampleRate / 1000)) kHz"
        ))

        let insight = UILabel()
        insight.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        insight.textColor = SPColor.secondaryInk
        insight.numberOfLines = 0
        insight.adjustsFontForContentSizeCategory = true
        if abs(delta) < 0.3 {
            insight.text = "Average RMS is nearly the same. The volume difference is small, but also check for differences in band balance."
        } else if delta > 0 {
            insight.text = String(format: "B's average RMS is %.1f dB higher than A. Because this includes differences in recording gain, it cannot be concluded that the ambient sound became louder.", abs(delta))
        } else {
            insight.text = String(format: "B's average RMS is %.1f dB lower than A. Because this includes differences in recording gain, it cannot be concluded that the ambient sound became quieter.", abs(delta))
        }
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(insight)
        card.addContent(stack, insets: UIEdgeInsets(top: 13, left: 15, bottom: 14, right: 15))
        section.addArrangedSubview(card)
        return section
    }

    private func makeComparisonHeader() -> UIView {
        let stack = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let label = UILabel()
        label.text = ""
        label.isHidden = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(UIView())
        let a = UILabel()
        a.text = "A"
        a.font = SPFont.mono(10, weight: .bold, relativeTo: .caption2)
        a.textColor = SPColor.accent
        a.textAlignment = .center
        a.widthAnchor.constraint(equalToConstant: 82).isActive = true
        let b = UILabel()
        b.text = "B"
        b.font = SPFont.mono(10, weight: .bold, relativeTo: .caption2)
        b.textColor = SPColor.moss
        b.textAlignment = .center
        b.widthAnchor.constraint(equalToConstant: 82).isActive = true
        stack.addArrangedSubview(a)
        stack.addArrangedSubview(b)
        return stack
    }

    private func makeConditionsCard(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let title = UILabel()
        title.text = "Recording Conditions"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(makeComparisonHeader())
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(title: "Date & Time", a: SPFormat.shortDate.string(from: a.createdAt), b: SPFormat.shortDate.string(from: b.createdAt)))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(title: "Place", a: a.place?.name ?? "Unassigned", b: b.place?.name ?? "Unassigned"))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(title: "Device", a: a.deviceModel ?? "—", b: b.deviceModel ?? "—"))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPComparisonValueRow(
            title: "Channels",
            a: a.channelCount == 1 ? "Mono" : "\(a.channelCount)ch",
            b: b.channelCount == 1 ? "Mono" : "\(b.channelCount)ch"
        ))
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15))
        return card
    }

    private func makeReportButton() -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: 9)
        let pdf = SPButton(title: "Export Comparison Report as PDF", symbol: "doc.richtext", style: .primary)
        pdf.addTarget(self, action: #selector(exportPDFReport), for: .touchUpInside)
        let text = SPButton(title: "Share Comparison Notes as Text", symbol: "text.alignleft", style: .secondary)
        text.addTarget(self, action: #selector(shareReport), for: .touchUpInside)
        stack.addArrangedSubview(pdf)
        stack.addArrangedSubview(text)
        return stack
    }

    // MARK: - 播放

    @objc private func playTapped() {
        guard didLoadAudio else { return }
        applyPlaybackOptions()
        playback.toggle()
        SPHaptic.light()
    }

    @objc private func sliderChanged() {
        guard didLoadAudio else { return }
        isSeeking = true
        playback.seek(to: Double(slider.value))
        currentLabel.text = SPFormat.duration(Double(slider.value))
        isSeeking = false
    }

    private func seekBoth(to time: Double) {
        guard didLoadAudio else { return }
        playback.seek(to: time)
    }

    @objc private func modeTapped(_ sender: SPFilterChip) {
        for chip in modeChips {
            chip.selectedState = chip == sender
        }
        switch sender.tag {
        case 1: setMode(.aOnly)
        case 2: setMode(.bOnly)
        default: setMode(.both)
        }
        SPHaptic.selection()
    }

    private func setNormalization(_ enabled: Bool) {
        normalizationEnabled = enabled
        playback.setNormalization(
            enabled: enabled,
            rmsA: summaryA?.rmsDBFS,
            rmsB: summaryB?.rmsDBFS
        )
        if enabled {
            SPToast.show("Matching playback volume", in: view, symbol: "slider.horizontal.3")
        }
    }

    private func applyPlaybackOptions() {
        playback.setNormalization(
            enabled: normalizationEnabled,
            rmsA: summaryA?.rmsDBFS,
            rmsB: summaryB?.rmsDBFS
        )
    }

    // MARK: - 标记与切换

    @objc private func addMarkerTapped(_ sender: UIButton) {
        let isA = sender.tag == 0
        guard let record = isA ? recordA : recordB else { return }
        let time = playback.currentTime
        guard time <= record.duration + 0.001 else {
            SPToast.show("Outside this recording's range", in: view, symbol: "exclamationmark.circle")
            return
        }
        let count = isA ? markersA.count + 1 : markersB.count + 1
        let marker = TemporaryMarker(id: UUID(), time: time, title: "Marker \(count)")
        if isA { markersA.append(marker) } else { markersB.append(marker) }
        SPHaptic.selection()
        rebuildContent(preserveScroll: true)
    }

    private func changeSlot(_ slot: Slot) {
        let selected = slot == .a ? recordingAID : recordingBID
        let excluded = slot == .a ? recordingBID : recordingAID
        let picker = RecordingPickerViewController(
            slotTitle: slot == .a ? "Change Recording A" : "Change Recording B",
            selectedID: selected,
            excludedID: excluded
        ) { [weak self] record in
            guard let self else { return }
            self.playback.pause()
            if slot == .a {
                self.recordingAID = record.id
                self.markersA = []
            } else {
                self.recordingBID = record.id
                self.markersB = []
            }
            self.selection.recordingAID = self.recordingAID
            self.selection.recordingBID = self.recordingBID
            self.didLoadAudio = false
            self.load(resetPlayback: true)
        }
        let nav = UINavigationController(rootViewController: picker)
        SPStyle.applyNavigationAppearance(to: nav)
        present(nav, animated: true)
    }

    private func swapSlots() {
        playback.pause()
        let oldA = recordingAID
        recordingAID = recordingBID
        recordingBID = oldA
        selection.recordingAID = recordingAID
        selection.recordingBID = recordingBID
        let mA = markersA
        markersA = markersB
        markersB = mA
        didLoadAudio = false
        load(resetPlayback: true)
    }

    // MARK: - 报告

    private func makeReportPayload() -> ComparisonReportPayload? {
        guard let a = recordA, let b = recordB, let range = selectedRange else { return nil }
        return ComparisonReportPayload(
            recordA: a,
            recordB: b,
            summaryA: summaryA,
            summaryB: summaryB,
            waveformA: analysisService.waveform(for: a),
            waveformB: analysisService.waveform(for: b),
            spectrogramA: analysisService.spectrogram(for: a),
            spectrogramB: analysisService.spectrogram(for: b),
            diff: diffData,
            range: range,
            markersA: markersA,
            markersB: markersB,
            generatedAt: Date()
        )
    }

    @objc private func exportPDFReport() {
        guard let payload = makeReportPayload() else { return }
        let overlay = SPLoadingOverlay(message: "Creating PDF report…")
        overlay.show(in: view)
        do {
            let url = try ComparisonReportRenderer.shared.generate(payload: payload)
            overlay.hide()
            SPShare.present(items: [url], from: self) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            overlay.hide()
            presentError(error, title: "Couldn't Create PDF Report")
        }
    }

    @objc private func shareReport() {
        guard let a = recordA, let b = recordB else { return }
        var lines: [String] = []
        lines.append("Soundprint Comparison Notes")
        lines.append("")
        lines.append("A: \(a.title)")
        lines.append("  \(SPFormat.dateTime(a.createdAt)) / \(a.place?.name ?? "Unassigned") / \(SPFormat.duration(a.duration))")
        lines.append("B: \(b.title)")
        lines.append("  \(SPFormat.dateTime(b.createdAt)) / \(b.place?.name ?? "Unassigned") / \(SPFormat.duration(b.duration))")
        if let range = selectedRange {
            lines.append("")
            lines.append("Comparison range: \(SPFormat.duration(range.lowerBound))–\(SPFormat.duration(range.upperBound))")
        }
        lines.append("")
        lines.append("Recording Conditions")
        lines.append("A Device: \(a.deviceModel ?? "Unknown") / \(Int(a.sampleRate)) Hz / \(a.channelCount)ch")
        lines.append("B Device: \(b.deviceModel ?? "Unknown") / \(Int(b.sampleRate)) Hz / \(b.channelCount)ch")
        if let sa = summaryA, let sb = summaryB {
            lines.append("")
            lines.append("Signal Comparison")
            lines.append(String(format: "Average RMS: A %.1f dBFS / B %.1f dBFS", sa.rmsDBFS, sb.rmsDBFS))
            lines.append(String(format: "Peak: A %.1f dBFS / B %.1f dBFS", sa.peakDBFS, sb.peakDBFS))
            lines.append("Low band: A \(SPFormat.percent(sa.bands.low)) / B \(SPFormat.percent(sb.bands.low))")
            lines.append("Mid band: A \(SPFormat.percent(sa.bands.mid)) / B \(SPFormat.percent(sb.bands.mid))")
            lines.append("High band: A \(SPFormat.percent(sa.bands.high)) / B \(SPFormat.percent(sb.bands.high))")
        } else {
            lines.append("")
            lines.append("Note: Sound analysis is not complete yet.")
        }
        if !markersA.isEmpty || !markersB.isEmpty {
            lines.append("")
            lines.append("Temporary Markers")
            lines.append("A: " + markersA.map { SPFormat.duration($0.time) }.joined(separator: ", "))
            lines.append("B: " + markersB.map { SPFormat.duration($0.time) }.joined(separator: ", "))
        }
        lines.append("")
        lines.append("RMS · peak · band values are comparison values from the recording signal. Differences in equipment calibration and recording gain mean they will not match sound pressure level (dB SPL).")
        lines.append("These comparison notes were exported from Soundprint.")
        let text = lines.joined(separator: "\n")
        SPShare.present(items: [text], from: self)
    }
}

// MARK: - 比较数值行

private final class SPComparisonValueRow: UIView {
    init(title: String, a: String, b: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption2)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.numberOfLines = 2

        let aLabel = UILabel()
        aLabel.text = a
        aLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        aLabel.textColor = SPColor.accent
        aLabel.textAlignment = .center
        aLabel.adjustsFontSizeToFitWidth = true
        aLabel.minimumScaleFactor = 0.7
        aLabel.widthAnchor.constraint(equalToConstant: 82).isActive = true
        aLabel.adjustsFontForContentSizeCategory = true

        let bLabel = UILabel()
        bLabel.text = b
        bLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        bLabel.textColor = SPColor.moss
        bLabel.textAlignment = .center
        bLabel.adjustsFontSizeToFitWidth = true
        bLabel.minimumScaleFactor = 0.7
        bLabel.widthAnchor.constraint(equalToConstant: 82).isActive = true
        bLabel.adjustsFontForContentSizeCategory = true

        let row = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(aLabel)
        row.addArrangedSubview(bLabel)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0))
        isAccessibilityElement = true
        accessibilityLabel = "\(title), A \(a), B \(b)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
