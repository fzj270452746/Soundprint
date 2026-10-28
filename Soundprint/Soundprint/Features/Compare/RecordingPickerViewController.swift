//
//  RecordingPickerViewController.swift
//  Soundprint
//
//  为 A/B 选择录音。同一段录音不能同时占两个位置。
//

import UIKit

final class RecordingPickerViewController: SPViewController {
    private let slotTitle: String
    private let selectedID: UUID?
    private let excludedID: UUID?
    private let onSelect: (RecordingEntity) -> Void
    private let library = LibraryService.shared

    private let searchField = SPSearchField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var recordings: [RecordingEntity] = []

    init(
        slotTitle: String,
        selectedID: UUID?,
        excludedID: UUID?,
        onSelect: @escaping (RecordingEntity) -> Void
    ) {
        self.slotTitle = slotTitle
        self.selectedID = selectedID
        self.excludedID = excludedID
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = slotTitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))

        searchField.setPlaceholder("Search recording titles, places, and tags")
        searchField.onTextChanged = { [weak self] _ in self?.reload() }
        view.addSubview(searchField)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = SPColor.paper
        tableView.separatorColor = SPColor.hairline
        tableView.rowHeight = 68
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RecordingPickCell.self, forCellReuseIdentifier: RecordingPickCell.reuseIdentifier)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No matching recordings"
        emptyLabel.font = SPFont.text(13, weight: .regular, relativeTo: .footnote)
        emptyLabel.textColor = SPColor.tertiaryInk
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30)
        ])
        reload()
    }

    private func reload() {
        var all = library.fetchRecordings(search: searchField.text)
        if let excludedID {
            all = all.filter { $0.id != excludedID }
        }
        recordings = all
        tableView.reloadData()
        emptyLabel.isHidden = !recordings.isEmpty
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

extension RecordingPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        recordings.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: RecordingPickCell.reuseIdentifier,
            for: indexPath
        ) as! RecordingPickCell
        let record = recordings[indexPath.row]
        cell.configure(with: record, selected: record.id == selectedID)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = recordings[indexPath.row]
        SPHaptic.selection()
        dismiss(animated: true) { [onSelect] in
            onSelect(record)
        }
    }
}

private final class RecordingPickCell: UITableViewCell {
    static let reuseIdentifier = "RecordingPickCell"
    private let iconTile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 36, pointSize: 14)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let durationLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = SPColor.surface
        tintColor = SPColor.accent

        titleLabel.font = SPFont.text(14, weight: .semibold, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.adjustsFontForContentSizeCategory = true
        durationLabel.font = SPFont.mono(10.5, weight: .medium, relativeTo: .caption2)
        durationLabel.textColor = SPColor.secondaryInk
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        let row = UIStackView(axis: .horizontal, spacing: 11, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(durationLabel)
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        accessoryType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with record: RecordingEntity, selected: Bool) {
        titleLabel.text = record.title
        let place = record.place?.name ?? "Unassigned"
        subtitleLabel.text = "\(place) · \(SPFormat.shortDate.string(from: record.createdAt))"
        durationLabel.text = SPFormat.duration(record.duration)
        accessoryType = selected ? .checkmark : .none
        accessibilityLabel = "\(record.title), \(place), \(SPFormat.accessibleDuration(record.duration))"
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
