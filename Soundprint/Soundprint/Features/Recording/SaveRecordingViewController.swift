//
//  SaveRecordingViewController.swift
//  Soundprint
//
//  录音完成后补充元数据。文件在点击保存后才从临时区原子移动到正式档案。
//

import CoreLocation
import UIKit

final class SaveRecordingViewController: SPViewController {
    var onSaved: ((RecordingEntity) -> Void)?
    var onDiscard: (() -> Void)?

    private let result: RecordingResult
    private let isRecovery: Bool
    private let library = LibraryService.shared
    private let preview = PlaybackService()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 16)
    private let bottomBar = UIView()
    private let saveButton = SPButton(title: "Save Recording", symbol: "checkmark", style: .primary)
    private let titleField = SPTextFieldView(title: "Title", placeholder: "Recording name", isRequired: true)
    private let placeRow = SPMenuRow(title: "Place", value: nil, symbol: "mappin.and.ellipse")
    private let tagFlow = SPTagFlowView()
    private let weatherField = SPTextFieldView(title: "Weather & Environment", placeholder: "e.g. clear skies, light wind", symbol: "cloud.sun")
    private let noteView = SPTextView(title: "Observation Notes", placeholder: "Sounds you heard, things you noticed, the recording conditions.", maxLength: 1200)
    private let previewButton = SPPlayButton(size: 38)
    private let previewTime = UILabel()
    private let coordinateLabel = UILabel()
    private let accuracyLabel = UILabel()
    private let coordinateStack = UIStackView(axis: .vertical, spacing: 3)
    private let precisionStack = UIStackView(axis: .horizontal, spacing: 7)
    private let locationButton = SPButton(title: "Add Current Location", symbol: "location.fill", style: .secondary)
    private let clearLocationButton = SPTextButton(title: "Remove Location")

    private var placeID: UUID?
    private var placeName: String?
    private var tags: [String] = []
    private var coordinate: Coordinate?
    private var precision: LocationPrecision = .none
    private var precisionChips: [SPFilterChip] = []
    private var isSaving = false

    init(result: RecordingResult, isRecovery: Bool = false) {
        self.result = result
        self.isRecovery = isRecovery
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save Recording"
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        placeID = result.placeID
        placeName = result.placeID.flatMap { library.fetchPlace(id: $0)?.name }
        titleField.text = defaultTitle()
        placeRow.value = placeName ?? "Not Set"
        buildInterface()
        tagFlow.tags = tags
        tagFlow.showsAddButton = true
        tagFlow.removable = true
        configurePreview()
        isModalInPresentation = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        preview.pause()
    }

    private func defaultTitle() -> String {
        if isRecovery { return "Recovered Recording" }
        let date = SPFormat.mediumDate.string(from: result.createdAt)
        let time = SPFormat.time.string(from: result.createdAt)
        return "Recording from \(date) \(time)"
    }

    // MARK: - 界面

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        if isRecovery {
            contentStack.addArrangedSubview(SPInfoBanner(
                title: "Recovered Interrupted Recording",
                message: "You can save the portion that was recorded. Review it, then add a place or notes.",
                tone: .success,
                symbol: "arrow.clockwise.circle"
            ))
        }

        contentStack.addArrangedSubview(makeSummaryCard())
        contentStack.addArrangedSubview(makeCard(with: titleField))
        contentStack.addArrangedSubview(makeCard(with: placeRow, insets: UIEdgeInsets(top: 13, left: 13, bottom: 13, right: 13)))
        contentStack.addArrangedSubview(makeTagsCard())
        contentStack.addArrangedSubview(makeWeatherCard())
        contentStack.addArrangedSubview(makeCard(with: noteView))
        contentStack.addArrangedSubview(makeLocationCard())

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = SPColor.paper
        let border = UIView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.backgroundColor = SPColor.hairline
        bottomBar.addSubview(border)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        bottomBar.addSubview(saveButton)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            border.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            border.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
            saveButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: SPMetric.screenInset),
            saveButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -SPMetric.screenInset),
            saveButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
            saveButton.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        placeRow.addTarget(self, action: #selector(placeTapped), for: .touchUpInside)
        tagFlow.onAdd = { [weak self] in self?.addTagPrompt() }
        tagFlow.onRemove = { [weak self] index in
            guard let self, self.tags.indices.contains(index) else { return }
            self.tags.remove(at: index)
            self.tagFlow.tags = self.tags
        }
        locationButton.addTarget(self, action: #selector(locationTapped), for: .touchUpInside)
        clearLocationButton.addTarget(self, action: #selector(clearLocationTapped), for: .touchUpInside)
    }

    private func makeSummaryCard() -> UIView {
        let card = SPCardView(style: .accent)
        let tile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 46, pointSize: 18)
        let title = UILabel()
        title.text = isRecovery ? "Recovered Recording" : "Recording Complete"
        title.font = SPFont.display(21, relativeTo: .title3)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true

        let meta = UILabel()
        meta.text = "\(SPFormat.dateTime(result.createdAt))\n\(SPFormat.duration(result.duration)) · \(result.quality.title) · \(result.quality.detail)"
        meta.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        meta.textColor = SPColor.secondaryInk
        meta.numberOfLines = 0
        meta.adjustsFontForContentSizeCategory = true

        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
        previewTime.font = SPFont.mono(9.5, weight: .regular, relativeTo: .caption2)
        previewTime.textColor = SPColor.secondaryInk
        previewTime.text = "Preview"
        previewTime.textAlignment = .center
        let previewStack = UIStackView(axis: .vertical, spacing: 3, alignment: .center)
        previewStack.addArrangedSubview(previewButton)
        previewStack.addArrangedSubview(previewTime)

        let textStack = UIStackView(axis: .vertical, spacing: 4)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(meta)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(tile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(previewStack)
        card.addContent(row, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        return card
    }

    private func makeCard(with content: UIView, insets: UIEdgeInsets = UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15)) -> UIView {
        let card = SPCardView(style: .surface)
        card.addContent(content, insets: insets)
        return card
    }

    private func makeTagsCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let label = UILabel()
        label.text = "Tags"
        label.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        label.textColor = SPColor.secondaryInk
        label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(tagFlow)

        let suggestionScroll = UIScrollView()
        suggestionScroll.translatesAutoresizingMaskIntoConstraints = false
        suggestionScroll.showsHorizontalScrollIndicator = false
        let suggestionStack = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
        suggestionStack.translatesAutoresizingMaskIntoConstraints = false
        for tag in SPSuggestions.tags {
            let chip = SPTagView(text: tag, symbol: "plus", color: SPColor.secondaryInk, background: SPColor.sunken)
            chip.onTap = { [weak self] in
                guard let self, !self.tags.contains(tag) else { return }
                self.tags = TagCodec.cleanedTags(self.tags + [tag])
                self.tagFlow.tags = self.tags
            }
            suggestionStack.addArrangedSubview(chip)
        }
        suggestionScroll.addSubview(suggestionStack)
        NSLayoutConstraint.activate([
            suggestionScroll.heightAnchor.constraint(equalToConstant: 27),
            suggestionStack.leadingAnchor.constraint(equalTo: suggestionScroll.contentLayoutGuide.leadingAnchor),
            suggestionStack.trailingAnchor.constraint(equalTo: suggestionScroll.contentLayoutGuide.trailingAnchor),
            suggestionStack.topAnchor.constraint(equalTo: suggestionScroll.contentLayoutGuide.topAnchor),
            suggestionStack.bottomAnchor.constraint(equalTo: suggestionScroll.contentLayoutGuide.bottomAnchor),
            suggestionStack.heightAnchor.constraint(equalTo: suggestionScroll.frameLayoutGuide.heightAnchor)
        ])
        stack.addArrangedSubview(suggestionScroll)
        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        return card
    }

    private func makeWeatherCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)
        stack.addArrangedSubview(weatherField)
        let quickScroll = UIScrollView()
        quickScroll.translatesAutoresizingMaskIntoConstraints = false
        quickScroll.showsHorizontalScrollIndicator = false
        let quickStack = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
        quickStack.translatesAutoresizingMaskIntoConstraints = false
        for weather in SPSuggestions.weather {
            let chip = SPTagView(text: weather, symbol: "plus", color: SPColor.secondaryInk, background: SPColor.sunken)
            chip.onTap = { [weak self] in
                guard let self else { return }
                let existing = self.weatherField.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.weatherField.text = existing.isEmpty ? weather : "\(existing), \(weather)"
            }
            quickStack.addArrangedSubview(chip)
        }
        quickScroll.addSubview(quickStack)
        NSLayoutConstraint.activate([
            quickScroll.heightAnchor.constraint(equalToConstant: 27),
            quickStack.leadingAnchor.constraint(equalTo: quickScroll.contentLayoutGuide.leadingAnchor),
            quickStack.trailingAnchor.constraint(equalTo: quickScroll.contentLayoutGuide.trailingAnchor),
            quickStack.topAnchor.constraint(equalTo: quickScroll.contentLayoutGuide.topAnchor),
            quickStack.bottomAnchor.constraint(equalTo: quickScroll.contentLayoutGuide.bottomAnchor),
            quickStack.heightAnchor.constraint(equalTo: quickScroll.frameLayoutGuide.heightAnchor)
        ])
        stack.addArrangedSubview(quickScroll)
        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        return card
    }

    private func makeLocationCard() -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 11)
        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Location (Optional)"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        let lock = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)))
        lock.tintColor = SPColor.moss
        header.addArrangedSubview(lock)
        stack.addArrangedSubview(header)

        coordinateLabel.font = SPFont.mono(12, weight: .medium, relativeTo: .subheadline)
        coordinateLabel.textColor = SPColor.ink
        coordinateLabel.adjustsFontForContentSizeCategory = true
        accuracyLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        accuracyLabel.textColor = SPColor.tertiaryInk
        accuracyLabel.numberOfLines = 0
        accuracyLabel.adjustsFontForContentSizeCategory = true
        coordinateStack.addArrangedSubview(coordinateLabel)
        coordinateStack.addArrangedSubview(accuracyLabel)
        coordinateStack.isHidden = true
        stack.addArrangedSubview(coordinateStack)

        for (index, value) in LocationPrecision.allCases.enumerated() where value != .none {
            let chip = SPFilterChip(title: value.title)
            chip.tag = index
            chip.addTarget(self, action: #selector(precisionTapped(_:)), for: .touchUpInside)
            precisionChips.append(chip)
            precisionStack.addArrangedSubview(chip)
        }
        precisionStack.addArrangedSubview(UIView())
        precisionStack.isHidden = true
        stack.addArrangedSubview(precisionStack)

        stack.addArrangedSubview(locationButton)
        clearLocationButton.isHidden = true
        stack.addArrangedSubview(clearLocationButton)

        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        return card
    }

    // MARK: - 预览

    private func configurePreview() {
        let loaded = preview.load(url: result.temporaryURL)
        previewButton.isEnabled = loaded
        if loaded {
            preview.onUpdate = { [weak self] current, duration, isPlaying in
                guard let self else { return }
                self.previewButton.isPlaying = isPlaying
                self.previewTime.text = "\(SPFormat.duration(current)) / \(SPFormat.duration(duration))"
            }
        }
    }

    @objc private func previewTapped() {
        preview.togglePlayback()
        SPHaptic.light()
    }

    // MARK: - 交互

    @objc private func placeTapped() {
        preview.pause()
        let picker = PlacePickerViewController(selectedPlaceID: placeID, allowNone: true) { [weak self] place in
            guard let self else { return }
            self.placeID = place?.id
            self.placeName = place?.name
            self.placeRow.value = place?.name ?? "Not Set"
        }
        let nav = UINavigationController(rootViewController: picker)
        SPStyle.applyNavigationAppearance(to: nav)
        present(nav, animated: true)
    }

    private func addTagPrompt() {
        guard tags.count < 12 else {
            presentAlert(title: "You can add up to 12 tags.")
            return
        }
        let alert = UIAlertController(title: "Add Tag", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. morning, quiet, waterside"
            field.font = SPFont.text(15)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self, let value = alert?.textFields?.first?.text else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !self.tags.contains(trimmed) else { return }
            self.tags = TagCodec.cleanedTags(self.tags + [trimmed])
            self.tagFlow.tags = self.tags
        })
        present(alert, animated: true)
    }

    @objc private func locationTapped() {
        preview.pause()
        locationButton.isEnabled = false
        locationButton.title = "Getting Current Location…"
        LocationService.shared.requestCurrentLocation { [weak self] result in
            guard let self else { return }
            self.locationButton.isEnabled = true
            self.locationButton.title = "Update Location"
            switch result {
            case .success(let location):
                self.coordinate = Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                self.precision = .precise
                self.updateLocationUI()
                SPHaptic.success()
            case .failure(let error):
                self.presentLocationError(error)
            }
        }
    }

    private func updateLocationUI() {
        let hasCoordinate = coordinate != nil
        coordinateStack.isHidden = !hasCoordinate
        precisionStack.isHidden = !hasCoordinate
        clearLocationButton.isHidden = !hasCoordinate
        for chip in precisionChips {
            let value = [LocationPrecision.approximate, .precise][safe: chip.tag] ?? .precise
            chip.selectedState = value == precision
        }
        if let coordinate {
            coordinateLabel.text = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
            accuracyLabel.text = precision == .approximate
                ? "Saved as an approximate location (to about 1 km)"
                : "Saved as a precise location"
        }
    }

    @objc private func precisionTapped(_ sender: SPFilterChip) {
        let options: [LocationPrecision] = [.approximate, .precise]
        guard options.indices.contains(sender.tag) else { return }
        precision = options[sender.tag]
        updateLocationUI()
        SPHaptic.selection()
    }

    @objc private func clearLocationTapped() {
        coordinate = nil
        precision = .none
        updateLocationUI()
    }

    private func presentLocationError(_ error: LocationError) {
        let alert = UIAlertController(title: "Unable to Get Location", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        if case .permissionDenied = error {
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        }
        present(alert, animated: true)
    }

    // MARK: - 保存与放弃

    @objc private func cancelTapped() {
        preview.pause()
        presentConfirm(
            title: "Discard This Recording?",
            message: "The unsaved recording will be deleted.",
            destructiveTitle: "Discard"
        ) { [weak self] in
            guard let self else { return }
            self.deleteTemporaryFile()
            self.onDiscard?()
        }
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        let title = titleField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            titleField.showError("Enter a title.")
            scrollView.setContentOffset(.zero, animated: true)
            SPHaptic.error()
            return
        }
        preview.pause()
        isSaving = true
        saveButton.isEnabled = false
        let overlay = SPLoadingOverlay(message: "Saving recording…")
        overlay.show(in: view)

        let draft = RecordingSaveDraft(
            title: title,
            temporaryAudioURL: result.temporaryURL,
            placeID: placeID,
            tags: tags,
            note: noteView.text,
            weather: weatherField.text,
            coordinate: coordinate,
            precision: coordinate == nil ? .none : precision,
            duration: result.duration,
            sampleRate: result.sampleRate,
            channelCount: result.channelCount,
            deviceModel: DeviceInfo.displayName,
            markers: result.markers,
            createdAt: result.createdAt
        )

        do {
            let record = try library.saveRecording(draft)
            RecordingDraftStore.shared.clear()
            SPHaptic.success()
            overlay.hide()
            onSaved?(record)
        } catch {
            isSaving = false
            saveButton.isEnabled = true
            overlay.hide()
            presentError(error, title: "Could Not Save Recording")
        }
    }

    private func deleteTemporaryFile() {
        preview.pause()
        try? FileManager.default.removeItem(at: result.temporaryURL)
        RecordingDraftStore.shared.clear()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
