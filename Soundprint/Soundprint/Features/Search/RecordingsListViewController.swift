//
//  RecordingsListViewController.swift
//  Soundprint
//
//  录音库：关键字、地点、标签和时长筛选。
//

import UIKit

final class RecordingsListViewController: SPViewController {
    private enum PlaceFilter: Equatable {
        case all
        case detached
        case place(UUID)
    }

    private enum DurationFilter: Int, CaseIterable {
        case all
        case short
        case medium
        case long

        var title: String {
            switch self {
            case .all: return "All"
            case .short: return "Under 1 Min"
            case .medium: return "1–5 Min"
            case .long: return "Over 5 Min"
            }
        }

        func matches(_ duration: Double) -> Bool {
            switch self {
            case .all: return true
            case .short: return duration < 60
            case .medium: return duration >= 60 && duration <= 300
            case .long: return duration > 300
            }
        }
    }

    private let library = LibraryService.shared
    private let searchField = SPSearchField()
    private let filterChipScroll = UIScrollView()
    private let filterChipStack = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyContainer = UIView()
    private var emptyState: SPEmptyStateView?
    private var filterHeight: NSLayoutConstraint!
    private var records: [RecordingEntity] = []
    private var searchText = ""
    private var placeFilter: PlaceFilter = .all
    private var tagFilter: String?
    private var durationFilter: DurationFilter = .all
    private var reloadWorkItem: DispatchWorkItem?

    init(initialPlaceID: UUID? = nil) {
        if let initialPlaceID {
            placeFilter = .place(initialPlaceID)
        }
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recordings"
        buildInterface()
        observe()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reload()
    }

