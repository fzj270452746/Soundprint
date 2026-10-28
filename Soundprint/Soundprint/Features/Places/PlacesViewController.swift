//
//  PlacesViewController.swift
//  Soundprint
//
//  地点列表：搜索、类型筛选、归档与地点档案入口。
//

import UIKit

final class PlacesViewController: SPViewController {
    private let library = LibraryService.shared
    private let collectionView: UICollectionView
    private let searchField = SPSearchField()
    private let filterScroll = UIScrollView()
    private let filterStack = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
    private let emptyContainer = UIView()
    private let detachedBanner = SPDetachedBanner()
    private let contentStack = UIStackView(axis: .vertical, spacing: 10)
    private var emptyState: SPEmptyStateView?
    private var places: [PlaceEntity] = []
    private var selectedKind: PlaceKind?
    private var showsArchived = false
    private var searchText = ""
    private var reloadWorkItem: DispatchWorkItem?

    init() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(132)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(132)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 28, trailing: 0)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        observeData()
        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    // MARK: - 界面

    private func buildInterface() {
        let titleLabel = UILabel()
        titleLabel.text = "Places"
        titleLabel.font = SPFont.display(34, relativeTo: .largeTitle)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Archive the sound of a place over time."
        subtitleLabel.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let addButton = SPIconButton(symbol: "plus", accessibilityLabel: "Create a new place", style: .filled)
        addButton.addTarget(self, action: #selector(addPlaceTapped), for: .touchUpInside)

        let titleRow = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        let titleStack = UIStackView(axis: .vertical, spacing: 2)
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)
        titleRow.addArrangedSubview(titleStack)
        titleRow.addArrangedSubview(UIView())
        titleRow.addArrangedSubview(addButton)

        searchField.onTextChanged = { [weak self] text in
            self?.searchText = text
            self?.reloadData()
        }

        buildFilters()

        filterScroll.translatesAutoresizingMaskIntoConstraints = false
        filterScroll.showsHorizontalScrollIndicator = false
        filterScroll.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: SPMetric.screenInset)
        filterScroll.addSubview(filterStack)
        NSLayoutConstraint.activate([
            filterScroll.heightAnchor.constraint(equalToConstant: 34),
            filterStack.leadingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.trailingAnchor),
            filterStack.topAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.bottomAnchor),
            filterStack.heightAnchor.constraint(equalTo: filterScroll.frameLayoutGuide.heightAnchor)
        ])

        detachedBanner.isHidden = true
        detachedBanner.onTap = { [weak self] in
            self?.openDetachedRecordings()
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PlaceCollectionCell.self, forCellWithReuseIdentifier: PlaceCollectionCell.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 24, right: 0)

        // backgroundView is framed by the collection view; keep autoresizing so it fills the bounds.
        emptyContainer.translatesAutoresizingMaskIntoConstraints = true
        emptyContainer.backgroundColor = .clear
        collectionView.backgroundView = emptyContainer

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(detachedBanner)
        contentStack.addArrangedSubview(collectionView)

        view.addSubview(titleRow)
        view.addSubview(searchField)
        view.addSubview(filterScroll)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            titleRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            titleRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            titleRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            searchField.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 16),

            filterScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            filterScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            filterScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),

            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: filterScroll.bottomAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        detachedBanner.heightAnchor.constraint(equalToConstant: 50).isActive = true
        collectionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        collectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func buildFilters() {
        filterStack.arrangedSubviews.forEach {
            filterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let all = SPFilterChip(title: "All")
        all.selectedState = selectedKind == nil
        all.addTarget(self, action: #selector(allFilterTapped), for: .touchUpInside)
        filterStack.addArrangedSubview(all)

        for kind in PlaceKind.allCases {
            let chip = SPFilterChip(title: kind.title, symbol: kind.symbolName)
            chip.tag = PlaceKind.allCases.firstIndex(of: kind) ?? 0
            chip.selectedState = selectedKind == kind
            chip.addTarget(self, action: #selector(kindFilterTapped(_:)), for: .touchUpInside)
            filterStack.addArrangedSubview(chip)
        }

        let archive = SPFilterChip(title: "Archive", symbol: "archivebox")
        archive.selectedState = showsArchived
        archive.addTarget(self, action: #selector(archiveFilterTapped), for: .touchUpInside)
        filterStack.addArrangedSubview(archive)
    }

    private func observeData() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataChanged),
            name: SPNotification.libraryDidChange,
            object: nil
        )
    }

    @objc private func dataChanged() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reloadData() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func reloadData() {
        places = library.fetchPlaces(
            includeArchived: showsArchived,
            kind: selectedKind,
            search: searchText
        )
        collectionView.reloadData()
        let detached = library.fetchDetachedRecordings().count
        detachedBanner.isHidden = detached == 0
        detachedBanner.configure(count: detached)
        updateEmptyState()
        rebuildFilters()
    }

    private func rebuildFilters() {
        for view in filterStack.arrangedSubviews {
            guard let chip = view as? SPFilterChip else { continue }
            if chip.accessibilityLabel == "All" {
                chip.selectedState = selectedKind == nil
            } else if chip.accessibilityLabel == "Archive" {
                chip.selectedState = showsArchived
            } else if let index = PlaceKind.allCases.firstIndex(where: { $0.title == chip.accessibilityLabel }) {
                chip.selectedState = selectedKind == PlaceKind.allCases[index]
            }
        }
    }

    private func updateEmptyState() {
        emptyState?.removeFromSuperview()
        emptyState = nil
        guard places.isEmpty else { return }

        let hasFilters = selectedKind != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || showsArchived
        let view: SPEmptyStateView
        if hasFilters {
            view = SPEmptyStateView(
                symbol: "magnifyingglass",
                title: "No Results",
                message: "Try a different search term or filter.",
                actionTitle: "Reset Filters",
                action: { [weak self] in self?.resetFilters() }
            )
        } else {
            view = SPEmptyStateView(
                symbol: "mappin.and.ellipse",
                title: "No Places Yet",
                message: "A street corner, a room, a shoreline. Add a place whose sound you want to keep, and follow how it changes over time.",
                actionTitle: "Create Your First Place",
                action: { [weak self] in self?.addPlaceTapped() }
            )
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor, constant: -30),
            view.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -20)
        ])
        emptyState = view
    }

    private func resetFilters() {
        selectedKind = nil
        showsArchived = false
        searchText = ""
        searchField.text = ""
        buildFilters()
        reloadData()
    }

    // MARK: - 操作

    @objc private func allFilterTapped() {
        selectedKind = nil
        buildFilters()
        reloadData()
        SPHaptic.selection()
    }

    @objc private func kindFilterTapped(_ sender: SPFilterChip) {
        let kinds = PlaceKind.allCases
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        selectedKind = selectedKind == kinds[sender.tag] ? nil : kinds[sender.tag]
        buildFilters()
        reloadData()
        SPHaptic.selection()
    }

    @objc private func archiveFilterTapped() {
        showsArchived.toggle()
        buildFilters()
        reloadData()
        SPHaptic.selection()
    }

    @objc private func addPlaceTapped() {
        presentPlaceEditor(mode: .create)
    }

    private func presentPlaceEditor(mode: PlaceEditorViewController.Mode) {
        let editor = PlaceEditorViewController(mode: mode) { [weak self] place, created in
            guard let self else { return }
            self.reloadData()
            if created {
                let detail = PlaceDetailViewController(placeID: place.id)
                self.navigationController?.pushViewController(detail, animated: true)
            }
        }
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func openDetachedRecordings() {
        let controller = SearchViewController(mode: .detached)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    private func editPlace(_ place: PlaceEntity) {
        presentPlaceEditor(mode: .edit(place))
    }

    private func deletePlace(_ place: PlaceEntity) {
        let count = place.recordings.count
        guard count > 0 else {
            presentConfirm(
                title: "Delete “\(place.name)”?",
                message: "This can't be undone.",
                destructiveTitle: "Delete"
            ) { [weak self] in
                do {
                    try self?.library.deletePlace(place, strategy: .deleteRecordings)
                    self?.reloadData()
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
            self?.confirmDeletePlaceWithRecordings(place)
        })
        sheet.addAction(UIAlertAction(title: "Move Recordings to Unassigned", style: .default) { [weak self] _ in
            do {
                try self?.library.deletePlace(place, strategy: .detachRecordings)
                self?.reloadData()
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

    private func confirmDeletePlaceWithRecordings(_ place: PlaceEntity) {
        let alert = UIAlertController(
            title: "Delete All Recordings Too?",
            message: "“\(place.name)” and its audio files will be permanently deleted. This can't be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            do {
                try self?.library.deletePlace(place, strategy: .deleteRecordings)
                self?.reloadData()
            } catch {
                self?.presentError(error)
            }
        })
        present(alert, animated: true)
    }

    private func toggleArchive(_ place: PlaceEntity) {
        do {
            try library.setPlaceArchived(place, archived: place.archivedAt == nil)
            SPHaptic.success()
            reloadData()
        } catch {
            presentError(error)
        }
    }
}

// MARK: - 数据源与代理

extension PlacesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        places.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PlaceCollectionCell.reuseIdentifier,
            for: indexPath
        ) as! PlaceCollectionCell
        cell.configure(with: places[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let place = places[indexPath.item]
        let detail = PlaceDetailViewController(placeID: place.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let place = places[indexPath.item]
        return UIContextMenuConfiguration(identifier: place.id as NSUUID, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                self.editPlace(place)
            }
            let archiveTitle = place.archivedAt == nil ? "Archive" : "Unarchive"
            let archive = UIAction(
                title: archiveTitle,
                image: UIImage(systemName: place.archivedAt == nil ? "archivebox" : "tray.and.arrow.up")
            ) { _ in
                self.toggleArchive(place)
            }
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.deletePlace(place)
            }
            return UIMenu(children: [edit, archive, delete])
        }
    }
}

// MARK: - 地点单元格

private final class PlaceCollectionCell: UICollectionViewCell {
    static let reuseIdentifier = "PlaceCollectionCell"
    private let card = SPPlaceCardView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        card.isUserInteractionEnabled = false
        contentView.addSubview(card)
        card.pinEdges(to: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with place: PlaceEntity) {
        card.configure(with: place)
        isAccessibilityElement = false
        accessibilityElements = [card]
    }
}

// MARK: - Unassigned Recordings Entry

private final class SPDetachedBanner: UIControl {
    private let iconTile = SPIconTile(symbol: "tray.full", color: SPColor.accent, size: 34, pointSize: 13)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView()
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.accentSoft
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button

        titleLabel.font = SPFont.text(13, weight: .semibold, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.ink
        titleLabel.text = "Unassigned Recordings"
        detailLabel.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        detailLabel.textColor = SPColor.secondaryInk

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevron.tintColor = SPColor.accent

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        let row = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(chevron)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 12))
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 7),
            chevron.heightAnchor.constraint(equalToConstant: 11)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(count: Int) {
        detailLabel.text = "\(count) recordings can be assigned to a place"
        accessibilityLabel = "Unassigned recordings, \(count)"
        accessibilityHint = "Opens the list"
    }

    @objc private func tapped() { onTap?() }
}
