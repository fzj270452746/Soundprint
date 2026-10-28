//
//  PlacePickerViewController.swift
//  Soundprint
//
//  轻量地点选择器。供保存录音和“Unassigned Recordings”的归档操作复用。
//

import UIKit

final class PlacePickerViewController: SPViewController {
    private let allowNone: Bool
    private let selectedPlaceID: UUID?
    private let onSelect: (PlaceEntity?) -> Void

    private let searchField = SPSearchField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let library = LibraryService.shared
    private var places: [PlaceEntity] = []
    private var filteredPlaces: [PlaceEntity] = []

    init(
        selectedPlaceID: UUID?,
        allowNone: Bool,
        onSelect: @escaping (PlaceEntity?) -> Void
    ) {
        self.selectedPlaceID = selectedPlaceID
        self.allowNone = allowNone
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Choose Place"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))

        searchField.onTextChanged = { [weak self] _ in self?.applyFilter() }
        view.addSubview(searchField)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = SPColor.paper
        tableView.separatorColor = SPColor.hairline
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.register(PlaceOptionCell.self, forCellReuseIdentifier: PlaceOptionCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        reload()
    }

    private func reload() {
        places = library.fetchPlaces()
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredPlaces = places
        } else {
            filteredPlaces = library.fetchPlaces(search: query)
        }
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func choose(_ place: PlaceEntity?) {
        SPHaptic.selection()
        dismiss(animated: true) { [onSelect] in
            onSelect(place)
        }
    }

    private func createPlace() {
        let editor = PlaceEditorViewController(mode: .create) { [weak self] place, _ in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.onSelect(place)
            }
        }
        let nav = UINavigationController(rootViewController: editor)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}

extension PlacePickerViewController: UITableViewDataSource, UITableViewDelegate {
    private var placeSection: Int { allowNone ? 1 : 0 }
    private var createSection: Int { placeSection + 1 }

    func numberOfSections(in tableView: UITableView) -> Int {
        createSection + 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if allowNone && section == 0 { return 1 }
        if section == placeSection { return max(1, filteredPlaces.count) }
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if allowNone && section == 0 { return "Place" }
        if section == placeSection { return filteredPlaces.isEmpty ? nil : "Saved Places" }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == createSection { return 20 }
        return 8
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PlaceOptionCell.reuseIdentifier,
            for: indexPath
        ) as! PlaceOptionCell
        cell.backgroundColor = SPColor.surface
        cell.textLabel?.textColor = SPColor.ink
        cell.tintColor = SPColor.accent
        cell.accessoryType = .none

        if allowNone && indexPath.section == 0 {
            cell.configure(
                title: "No Place",
                subtitle: "You can assign a place later",
                symbol: "minus.circle",
                color: SPColor.tertiaryInk,
                countText: nil
            )
            return cell
        }

        if indexPath.section == placeSection {
            if filteredPlaces.isEmpty {
                cell.configure(
                    title: "No Matching Places",
                    subtitle: "You can create a new place",
                    symbol: "magnifyingglass",
                    color: SPColor.tertiaryInk,
                    countText: nil
                )
                cell.selectionStyle = .none
                return cell
            }
            let place = filteredPlaces[indexPath.row]
            cell.configure(
                title: place.name,
                subtitle: place.kind.title,
                symbol: place.kind.symbolName,
                color: place.kind.color,
                countText: "\(place.recordings.count) recordings"
            )
            if place.id == selectedPlaceID {
                cell.accessoryType = .checkmark
                cell.tintColor = SPColor.accent
            }
            return cell
        }

        cell.configure(
            title: "Create New Place",
            subtitle: "Add a name and type",
            symbol: "plus.circle.fill",
            color: SPColor.accent,
            countText: nil
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if allowNone && indexPath.section == 0 {
            choose(nil)
            return
        }
        if indexPath.section == placeSection {
            guard !filteredPlaces.isEmpty else { return }
            choose(filteredPlaces[indexPath.row])
            return
        }
        createPlace()
    }
}

private final class PlaceOptionCell: UITableViewCell {
    static let reuseIdentifier = "PlaceOptionCell"
    private let tile = SPIconTile(symbol: "mappin", color: SPColor.accent, size: 34, pointSize: 13)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let countLabel = UILabel()
    private let iconContainer = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = SPColor.surface

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.widthAnchor.constraint(equalToConstant: 34).isActive = true
        iconContainer.heightAnchor.constraint(equalToConstant: 34).isActive = true

        titleLabel.font = SPFont.text(15, weight: .medium, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.adjustsFontForContentSizeCategory = true

        countLabel.font = SPFont.mono(10.5, weight: .regular, relativeTo: .caption2)
        countLabel.textColor = SPColor.tertiaryInk
        countLabel.textAlignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        let row = UIStackView(axis: .horizontal, spacing: 11, alignment: .center)
        row.addArrangedSubview(iconContainer)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(countLabel)
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        accessoryType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String?, symbol: String, color: UIColor, countText: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        countLabel.text = countText
        iconContainer.subviews.forEach { $0.removeFromSuperview() }
        let tile = SPIconTile(symbol: symbol, color: color, size: 34, pointSize: 13)
        iconContainer.addSubview(tile)
        tile.pinEdges(to: iconContainer)
        accessibilityLabel = [title, subtitle, countText].compactMap { $0 }.joined(separator: ", ")
    }
}
