//
//  RecordingEditViewController.swift
//  Soundprint
//
//  编辑录音的标题、地点、标签、天气与观察笔记。原始音频保持不变。
//

import UIKit

final class RecordingEditViewController: SPViewController {
    private let record: RecordingEntity
    private let onSaved: () -> Void
    private let library = LibraryService.shared

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 16)
    private let bottomBar = UIView()
    private let saveButton = SPButton(title: "Save Changes", symbol: "checkmark", style: .primary)
    private let titleField = SPTextFieldView(title: "Title", placeholder: "Recording name", isRequired: true)
    private let placeRow = SPMenuRow(title: "Place", value: nil, symbol: "mappin.and.ellipse")
    private let tagFlow = SPTagFlowView()
    private let weatherField = SPTextFieldView(title: "Weather & Environment", placeholder: "e.g. clear, light wind", symbol: "cloud.sun")
    private let noteView = SPTextView(title: "Observation Notes", placeholder: "Sounds you heard, changes you noticed, conditions while recording.", maxLength: 1200)

    private var tags: [String] = []
    private var selectedPlaceID: UUID?
    private var selectedPlaceName: String?

    init(record: RecordingEntity, onSaved: @escaping () -> Void) {
        self.record = record
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Recording"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        titleField.text = record.title
        noteView.text = record.note ?? ""
        weatherField.text = record.weather ?? ""
        tags = record.tags
        tagFlow.tags = tags
        tagFlow.showsAddButton = true
        tagFlow.removable = true
        selectedPlaceID = record.place?.id
        selectedPlaceName = record.place?.name
        placeRow.value = selectedPlaceName ?? "None"
        buildInterface()
        isModalInPresentation = true
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let titleCard = SPCardView(style: .surface)
        titleCard.addContent(titleField, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(titleCard)

        let placeCard = SPCardView(style: .surface)
        placeRow.addTarget(self, action: #selector(placeTapped), for: .touchUpInside)
        placeCard.addContent(placeRow, insets: UIEdgeInsets(top: 13, left: 13, bottom: 13, right: 13))
        contentStack.addArrangedSubview(placeCard)

        let tagCard = SPCardView(style: .surface)
        let tagTitle = UILabel()
        tagTitle.text = "Tags"
        tagTitle.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        tagTitle.textColor = SPColor.secondaryInk
        tagTitle.adjustsFontForContentSizeCategory = true
        let tagStack = UIStackView(axis: .vertical, spacing: 10)
        tagStack.addArrangedSubview(tagTitle)
        tagStack.addArrangedSubview(tagFlow)
        tagCard.addContent(tagStack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(tagCard)

        let weatherCard = SPCardView(style: .surface)
        let weatherStack = UIStackView(axis: .vertical, spacing: 10)
        weatherStack.addArrangedSubview(weatherField)
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
        weatherStack.addArrangedSubview(quickScroll)
        weatherCard.addContent(weatherStack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(weatherCard)

        let noteCard = SPCardView(style: .surface)
        noteCard.addContent(noteView, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(noteCard)

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

        tagFlow.onAdd = { [weak self] in self?.addTagPrompt() }
        tagFlow.onRemove = { [weak self] index in
            guard let self, self.tags.indices.contains(index) else { return }
            self.tags.remove(at: index)
            self.tagFlow.tags = self.tags
        }
    }

    @objc private func placeTapped() {
        let picker = PlacePickerViewController(selectedPlaceID: selectedPlaceID, allowNone: true) { [weak self] place in
            guard let self else { return }
            self.selectedPlaceID = place?.id
            self.selectedPlaceName = place?.name
            self.placeRow.value = place?.name ?? "None"
        }
        let nav = UINavigationController(rootViewController: picker)
        SPStyle.applyNavigationAppearance(to: nav)
        present(nav, animated: true)
    }

    private func addTagPrompt() {
        guard tags.count < 12 else {
            presentAlert(title: "Up to 12 Tags")
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

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let title = titleField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            titleField.showError("Enter a title.")
            return
        }
        let draft = RecordingEditDraft(
            title: title,
            placeID: selectedPlaceID,
            tags: tags,
            note: noteView.text,
            weather: weatherField.text,
            coordinate: record.coordinate,
            precision: record.hasCoordinates ? .precise : .none,
            markers: nil,
            createdAt: nil
        )
        do {
            try library.updateRecording(record, with: draft)
            SPHaptic.success()
            dismiss(animated: true) { [onSaved] in onSaved() }
        } catch {
            presentError(error)
        }
    }
}
