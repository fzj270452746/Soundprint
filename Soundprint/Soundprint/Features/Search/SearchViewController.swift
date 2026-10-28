//
//  SearchViewController.swift
//  Soundprint
//
//  跨录音、地点、笔记和标签的本地搜索；也承载“Unassigned Recordings”的归档。
//

import UIKit

final class SearchViewController: SPViewController {
    enum Mode {
        case general
        case detached
    }

    private let mode: Mode
    private let library = LibraryService.shared
    private let searchField = SPSearchField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyContainer = UIView()
    private var emptyView: SPEmptyStateView?
    private var recordings: [RecordingEntity] = []
    private var places: [PlaceEntity] = []
    private var query = ""
    private var reloadWorkItem: DispatchWorkItem?

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        if case .detached = mode {
            hidesBottomBarWhenPushed = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode == .detached ? "Unassigned Recordings" : "Search"
        if case .general = mode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        }
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
        searchField.setPlaceholder(mode == .detached ? "Search unassigned recordings" : "Search recordings, places, tags, and notes")
        searchField.onTextChanged = { [weak self] text in
            self?.query = text
            self?.reload()
        }
        view.addSubview(searchField)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = SPColor.paper
        tableView.separatorColor = SPColor.hairline
        tableView.estimatedRowHeight = 64
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SPRecordingTableCell.self, forCellReuseIdentifier: SPRecordingTableCell.reuseIdentifier)
        tableView.register(SPPlaceTableCell.self, forCellReuseIdentifier: SPPlaceTableCell.reuseIdentifier)
        view.addSubview(tableView)
        // backgroundView is framed by UITableView; keep autoresizing so it fills the table bounds.
        emptyContainer.translatesAutoresizingMaskIntoConstraints = true
        tableView.backgroundView = emptyContainer

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        if mode == .detached {
            recordings = library.fetchDetachedRecordings(search: query)
            places = []
        } else if query.isEmpty {
            recordings = library.fetchRecordings(limit: 5)
            places = Array(library.fetchPlaces().prefix(5))
        } else {
            recordings = library.fetchRecordings(search: query)
            places = library.fetchPlaces(search: query)
        }
        tableView.reloadData()
        updateEmpty()
    }

    private func updateEmpty() {
        emptyView?.removeFromSuperview()
        emptyView = nil
        let isEmpty = recordings.isEmpty && places.isEmpty
        guard isEmpty else { return }
        let view: SPEmptyStateView
        if mode == .detached {
            view = SPEmptyStateView(
                symbol: "tray",
                title: "No Unassigned Recordings",
                message: "Recordings saved without a place are collected here."
            )
        } else if query.isEmpty {
            view = SPEmptyStateView(
                symbol: "waveform",
                title: "Nothing Here Yet",
                message: "Once you add recordings or places, you can search across them here."
            )
        } else {
            view = SPEmptyStateView(
                symbol: "magnifyingglass",
                title: "No Results",
                message: "Try a different search term. You can search titles, places, tags, and notes."
            )
        }
        emptyContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor, constant: -20),
            view.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -20)
        ])
        emptyView = view
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func openRecording(_ record: RecordingEntity) {
        let detail = RecordingDetailViewController(recordingID: record.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func openPlace(_ place: PlaceEntity) {
        let detail = PlaceDetailViewController(placeID: place.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func showDetachedActions(for record: RecordingEntity) {
        let sheet = UIAlertController(title: record.title, message: "You can set a place for this recording.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Open Recording", style: .default) { [weak self] _ in
            self?.openRecording(record)
        })
        sheet.addAction(UIAlertAction(title: "Assign Place", style: .default) { [weak self] _ in
            self?.assignPlace(to: record)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func assignPlace(to record: RecordingEntity) {
        let picker = PlacePickerViewController(selectedPlaceID: record.place?.id, allowNone: false) { [weak self] place in
            guard let self, let place else { return }
            do {
                try self.library.assignRecordings([record], to: place)
                SPHaptic.success()
                self.reload()
                SPToast.show("Assigned to “\(place.name)”", in: self.view)
            } catch {
                self.presentError(error)
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        SPStyle.applyNavigationAppearance(to: nav)
        present(nav, animated: true)
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    private var recordingSection: Int { 0 }

    func numberOfSections(in tableView: UITableView) -> Int {
        mode == .general ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == recordingSection { return recordings.count }
        return places.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == recordingSection {
            guard !recordings.isEmpty else { return nil }
            if mode == .detached { return "\(recordings.count) unassigned recordings" }
            return query.isEmpty ? "Recent Recordings" : "Recordings"
        }
        guard !places.isEmpty else { return nil }
        return query.isEmpty ? "Recent Places" : "Places"
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
            header.textLabel?.textColor = SPColor.tertiaryInk
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == recordingSection {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SPRecordingTableCell.reuseIdentifier,
                for: indexPath
            ) as! SPRecordingTableCell
            cell.configure(with: recordings[indexPath.row])
            return cell
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SPPlaceTableCell.reuseIdentifier,
            for: indexPath
        ) as! SPPlaceTableCell
        cell.configure(with: places[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == recordingSection {
            let record = recordings[indexPath.row]
            if mode == .detached {
                showDetachedActions(for: record)
            } else {
                openRecording(record)
            }
        } else {
            openPlace(places[indexPath.row])
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard mode == .detached, indexPath.section == recordingSection else { return nil }
        let record = recordings[indexPath.row]
        let action = UIContextualAction(style: .normal, title: "Assign Place") { [weak self] _, _, completion in
            self?.assignPlace(to: record)
            completion(true)
        }
        action.backgroundColor = SPColor.accent
        action.image = UIImage(systemName: "mappin.and.ellipse")
        return UISwipeActionsConfiguration(actions: [action])
    }
}
