//
//  CompareViewController.swift
//  Soundprint
//
//  对比入口：选择 A/B 录音。历史变化是产品的核心价值。
//

import UIKit

final class CompareViewController: SPViewController {
    private let library = LibraryService.shared
    private let selection = CompareSelectionStore.shared
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 18)
    private var recordA: RecordingEntity?
    private var recordB: RecordingEntity?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildBase()
        observe()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private func buildBase() {
        let header = UIStackView(axis: .vertical, spacing: 3)
        let title = UILabel()
        title.text = "Compare"
        title.font = SPFont.display(34, relativeTo: .largeTitle)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        let subtitle = UILabel()
        subtitle.text = "Compare the same place at different times."
        subtitle.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
        subtitle.textColor = SPColor.tertiaryInk
        subtitle.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(subtitle)

        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
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
    }

    @objc private func dataChanged() {
        reload()
    }

    private func reload() {
        recordA = selection.recordingAID.flatMap { library.fetchRecording(id: $0) }
        recordB = selection.recordingBID.flatMap { library.fetchRecording(id: $0) }
        if recordA == nil { selection.recordingAID = nil }
        if recordB == nil { selection.recordingBID = nil }
        rebuild()
    }

    private func rebuild() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let total = library.recordingsCount()
        if total < 2 {
            let empty = SPEmptyStateView(
                symbol: "rectangle.split.2x1",
                title: "Comparison Requires Two Recordings",
                message: "Recording the same place on different days lets you compare waveforms and frequency changes side by side.",
                actionTitle: "Start Recording",
                action: { [weak self] in
                    self?.startRecording()
                }
            )
            let card = SPCardView(style: .surface)
            card.addContent(empty, insets: UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10))
            contentStack.addArrangedSubview(card)
            contentStack.addArrangedSubview(makeConditionsNote())
            return
        }

        let slotA = CompareSlotView(letter: "A", color: SPColor.accent, record: recordA)
        slotA.onTap = { [weak self] in self?.pickSlot(.a) }
        contentStack.addArrangedSubview(slotA)

        let swapButton = UIButton(type: .system)
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        swapButton.setImage(UIImage(systemName: "arrow.up.arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        swapButton.setTitle("  Swap A and B", for: .normal)
        swapButton.titleLabel?.font = SPFont.text(11, weight: .medium, relativeTo: .caption1)
        swapButton.tintColor = SPColor.secondaryInk
        swapButton.addTarget(self, action: #selector(swapTapped), for: .touchUpInside)
        let swapRow = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
        swapRow.addArrangedSubview(UIView())
        swapRow.addArrangedSubview(swapButton)
        swapRow.addArrangedSubview(UIView())
        contentStack.addArrangedSubview(swapRow)

        let slotB = CompareSlotView(letter: "B", color: SPColor.moss, record: recordB)
        slotB.onTap = { [weak self] in self?.pickSlot(.b) }
        contentStack.addArrangedSubview(slotB)

        let startButton = SPButton(title: "Compare", symbol: "arrow.right", style: .primary)
        startButton.isEnabled = recordA != nil && recordB != nil && recordA?.id != recordB?.id
        startButton.addTarget(self, action: #selector(startCompareTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(startButton)

        if let a = recordA, let b = recordB {
            contentStack.addArrangedSubview(makeSelectionSummary(a: a, b: b))
        } else {
            contentStack.addArrangedSubview(SPInfoBanner(
                title: "Select Two Recordings",
                message: "The closer the recording conditions, the easier it is to read environmental change.",
                tone: .neutral
            ))
        }
        contentStack.addArrangedSubview(makeConditionsNote())
    }

    private func makeSelectionSummary(a: RecordingEntity, b: RecordingEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 11)
        if a.id == b.id {
            stack.addArrangedSubview(SPInfoBanner(
                title: "The Same Recording Is Selected",
                message: "Choose a different recording for A and B.",
                tone: .warning
            ))
        } else {
            let samePlace = a.place?.id != nil && a.place?.id == b.place?.id
            let title = UILabel()
            title.text = samePlace ? "Recordings from the Same Place" : "Recordings from Different Places"
            title.font = SPFont.text(13, weight: .semibold, relativeTo: .footnote)
            title.textColor = samePlace ? SPColor.moss : SPColor.amber
            title.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(title)
            let detail = UILabel()
            if let place = a.place?.name, samePlace {
                detail.text = "Two recordings from \(place). The closer the recording conditions, the easier the comparison."
            } else {
                detail.text = "Because the places differ, volume differences include factors other than the environment."
            }
            detail.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
            detail.textColor = SPColor.secondaryInk
            detail.numberOfLines = 0
            detail.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(detail)
        }
        card.addContent(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    private func makeConditionsNote() -> UIView {
        let card = SPCardView(style: .sunken)
        let stack = UIStackView(axis: .vertical, spacing: 7)
        let title = UILabel()
        title.text = "For a Better Comparison"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        let body = UILabel()
        body.text = "Record at the same place, distance, and device settings. RMS and peak are signal values that include microphone gain, not calibrated sound pressure levels."
        body.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        body.textColor = SPColor.tertiaryInk
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body)
        card.addContent(stack, insets: UIEdgeInsets(top: 13, left: 14, bottom: 13, right: 14))
        return card
    }

    // MARK: - 操作

    private enum Slot { case a, b }

    private func pickSlot(_ slot: Slot) {
        let chosenID = slot == .a ? recordA?.id : recordB?.id
        let excluded = slot == .a ? recordB?.id : recordA?.id
        let picker = RecordingPickerViewController(
            slotTitle: slot == .a ? "Select Recording A" : "Select Recording B",
            selectedID: chosenID,
            excludedID: excluded
        ) { [weak self] record in
            guard let self else { return }
            if slot == .a {
                self.selection.recordingAID = record.id
            } else {
                self.selection.recordingBID = record.id
            }
            self.reload()
        }
        let nav = UINavigationController(rootViewController: picker)
        SPStyle.applyNavigationAppearance(to: nav)
        present(nav, animated: true)
    }

    @objc private func swapTapped() {
        guard recordA != nil || recordB != nil else { return }
        selection.swap()
        SPHaptic.selection()
        reload()
    }

    @objc private func startCompareTapped() {
        guard let a = recordA, let b = recordB, a.id != b.id else { return }
        let workspace = CompareWorkspaceViewController(recordingAID: a.id, recordingBID: b.id)
        workspace.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(workspace, animated: true)
    }

    private func startRecording() {
        RecordingFlowCoordinator.shared.present(from: self, placeID: nil) { [weak self] record in
            guard let self else { return }
            self.reload()
            if record != nil {
                SPToast.show("Recording saved", in: self.view)
            }
        }
    }
}

// MARK: - A/B 选择槽

private final class CompareSlotView: UIControl {
    var onTap: (() -> Void)?
    private let letter: String
    private let color: UIColor
    private let record: RecordingEntity?
    private let dashedBorder = CAShapeLayer()

    init(letter: String, color: UIColor, record: RecordingEntity?) {
        self.letter = letter
        self.color = color
        self.record = record
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = record == nil ? SPColor.surface.withAlphaComponent(0.6) : SPColor.surface
        layer.cornerRadius = SPMetric.cardRadius
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        if record == nil {
            layer.addSublayer(dashedBorder)
            buildEmpty()
        } else {
            buildFilled()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedBorder.frame = bounds
        dashedBorder.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: SPMetric.cardRadius
        ).cgPath
        dashedBorder.strokeColor = SPColor.strongHairline.withAlphaComponent(0.75).cgColor
        dashedBorder.fillColor = UIColor.clear.cgColor
        dashedBorder.lineWidth = 1
        dashedBorder.lineDashPattern = [5, 4]
    }

    private func buildEmpty() {
        let badge = makeBadge()
        let title = UILabel()
        title.text = "Select Recording \(letter)"
        title.font = SPFont.text(15, weight: .semibold, relativeTo: .body)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "Tap to choose from the library"
        detail.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        detail.textColor = SPColor.tertiaryInk
        detail.adjustsFontForContentSizeCategory = true
        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(detail)
        let plus = UIImageView(image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)))
        plus.tintColor = SPColor.tertiaryInk
        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(badge)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(plus)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        accessibilityLabel = "Select Recording \(letter)"
    }

    private func buildFilled() {
        guard let record else { return }
        let badge = makeBadge()
        let title = UILabel()
        title.text = record.title
        title.font = SPFont.text(16, weight: .semibold, relativeTo: .body)
        title.textColor = SPColor.ink
        title.numberOfLines = 1
        title.adjustsFontForContentSizeCategory = true
        let meta = UILabel()
        meta.text = "\(record.place?.name ?? "Unassigned") · \(SPFormat.shortDate.string(from: record.createdAt)) · \(SPFormat.duration(record.duration))"
        meta.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        meta.textColor = SPColor.tertiaryInk
        meta.adjustsFontForContentSizeCategory = true
        meta.numberOfLines = 1
        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(meta)

        let change = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        change.tintColor = SPColor.tertiaryInk

        let wave = SPWaveformView()
        wave.cache = AudioAnalysisService.shared.waveform(for: record)
        wave.duration = record.duration
        wave.progress = 0
        wave.showsPlayhead = false
        wave.isUserInteractionEnabled = false
        wave.tint = SPColor.secondaryInk
        wave.playedTint = SPColor.secondaryInk
        wave.heightAnchor.constraint(equalToConstant: 34).isActive = true
        wave.accessibilityElementsHidden = true

        let topRow = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        topRow.addArrangedSubview(badge)
        topRow.addArrangedSubview(textStack)
        topRow.addArrangedSubview(change)
        let stack = UIStackView(axis: .vertical, spacing: 9)
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(wave)
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: 15, bottom: 12, right: 15))
        accessibilityLabel = "Recording \(letter), \(record.title), \(record.place?.name ?? "Unassigned")"
        accessibilityHint = "Change"
    }

    private func makeBadge() -> UIView {
        let badge = UILabel()
        badge.text = letter
        badge.font = SPFont.mono(13, weight: .bold, relativeTo: .subheadline)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = color
        badge.layer.cornerRadius = 13
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 26).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return badge
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : 1 }
    }

    @objc private func tapped() {
        onTap?()
    }
}
