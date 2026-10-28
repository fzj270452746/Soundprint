//
//  ListCells.swift
//  Soundprint
//
//  搜索结果与录音库共用的表格单元。
//

import UIKit

final class SPRecordingTableCell: UITableViewCell {
    static let reuseIdentifier = "SPRecordingTableCell"
    private let iconTile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 36, pointSize: 14)
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let durationLabel = UILabel()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = SPColor.surface
        selectionStyle = .default
        tintColor = SPColor.accent

        titleLabel.font = SPFont.text(14.5, weight: .semibold, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        metaLabel.textColor = SPColor.tertiaryInk
        metaLabel.numberOfLines = 1
        metaLabel.adjustsFontForContentSizeCategory = true
        durationLabel.font = SPFont.mono(10, weight: .medium, relativeTo: .caption2)
        durationLabel.textColor = SPColor.secondaryInk
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 7).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 11).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(metaLabel)
        let row = UIStackView(axis: .horizontal, spacing: 11, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(durationLabel)
        row.addArrangedSubview(chevron)
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 14))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with record: RecordingEntity) {
        titleLabel.text = record.title
        let place = record.place?.name ?? "Unassigned"
        metaLabel.text = "\(place) · \(SPFormat.shortDate.string(from: record.createdAt)) · \(record.tags.prefix(2).joined(separator: " · "))"
        durationLabel.text = SPFormat.duration(record.duration)
        accessibilityLabel = "\(record.title), \(place), \(SPFormat.accessibleDuration(record.duration))"
        accessibilityHint = "Opens details"
        accessibilityTraits = .button
    }
}

final class SPPlaceTableCell: UITableViewCell {
    static let reuseIdentifier = "SPPlaceTableCell"
    private let iconTile = SPIconTile(symbol: "mappin", color: SPColor.accent, size: 36, pointSize: 14)
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let countLabel = UILabel()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = SPColor.surface
        selectionStyle = .default
        tintColor = SPColor.accent

        titleLabel.font = SPFont.display(16, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        metaLabel.textColor = SPColor.tertiaryInk
        metaLabel.adjustsFontForContentSizeCategory = true
        countLabel.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
        countLabel.textColor = SPColor.secondaryInk
        countLabel.textAlignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 7).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 11).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 2)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(metaLabel)
        let row = UIStackView(axis: .horizontal, spacing: 11, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(countLabel)
        row.addArrangedSubview(chevron)
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 14))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with place: PlaceEntity) {
        iconTile.update(symbol: place.kind.symbolName, color: place.kind.color)
        titleLabel.text = place.name
        metaLabel.text = "\(place.kind.title) · \(SPFormat.lastRecorded(place.sortedRecordings.first?.createdAt))"
        countLabel.text = "\(place.recordings.count) recordings"
        accessibilityLabel = "\(place.name), \(place.kind.title), \(place.recordings.count) recordings"
        accessibilityTraits = .button
    }
}
