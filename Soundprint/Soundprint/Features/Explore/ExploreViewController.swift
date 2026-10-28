//
//  ExploreViewController.swift
//  Soundprint
//
//  首页：快速录音、最近录音、最近地点与本地存储概览。
//

import UIKit

final class ExploreViewController: SPViewController {
    private let library = LibraryService.shared
    private let storage = StorageManager.shared
    private let selection = CompareSelectionStore.shared

    private let headerView = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 26)
    private let dateLabel = UILabel()
    private var storageSummary: SPStorageSummaryView?
    private var reloadWorkItem: DispatchWorkItem?
    private var hasPulsedRecord = false

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHeader()
        buildScroll()
        observe()
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        rebuild()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    // MARK: - 顶部

    private func buildHeader() {
        view.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = UILabel()
        wordmark.text = "Soundprint"
        wordmark.font = SPFont.wordmark(32)
        wordmark.textColor = SPColor.ink
        wordmark.adjustsFontForContentSizeCategory = true

        let archive = UILabel()
        archive.text = "Sound Archive"
        archive.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        archive.textColor = SPColor.accent
        archive.adjustsFontForContentSizeCategory = true

        dateLabel.text = SPFormat.fullDate.string(from: Date())
        dateLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        dateLabel.textColor = SPColor.tertiaryInk
        dateLabel.adjustsFontForContentSizeCategory = true

        let wordStack = UIStackView(axis: .vertical, spacing: 0)
        wordStack.addArrangedSubview(wordmark)
        wordStack.addArrangedSubview(archive)

        let searchButton = SPIconButton(symbol: "magnifyingglass", accessibilityLabel: "Search", style: .filled)
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        let topRow = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        topRow.addArrangedSubview(wordStack)
        topRow.addArrangedSubview(UIView())
        topRow.addArrangedSubview(searchButton)

        let dateRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = SPColor.hairline
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        line.widthAnchor.constraint(equalToConstant: 22).isActive = true
        dateRow.addArrangedSubview(line)
        dateRow.addArrangedSubview(dateLabel)
        dateRow.addArrangedSubview(UIView())

        let stack = UIStackView(axis: .vertical, spacing: 10)
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(dateRow)
        headerView.addSubview(stack)
        stack.pinEdges(to: headerView)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
    }

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
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func observe() {
        for name in [SPNotification.libraryDidChange, SPNotification.analysisDidChange, SPNotification.storageDidChange] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(dataChanged),
                name: name,
                object: nil
            )
        }
    }

    @objc private func dataChanged() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.rebuild() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    // MARK: - 内容

    private func rebuild() {
        let offset = scrollView.contentOffset
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        storageSummary = nil

        let allRecordings = library.fetchRecordings()
        let recent = Array(allRecordings.prefix(3))
        let places = library.recentPlaces(limit: 6)
        dateLabel.text = SPFormat.fullDate.string(from: Date())

        contentStack.addArrangedSubview(makeHero(lastRecording: allRecordings.first))
        contentStack.addArrangedSubview(makeRecentRecordings(recent, totalCount: allRecordings.count))
        if allRecordings.count >= 2 {
            contentStack.addArrangedSubview(makeCompareCallout())
        }
        contentStack.addArrangedSubview(makeRecentPlaces(places))
        contentStack.addArrangedSubview(makeStorageCard())
        contentStack.addArrangedSubview(makePrivacyFooter())

        refreshStorageStats()

        view.layoutIfNeeded()
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        if offset.y > 0 {
            scrollView.setContentOffset(CGPoint(x: 0, y: min(offset.y, maxOffset)), animated: false)
        }
    }

    private func makeHero(lastRecording: RecordingEntity?) -> UIView {
        let card = SPCardView(style: .accent)
        let backdrop = SPWaveBackdropView()
        card.addSubview(backdrop)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: card.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        let kicker = UILabel()
        kicker.attributedText = NSAttributedString(
            string: "Record Now",
            attributes: [
                .font: SPFont.text(9.5, weight: .semibold, relativeTo: .caption2),
                .foregroundColor: SPColor.accent,
                .kern: 1.5
            ]
        )
        let title = UILabel()
        title.text = lastRecording == nil ? "Keep the first sound,\nfor later." : "Keep the sound of now,\nfor later."
        title.font = SPFont.display(28, relativeTo: .title1)
        title.textColor = SPColor.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            title.maximumContentSizeCategory = .accessibilityMedium
        }
        let detail = UILabel()
        if let lastRecording {
            detail.text = "Last recorded \(SPFormat.relativeDate(lastRecording.createdAt)).\nRecord again to follow how this place changes."
        } else {
            detail.text = "Record a place's sound on different days.\nA notebook for noticing the small changes."
        }
        detail.font = SPFont.text(11.5, weight: .regular, relativeTo: .footnote)
        detail.textColor = SPColor.secondaryInk
        detail.numberOfLines = 0
        detail.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(axis: .vertical, spacing: 8)
        textStack.addArrangedSubview(kicker)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(detail)

        let recordButton = SPRecordButton()
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)

        let row = UIStackView(axis: .horizontal, spacing: 14, alignment: .center)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(recordButton)
        card.addContent(row, insets: UIEdgeInsets(top: 20, left: 19, bottom: 20, right: 17))

        if !hasPulsedRecord {
            hasPulsedRecord = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                recordButton.pulseIfNeeded()
            }
        }
        return card
    }

    private func makeRecentRecordings(_ recordings: [RecordingEntity], totalCount: Int) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 12)
        let header = SPSectionHeaderView(
            title: "Recent Recordings",
            subtitle: totalCount > 0 ? "\(totalCount) recordings" : nil,
            actionTitle: totalCount > 3 ? "See All" : (totalCount > 0 ? "See All" : nil),
            action: totalCount > 0 ? { [weak self] in self?.openAllRecordings() } : nil
        )
        section.addArrangedSubview(header)

        if recordings.isEmpty {
            let card = SPCardView(style: .surface)
            let empty = SPEmptyStateView(
                symbol: "waveform",
                title: "No Recordings Yet",
                message: "A quiet room, or the world outside your window. Start with a sound you noticed.",
                actionTitle: "Start Your First Recording",
                action: { [weak self] in self?.recordTapped() }
            )
            card.addContent(empty, insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
            section.addArrangedSubview(card)
        } else {
            for record in recordings {
                let card = SPRecordingCardView()
                card.configure(
                    with: record,
                    showPlace: true,
                    dateText: "\(SPFormat.relativeDate(record.createdAt)) \(SPFormat.time.string(from: record.createdAt))"
                )
                card.onTap = { [weak self] in self?.open(record) }
                section.addArrangedSubview(card)
            }
        }
        return section
    }

    private func makeCompareCallout() -> UIView {
        let card = SPCardView(style: .surface)
        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        card.accessibilityLabel = "Listen and Compare Recordings"
        card.accessibilityHint = "Opens the comparison screen"

        let art = SPOrbitalArtView(variant: .dual)
        art.isUserInteractionEnabled = false
        art.widthAnchor.constraint(equalToConstant: 96).isActive = true
        art.heightAnchor.constraint(equalToConstant: 66).isActive = true

        let title = UILabel()
        title.text = "Listen and Compare Recordings"
        title.font = SPFont.display(19, relativeTo: .headline)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "How a place changes, in waveforms and numbers."
        detail.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        detail.textColor = SPColor.secondaryInk
        detail.adjustsFontForContentSizeCategory = true
        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(detail)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 8).isActive = true

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(art)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(chevron)
        card.addContent(row, insets: UIEdgeInsets(top: 15, left: 16, bottom: 15, right: 16))
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(compareTapped)))
        return card
    }

    private func makeRecentPlaces(_ places: [PlaceEntity]) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 12)
        let header = SPSectionHeaderView(
            title: "Recent Places",
            subtitle: places.isEmpty ? nil : "Sound over time",
            actionTitle: places.isEmpty ? nil : "See All",
            action: places.isEmpty ? nil : { [weak self] in self?.openAllPlaces() }
        )
        section.addArrangedSubview(header)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        let stack = UIStackView(axis: .horizontal, spacing: 10, alignment: .fill)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 150),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        for place in places {
            let card = SPPlaceMiniCardView(frame: .zero)
            card.configure(with: place)
            card.onTap = { [weak self] in self?.open(place) }
            stack.addArrangedSubview(card)
        }
        let add = makeAddPlaceCard()
        stack.addArrangedSubview(add)
        section.addArrangedSubview(scroll)
        return section
    }

    private func makeAddPlaceCard() -> UIView {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = SPColor.surface.withAlphaComponent(0.55)
        control.layer.cornerRadius = 18
        control.layer.cornerCurve = .continuous
        control.layer.borderWidth = 1
        control.layer.borderColor = SPColor.hairline.cgColor
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = "Create a new place"
        control.addTarget(self, action: #selector(addPlaceTapped), for: .touchUpInside)

        let plus = SPIconTile(symbol: "plus", color: SPColor.accent, size: 36, pointSize: 14)
        let title = UILabel()
        title.text = "New Place"
        title.font = SPFont.display(16, relativeTo: .headline)
        title.textColor = SPColor.secondaryInk
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "Follow a place over time"
        detail.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        detail.textColor = SPColor.tertiaryInk
        detail.textAlignment = .center
        let stack = UIStackView(axis: .vertical, spacing: 8, alignment: .center)
        stack.addArrangedSubview(plus)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(detail)
        stack.isUserInteractionEnabled = false
        control.addSubview(stack)
        stack.pinEdges(to: control, insets: UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10))
        return control
    }

    private func makeStorageCard() -> UIView {
        let card = SPCardView(style: .surface)
        let summary = SPStorageSummaryView()
        storageSummary = summary
        let manage = SPTextButton(title: "Manage")
        manage.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        header.addArrangedSubview(summary)
        header.addArrangedSubview(manage)
        card.addContent(header, insets: UIEdgeInsets(top: 15, left: 16, bottom: 15, right: 10))
        return card
    }

    private func makePrivacyFooter() -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: 5, alignment: .center)
        let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        icon.tintColor = SPColor.moss
        let label = UILabel()
        label.text = "Recordings stay on this device. There's no cloud sync."
        label.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        label.textColor = SPColor.tertiaryInk
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        return stack
    }

    private func refreshStorageStats() {
        storage.stats { [weak self] stats in
            guard let self, let summary = self.storageSummary, summary.window != nil else { return }
            summary.configure(stats: stats)
        }
    }

    // MARK: - 操作

    @objc private func recordTapped() {
        SPHaptic.medium()
        RecordingFlowCoordinator.shared.present(from: self, placeID: nil) { [weak self] record in
            guard let self else { return }
            self.rebuild()
            if let record {
                let detail = RecordingDetailViewController(recordingID: record.id)
                self.navigationController?.pushViewController(detail, animated: true)
                SPToast.show("Recording saved", in: self.view)
            }
        }
    }

    @objc private func searchTapped() {
        let search = SearchViewController(mode: .general)
        let nav = UINavigationController(rootViewController: search)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func openAllRecordings() {
        let controller = RecordingsListViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openAllPlaces() {
        tabBarController?.selectedIndex = 1
    }

    @objc private func compareTapped() {
        tabBarController?.selectedIndex = 2
    }

    @objc private func addPlaceTapped() {
        let editor = PlaceEditorViewController(mode: .create) { [weak self] place, _ in
            guard let self else { return }
            self.rebuild()
            let detail = PlaceDetailViewController(placeID: place.id)
            self.navigationController?.pushViewController(detail, animated: true)
        }
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func openSettings() {
        tabBarController?.selectedIndex = 3
    }

    private func open(_ record: RecordingEntity) {
        let detail = RecordingDetailViewController(recordingID: record.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func open(_ place: PlaceEntity) {
        let detail = PlaceDetailViewController(placeID: place.id)
        navigationController?.pushViewController(detail, animated: true)
    }
}
