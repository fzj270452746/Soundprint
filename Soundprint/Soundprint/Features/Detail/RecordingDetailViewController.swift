//
//  RecordingDetailViewController.swift
//  Soundprint
//
//  录音详情：波形播放、事件标注、本地分析与导出。
//

import UIKit

final class RecordingDetailViewController: SPViewController {
    private let recordingID: UUID
    private let library = LibraryService.shared
    private let analysisService = AudioAnalysisService.shared
    private let storage = StorageManager.shared
    private let playback = PlaybackService()

    private var record: RecordingEntity?
    private var hasAudioFile = false
    private var isSeeking = false
    private var reloadWorkItem: DispatchWorkItem?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 22)
    private let playerBar = UIView()
    private let playButton = SPPlayButton(size: 50)
    private let playerSlider = UISlider()
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private var waveformView: SPWaveformView?

    init(recordingID: UUID) {
        self.recordingID = recordingID
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recording"
        buildPlayerBar()
        buildScroll()
        bindPlayback()
        observe()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        load()
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
            )
        ]
    }

    @objc private func keyboardTogglePlayback() {
        playTapped()
    }

    @objc private func keyboardBackward() {
        playback.skip(by: -5)
    }

    @objc private func keyboardForward() {
        playback.skip(by: 5)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            playback.pause()
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
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
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

        currentLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        currentLabel.textColor = SPColor.secondaryInk
        currentLabel.text = "0:00"
        currentLabel.setContentHuggingPriority(.required, for: .horizontal)

        durationLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        durationLabel.textColor = SPColor.tertiaryInk
        durationLabel.text = "0:00"
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let timeRow = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        timeRow.addArrangedSubview(currentLabel)
        timeRow.addArrangedSubview(UIView())
        timeRow.addArrangedSubview(durationLabel)

        playerSlider.translatesAutoresizingMaskIntoConstraints = false
        playerSlider.minimumValue = 0
        playerSlider.maximumValue = 1
        playerSlider.minimumTrackTintColor = SPColor.accent
        playerSlider.maximumTrackTintColor = SPColor.hairline
        playerSlider.setThumbImage(SPImage.sliderThumb(), for: .normal)
        playerSlider.setThumbImage(SPImage.sliderThumb(diameter: 20), for: .highlighted)
        playerSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        playerSlider.accessibilityLabel = "Playback position"
        playerSlider.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let controlStack = UIStackView(axis: .vertical, spacing: 1)
        controlStack.addArrangedSubview(timeRow)
        controlStack.addArrangedSubview(playerSlider)

        playerBar.addSubview(controlStack)
        controlStack.translatesAutoresizingMaskIntoConstraints = false

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
            controlStack.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 14),
            controlStack.trailingAnchor.constraint(equalTo: playerBar.trailingAnchor, constant: -SPMetric.screenInset),
            controlStack.centerYAnchor.constraint(equalTo: playButton.centerYAnchor)
        ])
    }

    private func bindPlayback() {
        playback.onUpdate = { [weak self] current, duration, isPlaying in
            guard let self else { return }
            self.currentLabel.text = SPFormat.duration(current)
            self.durationLabel.text = SPFormat.duration(duration)
            self.playButton.isPlaying = isPlaying
            if duration > 0 {
                self.playerSlider.maximumValue = Float(duration)
                if !self.isSeeking {
                    self.playerSlider.value = Float(current)
                }
                self.waveformView?.progress = CGFloat(current / duration)
                self.playerSlider.accessibilityValue = "\(SPFormat.accessibleDuration(current)) / \(SPFormat.accessibleDuration(duration))"
            }
        }
        playback.onStateChange = { [weak self] state in
            self?.playButton.isPlaying = state == .playing
        }
    }

    // MARK: - 加载

    private func load() {
        guard let record = library.fetchRecording(id: recordingID) else {
            navigationController?.popViewController(animated: true)
            return
        }
        self.record = record
        navigationItem.title = "Recording"
        configureMenu(for: record)
        prepareAudio(for: record)
        rebuildContent(record: record)
        if EventSuggestionService.isEnabled, record.waveformRelativePath != nil {
            EventSuggestionService.shared.schedule(recordingID: record.id, force: false)
        }
    }

    private func prepareAudio(for record: RecordingEntity) {
        guard let url = storage.audioURL(for: record),
              FileManager.default.fileExists(atPath: url.path) else {
            hasAudioFile = false
            playButton.isEnabled = false
            playerSlider.isEnabled = false
            currentLabel.text = "—"
            durationLabel.text = "—"
            return
        }
        if !hasAudioFile {
            hasAudioFile = playback.load(url: url)
        }
        playButton.isEnabled = hasAudioFile
        playerSlider.isEnabled = hasAudioFile
        if hasAudioFile {
            currentLabel.text = SPFormat.duration(playback.currentTime)
            durationLabel.text = SPFormat.duration(playback.duration)
            playerSlider.maximumValue = Float(max(0.001, playback.duration))
            playerSlider.value = Float(playback.currentTime)
        }
    }

    private func configureMenu(for record: RecordingEntity) {
        let share = UIAction(title: "Export", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.shareTapped()
        }
        let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.editTapped()
        }
        let trim = UIAction(title: "Create Excerpt", image: UIImage(systemName: "scissors")) { [weak self] _ in
            self?.trimTapped()
        }
        let retry = UIAction(title: "Rerun Analysis", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            guard let self else { return }
            self.analysisService.schedule(recordingID: self.recordingID, force: true)
            SPToast.show("Analysis started", in: self.view, symbol: "waveform")
            self.reloadSoon()
        }
        let delete = UIAction(
            title: "Delete Recording",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.deleteTapped()
        }
        let actions = hasAudioFile ? [share, edit, trim, retry, delete] : [share, edit, retry, delete]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.libraryDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.analysisDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.suggestionsDidChange,
            object: nil
        )
    }

    @objc private func dataChanged() {
        reloadSoon()
    }

    private func reloadSoon() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let record = self.library.fetchRecording(id: self.recordingID) else { return }
            let offset = self.scrollView.contentOffset
            self.record = record
            self.rebuildContent(record: record)
            self.view.layoutIfNeeded()
            let maxOffset = max(0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
            self.scrollView.setContentOffset(
                CGPoint(x: 0, y: min(offset.y, maxOffset)),
                animated: false
            )
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    // MARK: - 内容

    private func rebuildContent(record: RecordingEntity) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        waveformView = nil

        if !hasAudioFile {
            contentStack.addArrangedSubview(makeMissingAudioCard())
        }
        contentStack.addArrangedSubview(makeHeader(record: record))
        contentStack.addArrangedSubview(makeWaveformCard(record: record))
        if let noteCard = makeObservationCard(record: record) {
            contentStack.addArrangedSubview(noteCard)
        }
        contentStack.addArrangedSubview(makeEventsSection(record: record))
        if let suggestions = makeSuggestionsSection(record: record) {
            contentStack.addArrangedSubview(suggestions)
        }
        contentStack.addArrangedSubview(makeAnalysisSection(record: record))
        contentStack.addArrangedSubview(makeInfoCard(record: record))
    }

    private func makeHeader(record: RecordingEntity) -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let eyebrow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let dateLabel = UILabel()
        dateLabel.text = SPFormat.dateTime(record.createdAt)
        dateLabel.font = SPFont.text(11.5, weight: .medium, relativeTo: .caption1)
        dateLabel.textColor = SPColor.secondaryInk
        dateLabel.adjustsFontForContentSizeCategory = true
        eyebrow.addArrangedSubview(dateLabel)
        eyebrow.addArrangedSubview(UIView())
        eyebrow.addArrangedSubview(makeAnalysisBadge(for: record))
        stack.addArrangedSubview(eyebrow)

        let title = UILabel()
        title.text = record.title
        title.font = SPFont.display(30, relativeTo: .largeTitle)
        title.textColor = SPColor.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            title.maximumContentSizeCategory = .accessibilityMedium
        }
        stack.addArrangedSubview(title)

        let meta = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
        let pin = UIImageView(image: UIImage(systemName: "mappin", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)))
        pin.tintColor = SPColor.accent
        meta.addArrangedSubview(pin)
        let placeLabel = UILabel()
        placeLabel.text = record.place?.name ?? "Unassigned Recording"
        placeLabel.font = SPFont.text(12.5, weight: .medium, relativeTo: .footnote)
        placeLabel.textColor = SPColor.accent
        placeLabel.adjustsFontForContentSizeCategory = true
        meta.addArrangedSubview(placeLabel)
        let dot = UILabel()
        dot.text = "·"
        dot.font = SPFont.text(11, weight: .regular)
        dot.textColor = SPColor.tertiaryInk
        meta.addArrangedSubview(dot)
        let duration = UILabel()
        duration.text = SPFormat.duration(record.duration)
        duration.font = SPFont.mono(11.5, weight: .regular, relativeTo: .footnote)
        duration.textColor = SPColor.tertiaryInk
        duration.adjustsFontForContentSizeCategory = true
        meta.addArrangedSubview(duration)
        meta.addArrangedSubview(UIView())
        stack.addArrangedSubview(meta)

        if !record.tags.isEmpty {
            let tagFlow = SPTagFlowView(tags: record.tags)
            tagFlow.setContentHuggingPriority(.defaultLow, for: .vertical)
            stack.setCustomSpacing(12, after: meta)
            stack.addArrangedSubview(tagFlow)
        }
        return stack
    }

    private func makeAnalysisBadge(for record: RecordingEntity) -> SPStatusBadge {
        switch record.analysisState {
        case .ready:
            return SPStatusBadge(text: "Analyzed", color: SPColor.moss)
        case .processing, .pending:
            return SPStatusBadge(text: "Analyzing", color: SPColor.amber)
        case .failed:
            return SPStatusBadge(text: "Analysis Failed", color: SPColor.danger)
        case .disabled:
            return SPStatusBadge(text: "Analysis Off", color: SPColor.tertiaryInk)
        }
    }

    private func makeWaveformCard(record: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 6)
        let top = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let label = UILabel()
        label.text = "Waveform"
        label.font = SPFont.text(11.5, weight: .semibold, relativeTo: .caption1)
        label.textColor = SPColor.secondaryInk
        label.adjustsFontForContentSizeCategory = true
        top.addArrangedSubview(label)
        top.addArrangedSubview(UIView())
        let hint = UILabel()
        hint.text = hasAudioFile ? "Tap to move the playback position" : "Audio file not found"
        hint.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        hint.textColor = SPColor.tertiaryInk
        hint.adjustsFontForContentSizeCategory = true
        top.addArrangedSubview(hint)
        stack.addArrangedSubview(top)

        let wave = SPWaveformView()
        wave.accessibilityLabel = "Recording waveform"
        wave.cache = analysisService.waveform(for: record)
        wave.isLoading = wave.cache == nil && record.analysisState.isBusy
        wave.duration = record.duration
        wave.tint = SPColor.secondaryInk
        wave.playedTint = SPColor.accent
        wave.progress = playback.duration > 0 ? CGFloat(playback.currentTime / playback.duration) : 0
        wave.markers = record.sortedEvents.map {
            WaveformMarkerDisplay(time: $0.startTime, color: $0.kind.color, title: $0.title)
        }
        wave.onSeek = { [weak self] time in
            guard let self, self.hasAudioFile else { return }
            self.playback.seek(to: time)
        }
        wave.heightAnchor.constraint(equalToConstant: 112).isActive = true
        wave.isUserInteractionEnabled = hasAudioFile
        stack.addArrangedSubview(wave)
        waveformView = wave

        let bottom = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let eventsLabel = UILabel()
        eventsLabel.text = record.sortedEvents.isEmpty
            ? "No events recorded"
            : "\(record.sortedEvents.count) events"
        eventsLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        eventsLabel.textColor = SPColor.tertiaryInk
        eventsLabel.adjustsFontForContentSizeCategory = true
        bottom.addArrangedSubview(eventsLabel)
        bottom.addArrangedSubview(UIView())
        let timeLabel = UILabel()
        timeLabel.text = SPFormat.duration(record.duration)
        timeLabel.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
        timeLabel.textColor = SPColor.tertiaryInk
        timeLabel.adjustsFontForContentSizeCategory = true
        bottom.addArrangedSubview(timeLabel)
        stack.addArrangedSubview(bottom)

        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        return card
    }

    private func makeObservationCard(record: RecordingEntity) -> UIView? {
        let hasNote = !(record.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasWeather = !(record.weather ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasNote || hasWeather else { return nil }

        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Observation Notes"
        title.font = SPFont.display(19, relativeTo: .headline)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        if hasWeather, let weather = record.weather {
            header.addArrangedSubview(SPTagView(
                text: weather,
                symbol: "cloud.sun",
                color: SPColor.amber,
                background: SPColor.amberSoft
            ))
        }
        stack.addArrangedSubview(header)
        if hasNote, let note = record.note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = SPFont.text(14, weight: .regular, relativeTo: .body)
            noteLabel.textColor = SPColor.secondaryInk
            noteLabel.numberOfLines = 0
            noteLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(noteLabel)
        }
        card.addContent(stack, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        return card
    }

    // MARK: - 事件候选

    private func makeSuggestionsSection(record: RecordingEntity) -> UIView? {
        guard EventSuggestionService.isEnabled, record.waveformRelativePath != nil else { return nil }
        let suggestions = EventSuggestionService.shared.suggestions(for: record)
        let section = UIStackView(axis: .vertical, spacing: 10)
        let header = SPSectionHeaderView(
            title: "Sound Suggestions",
            subtitle: "From on-device changes",
            actionTitle: "Detect Again",
            action: { [weak self] in self?.redetectSuggestions(record: record) }
        )
        section.addArrangedSubview(header)

        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let badgeRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        badgeRow.addArrangedSubview(SPStatusBadge(text: "Estimated", color: SPColor.amber))
        let note = UILabel()
        note.text = "These aren't confirmed automatically. Review each one before adding."
        note.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.adjustsFontForContentSizeCategory = true
        note.numberOfLines = 0
        badgeRow.addArrangedSubview(note)
        let badgeWrapper = UIView()
        badgeWrapper.addSubview(badgeRow)
        badgeRow.pinEdges(to: badgeWrapper, insets: UIEdgeInsets(top: 12, left: 14, bottom: 8, right: 14))
        stack.addArrangedSubview(badgeWrapper)

        if suggestions.isEmpty {
            let empty = UIView()
            let label = UILabel()
            label.text = "No suggestions right now.\nSections where volume or frequency content changes are found on-device."
            label.font = SPFont.text(12, weight: .regular, relativeTo: .footnote)
            label.textColor = SPColor.secondaryInk
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            empty.addSubview(label)
            label.pinEdges(to: empty, insets: UIEdgeInsets(top: 6, left: 14, bottom: 16, right: 14))
            stack.addArrangedSubview(empty)
        } else {
            for (index, suggestion) in suggestions.enumerated() {
                let row = SPSuggestionRowView()
                row.configure(with: suggestion)
                row.onAccept = { [weak self] in
                    self?.acceptSuggestion(suggestion, record: record)
                }
                row.onIgnore = { [weak self] in
                    EventSuggestionService.shared.discard(suggestionID: suggestion.id, for: record)
                    self?.reloadSoon()
                }
                stack.addArrangedSubview(row)
                if index < suggestions.count - 1 {
                    stack.addArrangedSubview(SPDivider())
                }
            }
            let footer = UILabel()
            footer.text = "Suggestions are based on changes in the recorded signal. They don't determine the kind or meaning of a sound."
            footer.font = SPFont.text(9.5, weight: .regular, relativeTo: .caption2)
            footer.textColor = SPColor.tertiaryInk
            footer.numberOfLines = 0
            footer.adjustsFontForContentSizeCategory = true
            let wrapper = UIView()
            wrapper.addSubview(footer)
            footer.pinEdges(to: wrapper, insets: UIEdgeInsets(top: 10, left: 14, bottom: 14, right: 14))
            stack.addArrangedSubview(SPDivider())
            stack.addArrangedSubview(wrapper)
        }

        card.addContent(stack, insets: UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6))
        section.addArrangedSubview(card)
        return section
    }

    private func redetectSuggestions(record: RecordingEntity) {
        EventSuggestionService.shared.schedule(recordingID: record.id, force: true)
        SPHaptic.selection()
        SPToast.show("Detecting sound changes", in: view, symbol: "waveform")
    }

    private func acceptSuggestion(_ suggestion: EventSuggestion, record: RecordingEntity) {
        let editor = EventEditorViewController(
            record: record,
            event: nil,
            defaultTime: suggestion.startTime,
            initialEndTime: suggestion.endTime,
            initialTitle: "Sound Change",
            initialKind: .other,
            onSaved: { [weak self] in
                EventSuggestionService.shared.discard(suggestionID: suggestion.id, for: record)
                self?.reloadSoon()
            }
        )
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    // MARK: - 事件

    private func makeEventsSection(record: RecordingEntity) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 10)
        let header = SPSectionHeaderView(
            title: "Sound Events",
            subtitle: record.sortedEvents.isEmpty ? "Mark the sounds you notice" : "\(record.sortedEvents.count) events",
            actionTitle: "Add",
            action: { [weak self] in self?.addEventTapped() }
        )
        section.addArrangedSubview(header)

        if record.sortedEvents.isEmpty {
            let card = SPCardView(style: .sunken)
            let stack = UIStackView(axis: .vertical, spacing: 8, alignment: .center)
            let icon = UIImageView(image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)))
            icon.tintColor = SPColor.secondaryInk
            let label = UILabel()
            label.text = "A car, a bird, a door.\nMark the moment you notice on the waveform."
            label.font = SPFont.text(12, weight: .regular, relativeTo: .footnote)
            label.textColor = SPColor.secondaryInk
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            let button = SPButton(title: "Add First Event", symbol: "plus", style: .secondary)
            button.addTarget(self, action: #selector(addEventTapped), for: .touchUpInside)
            stack.addArrangedSubview(icon)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(button)
            card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
            section.addArrangedSubview(card)
            return section
        }

        let card = SPCardView(style: .surface)
        let rows = UIStackView(axis: .vertical, spacing: 0)
        for (index, event) in record.sortedEvents.enumerated() {
            let row = SPEventRowView()
            row.configure(with: event, duration: record.duration)
            row.onTap = { [weak self] in
                guard let self else { return }
                self.playback.seek(to: event.startTime)
                if self.hasAudioFile, self.playback.state != .playing {
                    self.playback.play()
                }
                SPHaptic.light()
            }
            row.onMore = { [weak self] in
                self?.presentEventMenu(event)
            }
            row.onEdit = { [weak self] in
                self?.editEvent(event)
            }
            row.onDelete = { [weak self] in
                guard let self else { return }
                self.presentConfirm(
                    title: "Delete This Event?",
                    message: nil,
                    destructiveTitle: "Delete"
                ) {
                    try? self.library.deleteEvent(event)
                }
            }
            rows.addArrangedSubview(row)
            if index < record.sortedEvents.count - 1 {
                rows.addArrangedSubview(SPDivider())
            }
        }
        card.addContent(rows, insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
        section.addArrangedSubview(card)
        return section
    }

    private func presentEventMenu(_ event: SoundEventEntity) {
        let sheet = UIAlertController(title: event.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
            self?.editEvent(event)
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.presentConfirm(
                title: "Delete This Event?",
                message: nil,
                destructiveTitle: "Delete"
            ) {
                try? self.library.deleteEvent(event)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    @objc private func addEventTapped() {
        guard let record else { return }
        let editor = EventEditorViewController(
            record: record,
            event: nil,
            defaultTime: max(0, min(playback.currentTime, record.duration)),
            onSaved: {}
        )
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func editEvent(_ event: SoundEventEntity) {
        guard let record else { return }
        let editor = EventEditorViewController(
            record: record,
            event: event,
            defaultTime: event.startTime,
            onSaved: {}
        )
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    // MARK: - 分析

    private func makeAnalysisSection(record: RecordingEntity) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 12)
        let header = SPSectionHeaderView(
            title: "Sound Analysis",
            subtitle: "All computed on-device",
            actionTitle: record.analysisState == .ready || record.analysisState == .disabled ? nil : "Retry",
            action: { [weak self] in
                guard let self else { return }
                self.analysisService.schedule(recordingID: self.recordingID, force: true)
                self.reloadSoon()
            }
        )
        section.addArrangedSubview(header)

        switch record.analysisState {
        case .pending, .processing:
            section.addArrangedSubview(makeAnalyzingCard())
        case .failed:
            section.addArrangedSubview(makeAnalysisFailedCard())
        case .disabled:
            section.addArrangedSubview(makeAnalysisDisabledCard())
        case .ready:
            if let summary = analysisService.analysis(for: record) {
                section.addArrangedSubview(makeMetricsCard(summary: summary))
                section.addArrangedSubview(makeRMSCard(summary: summary))
                section.addArrangedSubview(makeSpectrogramCard(record: record, summary: summary))
                section.addArrangedSubview(SPInfoBanner(
                    title: "Reading These Values",
                    message: "The RMS, peak, and band values are relative measures of the recorded signal. They are affected by microphone model, distance, and automatic gain, and are not calibrated sound pressure level (dB SPL).",
                    tone: .neutral,
                    symbol: "info.circle"
                ))
                section.addArrangedSubview(makeAnalysisInfoCard(summary: summary))
            } else {
                section.addArrangedSubview(makeAnalyzingCard())
            }
        }
        return section
    }

    private func makeAnalyzingCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = SPColor.accent
        spinner.startAnimating()
        let textStack = UIStackView(axis: .vertical, spacing: 3)
        let title = UILabel()
        title.text = "Analyzing the sound's characteristics"
        title.font = SPFont.text(14, weight: .semibold, relativeTo: .subheadline)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        let body = UILabel()
        body.text = "You can view the waveform and play the recording without waiting for analysis to finish."
        body.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
        body.textColor = SPColor.secondaryInk
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(body)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(textStack)
        card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        return card
    }

    private func makeAnalysisFailedCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let banner = SPInfoBanner(
            title: "Analysis Couldn't Be Completed",
            message: "The recording itself is saved. You can still play and export it.",
            tone: .warning
        )
        let retry = SPButton(title: "Analyze Again", symbol: "arrow.clockwise", style: .secondary)
        retry.addTarget(self, action: #selector(retryAnalysisTapped), for: .touchUpInside)
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(retry)
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    private func makeAnalysisDisabledCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let banner = SPInfoBanner(
            title: "Automatic Analysis Is Off",
            message: "Waveform and playback are available. You can analyze this recording only when you need to.",
            tone: .neutral
        )
        let analyze = SPButton(title: "Analyze This Recording", symbol: "waveform.path.ecg", style: .secondary)
        analyze.addTarget(self, action: #selector(retryAnalysisTapped), for: .touchUpInside)
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(analyze)
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    private func makeMetricsCard(summary: AudioAnalysisSummary) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)
        let row = UIStackView(axis: .horizontal, spacing: 8, distribution: .fillEqually)
        row.addArrangedSubview(SPMetricTile(
            title: "Average RMS",
            value: SPFormat.decibel(summary.rmsDBFS),
            unit: "dBFS",
            accent: SPColor.ink
        ))
        row.addArrangedSubview(SPMetricTile(
            title: "Digital Peak",
            value: SPFormat.decibel(summary.peakDBFS),
            unit: "dBFS",
            accent: SPColor.accent
        ))
        row.addArrangedSubview(SPMetricTile(
            title: "Channels",
            value: summary.channels == 1 ? "Mono" : "\(summary.channels)ch",
            accent: SPColor.secondaryInk
        ))
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(SPBandCompositionView())
        if let bandView = stack.arrangedSubviews.last as? SPBandCompositionView {
            bandView.configure(bands: summary.bands)
        }
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 16, right: 14))
        return card
    }

    private func makeRMSCard(summary: AudioAnalysisSummary) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 8)
        let title = UILabel()
        title.text = "RMS over Time"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        let graph = SPRMSTrendView()
        graph.configure(values: summary.rmsTimeline)
        graph.heightAnchor.constraint(equalToConstant: 82).isActive = true
        let caption = UILabel()
        caption.text = "Relative strength of the recorded signal. The time axis spans the whole recording."
        caption.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        caption.textColor = SPColor.tertiaryInk
        caption.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(graph)
        stack.addArrangedSubview(caption)
        card.addContent(stack, insets: UIEdgeInsets(top: 15, left: 16, bottom: 14, right: 16))
        return card
    }

    private func makeSpectrogramCard(record: RecordingEntity, summary: AudioAnalysisSummary) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        let titleRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Simplified Spectrogram"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(UIView())
        if let spectrum = analysisService.spectrogram(for: record) {
            let range = UILabel()
            range.text = "0 – \(Int(spectrum.maxFrequency / 1000)) kHz"
            range.font = SPFont.mono(9.5, weight: .regular, relativeTo: .caption2)
            range.textColor = SPColor.tertiaryInk
            titleRow.addArrangedSubview(range)
        }
        stack.addArrangedSubview(titleRow)

        let plot = SPSpectrogramView()
        plot.cache = analysisService.spectrogram(for: record)
        plot.heightAnchor.constraint(equalToConstant: 132).isActive = true
        stack.addArrangedSubview(plot)

        let axes = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
        let timeStart = UILabel()
        timeStart.text = "0:00"
        timeStart.font = SPFont.mono(9, weight: .regular, relativeTo: .caption2)
        timeStart.textColor = SPColor.tertiaryInk
        let timeEnd = UILabel()
        timeEnd.text = SPFormat.duration(summary.duration)
        timeEnd.font = SPFont.mono(9, weight: .regular, relativeTo: .caption2)
        timeEnd.textColor = SPColor.tertiaryInk
        axes.addArrangedSubview(timeStart)
        axes.addArrangedSubview(UIView())
        axes.addArrangedSubview(timeEnd)
        stack.addArrangedSubview(axes)

        card.addContent(stack, insets: UIEdgeInsets(top: 15, left: 16, bottom: 13, right: 16))
        return card
    }

    private func makeAnalysisInfoCard(summary: AudioAnalysisSummary) -> UIView {
        let card = SPCardView(style: .sunken)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        stack.addArrangedSubview(SPValueRow(
            title: "Analysis Version",
            value: summary.algorithmVersion
        ))
        stack.addArrangedSubview(SPValueRow(
            title: "Window Length / Hop",
            value: "\(summary.windowSize) / \(summary.hopSize)"
        ))
        stack.addArrangedSubview(SPValueRow(
            title: "Analysis Sample Rate",
            value: "\(SPFormat.decimal(summary.sampleRate / 1000)) kHz"
        ))
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 15, bottom: 14, right: 15))
        return card
    }

    // MARK: - 录音信息

    private func makeInfoCard(record: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 11)
        let title = UILabel()
        title.text = "Recording Info"
        title.font = SPFont.display(19, relativeTo: .headline)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)

        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(title: "Date Recorded", value: SPFormat.dateTime(record.createdAt)))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(title: "Duration", value: SPFormat.duration(record.duration)))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(
            title: "Format",
            value: "\(record.audioFormat.uppercased()) · \(Int(record.sampleRate)) Hz · \(record.channelCount == 1 ? "Mono" : "\(record.channelCount)ch")"
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(title: "File Size", value: SPFormat.fileSize(record.fileSize)))
        if let device = record.deviceModel, !device.isEmpty {
            stack.addArrangedSubview(SPDivider())
            stack.addArrangedSubview(SPValueRow(title: "Recording Device", value: device))
        }
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(
            title: "Location",
            value: record.coordinate.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) } ?? "Not saved"
        ))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(
            title: "Audio File",
            value: hasAudioFile ? "Saved" : "Not found",
            valueColor: hasAudioFile ? SPColor.moss : SPColor.danger
        ))

        let export = SPButton(title: "Export This Recording", symbol: "square.and.arrow.up", style: .secondary)
        export.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(export)

        let trim = SPButton(title: "Create Excerpt from This Recording", symbol: "scissors", style: .secondary)
        trim.addTarget(self, action: #selector(trimTapped), for: .touchUpInside)
        trim.isEnabled = hasAudioFile
        stack.setCustomSpacing(9, after: export)
        stack.addArrangedSubview(trim)

        let delete = SPButton(title: "Delete Recording", symbol: "trash", style: .danger)
        delete.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        stack.setCustomSpacing(9, after: trim)
        stack.addArrangedSubview(delete)

        card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
        return card
    }

    private func makeMissingAudioCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 11)
        let banner = SPInfoBanner(
            title: "Audio File Not Found",
            message: "Metadata and events are kept. Restore from a device backup, or delete this recording.",
            tone: .warning
        )
        let metadataButton = SPButton(title: "Export Metadata Only", symbol: "doc.text", style: .secondary)
        metadataButton.addTarget(self, action: #selector(exportMetadataOnlyTapped), for: .touchUpInside)
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(metadataButton)
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    // MARK: - 播放操作

    @objc private func playTapped() {
        guard hasAudioFile else { return }
        playback.togglePlayback()
        SPHaptic.light()
    }

    @objc private func sliderChanged() {
        guard hasAudioFile else { return }
        isSeeking = true
        let target = Double(playerSlider.value)
        playback.seek(to: target)
        if let duration = record?.duration, duration > 0 {
            waveformView?.progress = CGFloat(target / duration)
        }
        currentLabel.text = SPFormat.duration(target)
        isSeeking = false
    }

    @objc private func retryAnalysisTapped() {
        analysisService.schedule(recordingID: recordingID, force: true)
        SPToast.show("Analysis started", in: view, symbol: "waveform")
        reloadSoon()
    }

    // MARK: - 文件操作

    @objc private func shareTapped() {
        guard let record else { return }
        let controller = ExportOptionsViewController(record: record) { [weak self] options in
            self?.performExport(options)
        }
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 24
        }
        present(controller, animated: true)
    }

    @objc private func exportMetadataOnlyTapped() {
        performExport(RecordingExportOptions(includeMetadata: true, includeExactLocation: false))
    }

    private func performExport(_ options: RecordingExportOptions) {
        guard let record else { return }
        do {
            let package = try RecordingExportService.shared.createExport(for: record, options: options)
            SPShare.present(items: package.items, from: self) {
                try? FileManager.default.removeItem(at: package.temporaryDirectory)
            }
        } catch {
            presentError(error, title: "Couldn't Export")
        }
    }

    @objc private func trimTapped() {
        guard let record, hasAudioFile else { return }
        playback.pause()
        let trim = TrimClipViewController(record: record)
        trim.onSaved = { [weak self] newRecord in
            guard let self else { return }
            self.load()
            SPToast.show("Excerpt saved", in: self.view, symbol: "scissors")
            let detail = RecordingDetailViewController(recordingID: newRecord.id)
            self.navigationController?.pushViewController(detail, animated: true)
        }
        let nav = UINavigationController(rootViewController: trim)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func editTapped() {
        guard let record else { return }
        let editor = RecordingEditViewController(record: record) { [weak self] in
            self?.load()
            guard let self else { return }
            SPToast.show("Recording updated", in: self.view)
        }
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func deleteTapped() {
        guard let record else { return }
        presentConfirm(
            title: "Delete This Recording?",
            message: "The audio file, events, and analysis results will all be deleted. This can't be undone.",
            destructiveTitle: "Delete"
        ) { [weak self] in
            guard let self else { return }
            self.playback.pause()
            do {
                try self.library.deleteRecording(record)
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.presentError(error)
            }
        }
    }
}

// MARK: - 事件行

private final class SPEventRowView: UIControl {
    private let timeLabel = UILabel()
    private let iconTile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 34, pointSize: 13)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    var onTap: (() -> Void)?
    var onMore: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        timeLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        timeLabel.textColor = SPColor.accent
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        titleLabel.font = SPFont.text(14, weight: .semibold, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        detailLabel.textColor = SPColor.tertiaryInk
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontForContentSizeCategory = true

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        moreButton.tintColor = SPColor.tertiaryInk
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        moreButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        let row = UIStackView(axis: .horizontal, spacing: 9, alignment: .center)
        row.addArrangedSubview(timeLabel)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(moreButton)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 9, left: 4, bottom: 9, right: 2))
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with event: SoundEventEntity, duration: Double) {
        timeLabel.text = SPFormat.duration(event.startTime)
        let newTile = SPIconTile(symbol: event.kind.symbolName, color: event.kind.color, size: 34, pointSize: 13)
        iconTile.removeFromSuperview()
        if let row = subviews.first as? UIStackView {
            row.insertArrangedSubview(newTile, at: 1)
        }
        titleLabel.text = event.title
        var detail = event.kind.title
        if let end = event.endTimeValue, end > event.startTime {
            detail += " · \(SPFormat.duration(event.startTime))–\(SPFormat.duration(end))"
        }
        detailLabel.text = detail
        accessibilityLabel = "\(event.kind.title), \(event.title), starts \(SPFormat.accessibleDuration(event.startTime))"
        accessibilityHint = "Move playback to this event"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Edit Event", target: self, selector: #selector(accessibilityEdit)),
            UIAccessibilityCustomAction(name: "Delete Event", target: self, selector: #selector(accessibilityDelete))
        ]
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }

    @objc private func tapped() { onTap?() }
    @objc private func moreTapped() { onMore?() }

    @objc private func accessibilityEdit() -> Bool {
        onEdit?()
        return true
    }

    @objc private func accessibilityDelete() -> Bool {
        onDelete?()
        return true
    }
}


