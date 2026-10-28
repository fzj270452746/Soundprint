//
//  PlaceDetailViewController.swift
//  Soundprint
//
//  地点档案页：位置、统计、录音时间线与对比入口。
//

import MapKit
import UIKit

final class PlaceDetailViewController: SPViewController {
    private let placeID: UUID
    private let library = LibraryService.shared
    private var place: PlaceEntity?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 22)
    private var mapView: MKMapView?
    private var reloadWorkItem: DispatchWorkItem?

    init(placeID: UUID) {
        self.placeID = placeID
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Place"
        view.backgroundColor = SPColor.paper
        buildScroll()
        observe()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reload()
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
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
        scrollView.contentInset.bottom = 20
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.libraryDidChange,
            object: nil
        )
    }

    @objc private func dataChanged() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - 刷新

    private func reload() {
        guard let loaded = library.fetchPlace(id: placeID) else {
            navigationController?.popViewController(animated: true)
            return
        }
        place = loaded
        navigationItem.title = loaded.name
        configureMenu(for: loaded)
        rebuildContent(place: loaded)
    }

    private func configureMenu(for place: PlaceEntity) {
        let edit = UIAction(title: "Edit Place", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.editPlace(place)
        }
        let archiveTitle = place.archivedAt == nil ? "Archive" : "Unarchive"
        let archiveSymbol = place.archivedAt == nil ? "archivebox" : "tray.and.arrow.up"
        let archive = UIAction(title: archiveTitle, image: UIImage(systemName: archiveSymbol)) { [weak self] _ in
            self?.toggleArchive(place)
        }
        let delete = UIAction(
            title: "Delete Place",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDelete(place)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [edit, archive, delete])
        )
    }

    private func rebuildContent(place: PlaceEntity) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        mapView = nil

        contentStack.addArrangedSubview(makeHeader(place: place))
        if let coordinate = place.coordinate {
            contentStack.addArrangedSubview(makeMapCard(place: place, coordinate: coordinate))
        }
        contentStack.addArrangedSubview(makeRecordingsSection(place: place))
        contentStack.addArrangedSubview(makeInfoCard(place: place))
    }

    // MARK: - 头部

    private func makeHeader(place: PlaceEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let kind = place.kind

        let icon = SPIconTile(symbol: kind.symbolName, color: kind.color, size: 52, pointSize: 21)
        let typeLabel = UILabel()
        typeLabel.attributedText = NSAttributedString(
            string: kind.title,
            attributes: [
                .font: SPFont.text(10.5, weight: .semibold, relativeTo: .caption2),
                .foregroundColor: kind.color,
                .kern: 1.2
            ]
        )
        typeLabel.adjustsFontForContentSizeCategory = true

        let archived = SPStatusBadge(text: "Archived", color: SPColor.tertiaryInk)
        archived.isHidden = place.archivedAt == nil
        let typeRow = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        typeRow.addArrangedSubview(typeLabel)
        typeRow.addArrangedSubview(archived)
        typeRow.addArrangedSubview(UIView())

        let nameLabel = UILabel()
        nameLabel.text = place.name
        nameLabel.font = SPFont.display(30, relativeTo: .largeTitle)
        nameLabel.textColor = SPColor.ink
        nameLabel.numberOfLines = 0
        nameLabel.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            nameLabel.maximumContentSizeCategory = .accessibilityMedium
        }

        let topText = UIStackView(axis: .vertical, spacing: 5)
        topText.addArrangedSubview(typeRow)
        topText.addArrangedSubview(nameLabel)

        let topRow = UIStackView(axis: .horizontal, spacing: 14, alignment: .top)
        topRow.addArrangedSubview(icon)
        topRow.addArrangedSubview(topText)
        stack.addArrangedSubview(topRow)

        if let note = place.note, !note.isEmpty {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = SPFont.text(14, weight: .regular, relativeTo: .body)
            noteLabel.textColor = SPColor.secondaryInk
            noteLabel.numberOfLines = 0
            noteLabel.adjustsFontForContentSizeCategory = true
            stack.setCustomSpacing(14, after: topRow)
            stack.addArrangedSubview(noteLabel)
        }

        if !place.tags.isEmpty {
            let tagFlow = SPTagFlowView(tags: place.tags)
            stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(tagFlow)
        }

        let divider = SPDivider()
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(14, after: divider)

        let stats = makeStatsRow(place: place)
        stack.addArrangedSubview(stats)
        stack.setCustomSpacing(16, after: stats)

        let recordButton = SPButton(title: "Record Here", symbol: "mic.fill", style: .primary)
        recordButton.addTarget(self, action: #selector(recordHereTapped), for: .touchUpInside)
        stack.addArrangedSubview(recordButton)

        let recordings = place.sortedRecordings
        if recordings.count >= 2 {
            let compareButton = SPButton(title: "Compare Recordings", symbol: "rectangle.split.2x1", style: .secondary)
            compareButton.addTarget(self, action: #selector(compareTapped), for: .touchUpInside)
            stack.setCustomSpacing(9, after: recordButton)
            stack.addArrangedSubview(compareButton)
        }

        card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
        return card
    }

    private func makeStatsRow(place: PlaceEntity) -> UIView {
        let recordings = place.sortedRecordings
        let count = recordings.count
        let first = recordings.last?.createdAt
        let latest = recordings.first?.createdAt

        let row = UIStackView(axis: .horizontal, spacing: 8, distribution: .fillEqually)
        row.addArrangedSubview(SPMetricTile(
            title: "Recordings",
            value: "\(count)",
            unit: "total",
            accent: SPColor.ink
        ))
        row.addArrangedSubview(SPMetricTile(
            title: "First Recording",
            value: first.map { SPFormat.shortDate.string(from: $0) } ?? "—",
            accent: SPColor.secondaryInk
        ))
        row.addArrangedSubview(SPMetricTile(
            title: "Latest Recording",
            value: latest.map { SPFormat.relativeDate($0) } ?? "—",
            accent: SPColor.accent
        ))
        return row
    }

    // MARK: - 地图

    private func makeMapCard(place: PlaceEntity, coordinate: Coordinate) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 10)

        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Recorded Location"
        title.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        let precision = SPStatusBadge(
            text: place.precision.title,
            color: place.precision == .precise ? SPColor.moss : SPColor.amber,
            symbol: "location.fill"
        )
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(precision)
        stack.addArrangedSubview(header)

        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.layer.cornerRadius = 14
        map.layer.cornerCurve = .continuous
        map.clipsToBounds = true
        map.delegate = self
        map.heightAnchor.constraint(equalToConstant: 168).isActive = true

        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        annotation.title = place.name
        map.addAnnotation(annotation)
        map.setRegion(
            MKCoordinateRegion(
                center: annotation.coordinate,
                latitudinalMeters: place.precision == .approximate ? 2_600 : 620,
                longitudinalMeters: place.precision == .approximate ? 2_600 : 620
            ),
            animated: false
        )
        stack.addArrangedSubview(map)
        mapView = map

        let openButton = SPTextButton(title: "Open in Maps")
        openButton.addTarget(self, action: #selector(openMapTapped), for: .touchUpInside)
        openButton.contentHorizontalAlignment = .leading
        stack.addArrangedSubview(openButton)
        card.addContent(stack, insets: UIEdgeInsets(top: 15, left: 15, bottom: 11, right: 15))
        return card
    }

    // MARK: - 录音历史

    private func makeRecordingsSection(place: PlaceEntity) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 12)
        let recordings = place.sortedRecordings
        let header = SPSectionHeaderView(
            title: "Recording History",
            subtitle: recordings.isEmpty ? nil : "\(recordings.count) recordings · Newest first",
            actionTitle: recordings.count >= 2 ? "Compare" : nil,
            action: recordings.count >= 2 ? { [weak self] in self?.compareTapped() } : nil
        )
        section.addArrangedSubview(header)

        if recordings.isEmpty {
            let empty = SPEmptyStateView(
                symbol: "mic",
                title: "No Sound Here Yet",
                message: "Add recordings at the same location to compare changes across seasons and times of day.",
                actionTitle: "Record Here",
                action: { [weak self] in self?.recordHereTapped() }
            )
            section.addArrangedSubview(empty)
        } else {
            let displayed = Array(recordings.prefix(20))
            let card = SPCardView(style: .surface)
            let rows = UIStackView(axis: .vertical, spacing: 0)
            for (index, record) in displayed.enumerated() {
                let row = SPRecordingRowView()
                row.configure(with: record, showPlace: false) { [weak self] in
                    self?.openRecording(record)
                }
                rows.addArrangedSubview(row)
                if index < displayed.count - 1 {
                    rows.addArrangedSubview(SPDivider())
                }
            }
            card.addContent(rows, insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
            section.addArrangedSubview(card)
            if recordings.count > displayed.count {
                let all = SPButton(title: "See All Recordings Here", symbol: "list.bullet", style: .secondary)
                all.addTarget(self, action: #selector(openAllPlaceRecordings), for: .touchUpInside)
                section.addArrangedSubview(all)
            }
        }
        return section
    }

    // MARK: - 信息

    private func makeInfoCard(place: PlaceEntity) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)
        let title = UILabel()
        title.text = "Place Details"
        title.font = SPFont.display(19, relativeTo: .headline)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(title)

        stack.addArrangedSubview(SPValueRow(title: "Created", value: SPFormat.shortDate.string(from: place.createdAt)))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(title: "Updated", value: SPFormat.shortDate.string(from: place.updatedAt)))
        stack.addArrangedSubview(SPDivider())
        let locationValue: String
        if place.coordinate != nil {
            locationValue = "\(place.precision.title) · \(String(format: "%.5f, %.5f", place.latitude, place.longitude))"
        } else {
            locationValue = "Not saved"
        }
        stack.addArrangedSubview(SPValueRow(title: "Location", value: locationValue))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(SPValueRow(
            title: "Audio Files",
            value: SPFormat.fileSize(place.recordings.reduce(0) { $0 + $1.fileSize })
        ))

        let privacy = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
        let lock = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)))
        lock.tintColor = SPColor.moss
        lock.contentMode = .scaleAspectFit
        lock.translatesAutoresizingMaskIntoConstraints = false
        lock.widthAnchor.constraint(equalToConstant: 10).isActive = true
        lock.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let privacyLabel = UILabel()
        privacyLabel.text = "Place information is stored only on this device"
        privacyLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        privacyLabel.textColor = SPColor.tertiaryInk
        privacyLabel.adjustsFontForContentSizeCategory = true
        privacy.addArrangedSubview(lock)
        privacy.addArrangedSubview(privacyLabel)
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(privacy)

        card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
        return card
    }

    // MARK: - 操作

    @objc private func recordHereTapped() {
        guard let place else { return }
        RecordingFlowCoordinator.shared.present(from: self, placeID: place.id) { [weak self] record in
            guard let self, let record else { return }
            self.reload()
            let detail = RecordingDetailViewController(recordingID: record.id)
            self.navigationController?.pushViewController(detail, animated: true)
        }
    }

    @objc private func compareTapped() {
        guard let place else { return }
        let records = place.sortedRecordings
        guard records.count >= 2 else { return }
        let controller = CompareWorkspaceViewController(
            recordingAID: records[1].id,
            recordingBID: records[0].id
        )
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openAllPlaceRecordings() {
        guard let place else { return }
        let controller = RecordingsListViewController(initialPlaceID: place.id)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openRecording(_ record: RecordingEntity) {
        let controller = RecordingDetailViewController(recordingID: record.id)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openMapTapped() {
        guard let place, let coordinate = place.coordinate else { return }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func editPlace(_ place: PlaceEntity) {
        let editor = PlaceEditorViewController(mode: .edit(place)) { [weak self] place, _ in
            guard let self else { return }
            self.reload()
            SPToast.show("Place updated", in: self.view, symbol: "checkmark.circle.fill")
        }
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func toggleArchive(_ place: PlaceEntity) {
        do {
            try library.setPlaceArchived(place, archived: place.archivedAt == nil)
            SPHaptic.success()
            reload()
            SPToast.show(
                place.archivedAt == nil ? "Restored from archive" : "Archived",
                in: view,
                symbol: "archivebox"
            )
        } catch {
            presentError(error)
        }
    }

    private func confirmDelete(_ place: PlaceEntity) {
        let count = place.recordings.count
        guard count > 0 else {
            presentConfirm(
                title: "Delete “\(place.name)”?",
                message: "This can't be undone.",
                destructiveTitle: "Delete"
            ) { [weak self] in
                do {
                    try self?.library.deletePlace(place, strategy: .deleteRecordings)
                    self?.navigationController?.popViewController(animated: true)
                } catch {
                    self?.presentError(error)
                }
            }
            return
        }

        let sheet = UIAlertController(
            title: "Delete “\(place.name)”",
            message: "What should happen to the \(count) linked recordings?",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Delete All Recordings", style: .destructive) { [weak self] _ in
            self?.confirmDeleteWithRecordings(place)
        })
        sheet.addAction(UIAlertAction(title: "Move Recordings to Unassigned", style: .default) { [weak self] _ in
            do {
                try self?.library.deletePlace(place, strategy: .detachRecordings)
                self?.navigationController?.popViewController(animated: true)
            } catch {
                self?.presentError(error)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func confirmDeleteWithRecordings(_ place: PlaceEntity) {
        presentConfirm(
            title: "Delete All Recordings Too?",
            message: "“\(place.name)” and its audio files will be permanently deleted. This can't be undone.",
            destructiveTitle: "Delete All"
        ) { [weak self] in
            do {
                try self?.library.deletePlace(place, strategy: .deleteRecordings)
                self?.navigationController?.popViewController(animated: true)
            } catch {
                self?.presentError(error)
            }
        }
    }
}

extension PlaceDetailViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        let identifier = "place-detail-pin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.markerTintColor = SPColor.accent
        view.glyphImage = UIImage(systemName: "waveform")
        view.displayPriority = .required
        return view
    }
}
