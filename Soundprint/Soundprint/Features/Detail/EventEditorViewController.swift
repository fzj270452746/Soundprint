//
//  EventEditorViewController.swift
//  Soundprint
//
//  手动声音事件标注。所有事件都是用户观察，不伪装成自动识别结论。
//

import UIKit

final class EventEditorViewController: SPViewController {
    private let record: RecordingEntity
    private let event: SoundEventEntity?
    private let defaultTime: Double
    private let initialEndTime: Double?
    private let initialTitle: String?
    private let initialKind: EventKind?
    private let onSaved: () -> Void
    private let library = LibraryService.shared

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 16)
    private let bottomBar = UIView()
    private let saveButton = SPButton(title: "Save Event", symbol: "checkmark", style: .primary)
    private let kindPicker = SPEventKindPicker()
    private let titleField = SPTextFieldView(title: "Event Name", placeholder: "e.g. a distant railway crossing, birdsong")
    private let noteView = SPTextView(title: "Notes", placeholder: "How it sounds, its direction, anything you noticed.", maxLength: 300)
    private let startSlider: SPTimeSliderView
    private let endSlider: SPTimeSliderView
    private let endToggle: SPToggleRow
    private var selectedKind: EventKind = .other

    init(
        record: RecordingEntity,
        event: SoundEventEntity?,
        defaultTime: Double,
        initialEndTime: Double? = nil,
        initialTitle: String? = nil,
        initialKind: EventKind? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.record = record
        self.event = event
        self.defaultTime = defaultTime
        self.initialEndTime = initialEndTime
        self.initialTitle = initialTitle
        self.initialKind = initialKind
        self.onSaved = onSaved
        self.startSlider = SPTimeSliderView(
            title: "Start Time",
            value: event?.startTime ?? defaultTime,
            duration: record.duration
        )
        let fallbackEnd = min(record.duration, max(defaultTime + 2, 2))
        let endValue = event?.endTimeValue ?? initialEndTime ?? fallbackEnd
        self.endSlider = SPTimeSliderView(
            title: "End Time",
            value: endValue,
            duration: record.duration
        )
        self.endToggle = SPToggleRow(
            title: "Record End Time",
            subtitle: "Knowing how long the sound lasted makes it easier to find in comparisons.",
            isOn: event?.endTimeValue != nil || initialEndTime != nil,
            symbol: "timer"
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = event == nil ? "Add Sound Event" : "Edit Event"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        buildInterface()
        populate()
        isModalInPresentation = true
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let kindCard = SPCardView(style: .surface)
        let kindStack = UIStackView(axis: .vertical, spacing: 10)
        let kindLabel = UILabel()
        kindLabel.text = "Kind"
        kindLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        kindLabel.textColor = SPColor.secondaryInk
        kindLabel.adjustsFontForContentSizeCategory = true
        kindStack.addArrangedSubview(kindLabel)
        kindStack.addArrangedSubview(kindPicker)
        kindCard.addContent(kindStack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(kindCard)

        let titleCard = SPCardView(style: .surface)
        titleCard.addContent(titleField, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(titleCard)

        let timeCard = SPCardView(style: .surface)
        let timeStack = UIStackView(axis: .vertical, spacing: 14)
        timeStack.addArrangedSubview(startSlider)
        timeStack.addArrangedSubview(SPDivider())
        timeStack.addArrangedSubview(endToggle)
        timeStack.addArrangedSubview(endSlider)
        timeCard.addContent(timeStack, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(timeCard)

        let noteCard = SPCardView(style: .surface)
        noteCard.addContent(noteView, insets: UIEdgeInsets(top: 17, left: 15, bottom: 17, right: 15))
        contentStack.addArrangedSubview(noteCard)

        if event != nil {
            let deleteButton = SPButton(title: "Delete Event", symbol: "trash", style: .danger)
            deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
            contentStack.addArrangedSubview(deleteButton)
        }

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

        kindPicker.onChange = { [weak self] kind in self?.selectedKind = kind }
        endToggle.onChange = { [weak self] isOn in
            guard let self else { return }
            self.endSlider.alpha = isOn ? 1 : 0.38
            self.endSlider.isUserInteractionEnabled = isOn
            if isOn, self.endSlider.value < self.startSlider.value {
                self.endSlider.value = min(self.record.duration, self.startSlider.value + 1)
            }
        }
        startSlider.onChange = { [weak self] value in
            guard let self, self.endToggle.toggle.isOn, self.endSlider.value < value else { return }
            self.endSlider.value = min(self.record.duration, value + 0.5)
        }
        endSlider.alpha = endToggle.toggle.isOn ? 1 : 0.38
        endSlider.isUserInteractionEnabled = endToggle.toggle.isOn
    }

    private func populate() {
        let kind = event?.kind ?? initialKind ?? .other
        selectedKind = kind
        kindPicker.select(kind, notify: false)
        titleField.text = event?.title ?? initialTitle ?? ""
        noteView.text = event?.note ?? ""
        titleField.textField.placeholder = selectedKind.title
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let start = startSlider.value
        var end: Double?
        if endToggle.toggle.isOn {
            let endValue = endSlider.value
            guard endValue > start + 0.05 else {
                presentAlert(title: "Check the End Time", message: "The end time must be later than the start time.")
                return
            }
            end = endValue
        }
        do {
            if let event {
                try library.updateEvent(
                    event,
                    kind: selectedKind,
                    title: titleField.text,
                    startTime: start,
                    endTime: end,
                    note: noteView.text
                )
            } else {
                try library.addEvent(
                    to: record,
                    kind: selectedKind,
                    title: titleField.text,
                    startTime: start,
                    endTime: end,
                    note: noteView.text
                )
            }
            SPHaptic.success()
            dismiss(animated: true) { [onSaved] in onSaved() }
        } catch {
            presentError(error)
        }
    }

    @objc private func deleteTapped() {
        guard let event else { return }
        presentConfirm(
            title: "Delete This Event?",
            message: "The recording itself won't be deleted.",
            destructiveTitle: "Delete"
        ) { [weak self] in
            guard let self else { return }
            do {
                try self.library.deleteEvent(event)
                self.dismiss(animated: true) { [onSaved = self.onSaved] in onSaved() }
            } catch {
                self.presentError(error)
            }
        }
    }
}