// MARK: - 建议行

private final class SPSuggestionRowView: UIView {
    private let timeLabel = UILabel()
    private let iconTile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 32, pointSize: 12)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let acceptButton = SPTextButton(title: "Add")
    private let ignoreButton = UIButton(type: .system)
    var onAccept: (() -> Void)?
    var onIgnore: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        timeLabel.textColor = SPColor.accent
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        titleLabel.font = SPFont.text(13.5, weight: .semibold, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        detailLabel.textColor = SPColor.tertiaryInk
        detailLabel.numberOfLines = 2
        detailLabel.adjustsFontForContentSizeCategory = true

        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        acceptButton.accessibilityLabel = "Add suggestion as event"

        ignoreButton.translatesAutoresizingMaskIntoConstraints = false
        ignoreButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
        ignoreButton.tintColor = SPColor.tertiaryInk
        ignoreButton.addTarget(self, action: #selector(ignoreTapped), for: .touchUpInside)
        ignoreButton.accessibilityLabel = "Ignore suggestion"
        ignoreButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        ignoreButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)
        let row = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        row.addArrangedSubview(timeLabel)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(acceptButton)
        row.addArrangedSubview(ignoreButton)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 6))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with suggestion: EventSuggestion) {
        timeLabel.text = SPFormat.duration(suggestion.startTime)
        titleLabel.text = suggestion.title
        detailLabel.text = "\(SPFormat.preciseDuration(suggestion.startTime))–\(SPFormat.preciseDuration(suggestion.endTime)) · \(suggestion.strengthLabel)"
        accessibilityLabel = "\(suggestion.title), \(SPFormat.accessibleDuration(suggestion.startTime)) to \(SPFormat.accessibleDuration(suggestion.endTime)). \(suggestion.strengthLabel)"
    }

    @objc private func acceptTapped() { onAccept?() }
    @objc private func ignoreTapped() { onIgnore?() }
}