    private func buildInterface() {
        searchField.onTextChanged = { [weak self] text in
            self?.searchText = text
            self?.reload()
        }
        view.addSubview(searchField)

        filterChipScroll.translatesAutoresizingMaskIntoConstraints = false
        filterChipScroll.showsHorizontalScrollIndicator = false
        filterChipStack.translatesAutoresizingMaskIntoConstraints = false
        filterChipScroll.addSubview(filterChipStack)
        filterHeight = filterChipScroll.heightAnchor.constraint(equalToConstant: 30)
        filterHeight.isActive = true
        view.addSubview(filterChipScroll)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = SPColor.paper
        tableView.separatorColor = SPColor.hairline
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SPRecordingTableCell.self, forCellReuseIdentifier: SPRecordingTableCell.reuseIdentifier)
        view.addSubview(tableView)
        // backgroundView is framed by UITableView; keep autoresizing so it fills the table bounds.
        emptyContainer.translatesAutoresizingMaskIntoConstraints = true
        tableView.backgroundView = emptyContainer

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),

            filterChipScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            filterChipScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            filterChipScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 7),
            filterChipStack.leadingAnchor.constraint(equalTo: filterChipScroll.contentLayoutGuide.leadingAnchor),
            filterChipStack.trailingAnchor.constraint(equalTo: filterChipScroll.contentLayoutGuide.trailingAnchor),
            filterChipStack.topAnchor.constraint(equalTo: filterChipScroll.contentLayoutGuide.topAnchor),
            filterChipStack.bottomAnchor.constraint(equalTo: filterChipScroll.contentLayoutGuide.bottomAnchor),
            filterChipStack.heightAnchor.constraint(equalTo: filterChipScroll.frameLayoutGuide.heightAnchor),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: filterChipScroll.bottomAnchor, constant: 6),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        rebuildFilterMenu()
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

    private func reload() {
        var all = library.fetchRecordings(search: searchText)
        switch placeFilter {
        case .all:
            break
        case .detached:
            all = all.filter { $0.place == nil }
        case .place(let id):
            all = all.filter { $0.place?.id == id }
        }
        if let tagFilter {
            all = all.filter { $0.tags.contains(tagFilter) }
        }
        all = all.filter { durationFilter.matches($0.duration) }
        records = all
        tableView.reloadData()
        updateFilterChips()
        updateEmptyState()
        rebuildFilterMenu()
    }

    private func updateEmptyState() {
        emptyState?.removeFromSuperview()
        emptyState = nil
        guard records.isEmpty else { return }
        let hasFilters = placeFilter != .all || tagFilter != nil || durationFilter != .all || !searchText.isEmpty
        let view: SPEmptyStateView
        if hasFilters {
            view = SPEmptyStateView(
                symbol: "line.3.horizontal.decrease.circle",
                title: "No Recordings Match",
                message: "Try changing the search term or filters.",
                actionTitle: "Clear Filters",
                action: { [weak self] in self?.clearFilters() }
            )
        } else {
            view = SPEmptyStateView(
                symbol: "waveform",
                title: "No Recordings Yet",
                message: "Record the first sound at a place that catches your ear.",
                actionTitle: "Start Recording",
                action: { [weak self] in self?.startRecording() }
            )
        }
        emptyContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor, constant: -20),
            view.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -20)
        ])
        emptyState = view
    }

    private func updateFilterChips() {
        filterChipStack.arrangedSubviews.forEach {
            filterChipStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var hasChips = false
        if case .detached = placeFilter {
            let chip = SPTagView(text: "Unassigned", symbol: "tray", color: SPColor.accent, background: SPColor.accentSoft, removable: true)
            chip.onTap = { [weak self] in self?.placeFilter = .all; self?.reload() }
            filterChipStack.addArrangedSubview(chip)
            hasChips = true
        } else if case .place(let id) = placeFilter, let place = library.fetchPlace(id: id) {
            let chip = SPTagView(text: place.name, symbol: "mappin", color: SPColor.accent, background: SPColor.accentSoft, removable: true)
            chip.onTap = { [weak self] in self?.placeFilter = .all; self?.reload() }
            filterChipStack.addArrangedSubview(chip)
            hasChips = true
        }
        if let tagFilter {
            let chip = SPTagView(text: tagFilter, symbol: "tag", color: SPColor.secondaryInk, background: SPColor.sunken, removable: true)
            chip.onTap = { [weak self] in self?.tagFilter = nil; self?.reload() }
            filterChipStack.addArrangedSubview(chip)
            hasChips = true
        }
        if durationFilter != .all {
            let chip = SPTagView(text: durationFilter.title, symbol: "timer", color: SPColor.secondaryInk, background: SPColor.sunken, removable: true)
            chip.onTap = { [weak self] in self?.durationFilter = .all; self?.reload() }
            filterChipStack.addArrangedSubview(chip)
            hasChips = true
        }
        if hasChips {
            let clear = SPTagView(text: "Clear", symbol: "xmark", color: SPColor.danger, background: SPColor.dangerSoft)
            clear.onTap = { [weak self] in self?.clearFilters() }
            filterChipStack.addArrangedSubview(clear)
        }
        filterHeight.constant = hasChips ? 30 : 0
        filterChipScroll.isHidden = !hasChips
    }

    private func rebuildFilterMenu() {
        let places = library.fetchPlaces(includeArchived: true)
        let tags = library.allTags()

        var placeActions: [UIAction] = [
            UIAction(title: "All", state: placeFilter == .all ? .on : .off) { [weak self] _ in
                self?.placeFilter = .all
                self?.reload()
            },
            UIAction(title: "Unassigned", image: UIImage(systemName: "tray"), state: placeFilter == .detached ? .on : .off) { [weak self] _ in
                self?.placeFilter = .detached
                self?.reload()
            }
        ]
        for place in places {
            let selected: UIAction.State = {
                if case .place(let id) = placeFilter, id == place.id { return .on }
                return .off
            }()
            placeActions.append(UIAction(title: place.name, state: selected) { [weak self] _ in
                self?.placeFilter = .place(place.id)
                self?.reload()
            })
        }

        var tagActions: [UIAction] = [
            UIAction(title: "All", state: tagFilter == nil ? .on : .off) { [weak self] _ in
                self?.tagFilter = nil
                self?.reload()
            }
        ]
        for tag in tags {
            tagActions.append(UIAction(title: tag, state: tagFilter == tag ? .on : .off) { [weak self] _ in
                self?.tagFilter = tag
                self?.reload()
            })
        }

        let durationActions = DurationFilter.allCases.map { filter in
            UIAction(title: filter.title, state: durationFilter == filter ? .on : .off) { [weak self] _ in
                self?.durationFilter = filter
                self?.reload()
            }
        }

        let reset = UIAction(
            title: "Clear Filters",
            image: UIImage(systemName: "arrow.counterclockwise"),
            attributes: (placeFilter == .all && tagFilter == nil && durationFilter == .all) ? .disabled : []
        ) { [weak self] _ in
            self?.clearFilters()
        }

        let menu = UIMenu(children: [
            UIMenu(title: "Place", image: UIImage(systemName: "mappin.and.ellipse"), children: placeActions),
            UIMenu(title: "Tags", image: UIImage(systemName: "tag"), children: tagActions),
            UIMenu(title: "Length", image: UIImage(systemName: "timer"), children: durationActions),
            UIMenu(options: .displayInline, children: [reset])
        ])
        let item = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            menu: menu
        )
        item.accessibilityLabel = "Filters"
        navigationItem.rightBarButtonItem = item
    }

    private func clearFilters() {
        placeFilter = .all
        tagFilter = nil
        durationFilter = .all
        searchText = ""
        searchField.text = ""
        reload()
    }

    private func startRecording() {
        RecordingFlowCoordinator.shared.present(from: self, placeID: nil) { [weak self] record in
            guard let self else { return }
            self.reload()
            if let record {
                let detail = RecordingDetailViewController(recordingID: record.id)
                self.navigationController?.pushViewController(detail, animated: true)
            }
        }
    }
}

extension RecordingsListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        records.isEmpty ? nil : "\(records.count) recordings"
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
            header.textLabel?.textColor = SPColor.tertiaryInk
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SPRecordingTableCell.reuseIdentifier,
            for: indexPath
        ) as! SPRecordingTableCell
        cell.configure(with: records[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let detail = RecordingDetailViewController(recordingID: records[indexPath.row].id)
        navigationController?.pushViewController(detail, animated: true)
    }
}

