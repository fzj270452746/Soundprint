//
//  ContentViews.swift
//  Soundprint
//
//  录音与地点的展示组件。卡片整体可点击，并带有完整的 VoiceOver 描述。
//

import UIKit

// MARK: - 图标方块

final class SPIconTile: UIView {
    private let imageView = UIImageView()

    init(symbol: String, color: UIColor, background: UIColor? = nil, size: CGFloat = 42, pointSize: CGFloat = 17) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = background ?? color.withAlphaComponent(0.12)
        layer.cornerRadius = size * 0.31
        layer.cornerCurve = .continuous
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(symbol: String, color: UIColor) {
        imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        imageView.tintColor = color
        backgroundColor = color.withAlphaComponent(0.12)
    }
}

// MARK: - 大录音卡片

final class SPRecordingCardView: UIControl {
    private let eyebrow = UILabel()
    private let dateLabel = UILabel()
    private let titleLabel = UILabel()
    private let waveform = SPWaveformView()
    private let durationLabel = UILabel()
    private let placeIcon = UIImageView()
    private let footerStack = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
    private let tagsStack = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
    private let missingLabel = UILabel()
    private var recordingID: UUID?

    var onTap: (() -> Void)?
    private(set) var record: RecordingEntity?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.surface
        layer.cornerRadius = SPMetric.cardRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SPColor.hairline.cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button

        placeIcon.translatesAutoresizingMaskIntoConstraints = false
        placeIcon.image = UIImage(systemName: "mappin", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        placeIcon.tintColor = SPColor.tertiaryInk
        placeIcon.contentMode = .scaleAspectFit
        placeIcon.widthAnchor.constraint(equalToConstant: 10).isActive = true
        placeIcon.heightAnchor.constraint(equalToConstant: 10).isActive = true

        eyebrow.font = SPFont.text(11, weight: .medium, relativeTo: .caption1)
        eyebrow.textColor = SPColor.secondaryInk
        eyebrow.numberOfLines = 1
        eyebrow.adjustsFontForContentSizeCategory = true
        eyebrow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dateLabel.font = SPFont.mono(10.5, weight: .regular, relativeTo: .caption2)
        dateLabel.textColor = SPColor.tertiaryInk
        dateLabel.textAlignment = .right
        dateLabel.adjustsFontForContentSizeCategory = true

        titleLabel.font = SPFont.display(20, relativeTo: .title3)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            titleLabel.maximumContentSizeCategory = .accessibilityLarge
        }

        waveform.tint = SPColor.secondaryInk.withAlphaComponent(0.78)
        waveform.playedTint = SPColor.secondaryInk.withAlphaComponent(0.78)
        waveform.progress = 1
        waveform.showsPlayhead = false
        waveform.isUserInteractionEnabled = false
        waveform.heightAnchor.constraint(equalToConstant: 38).isActive = true

        durationLabel.font = SPFont.mono(11, weight: .medium, relativeTo: .caption1)
        durationLabel.textColor = SPColor.secondaryInk
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.adjustsFontForContentSizeCategory = true

        missingLabel.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        missingLabel.textColor = SPColor.danger
        missingLabel.text = "Audio file not found"
        missingLabel.isHidden = true
        missingLabel.adjustsFontForContentSizeCategory = true

        footerStack.addArrangedSubview(durationLabel)
        footerStack.addArrangedSubview(tagsStack)
        footerStack.addArrangedSubview(UIView())

        let topRow = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
        topRow.addArrangedSubview(placeIcon)
        topRow.addArrangedSubview(eyebrow)
        topRow.addArrangedSubview(dateLabel)

        let stack = UIStackView(axis: .vertical, spacing: 0)
        stack.addArrangedSubview(topRow)
        stack.setCustomSpacing(8, after: topRow)
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(10, after: titleLabel)
        stack.addArrangedSubview(waveform)
        stack.setCustomSpacing(10, after: waveform)
        stack.addArrangedSubview(footerStack)
        stack.addArrangedSubview(missingLabel)
        stack.setCustomSpacing(5, after: footerStack)

        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 16, left: 17, bottom: 15, right: 17))
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with record: RecordingEntity, showPlace: Bool = true, dateText: String? = nil) {
        self.record = record
        recordingID = record.id
        let placeName = record.place?.name ?? "Unassigned Recording"
        eyebrow.text = showPlace ? placeName : (record.place?.name ?? "Unassigned")
        placeIcon.isHidden = !showPlace
        dateLabel.text = dateText ?? SPFormat.shortDate.string(from: record.createdAt)
        titleLabel.text = record.title
        durationLabel.text = SPFormat.duration(record.duration)
        waveform.duration = record.duration
        waveform.cache = AudioAnalysisService.shared.waveform(for: record)
        waveform.accessibilityElementsHidden = true

        tagsStack.arrangedSubviews.forEach {
            tagsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for tag in record.tags.prefix(2) {
            tagsStack.addArrangedSubview(SPTagView(text: tag))
        }

        let exists = AppEnvironment.shared.storage.audioURL(for: record)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        missingLabel.isHidden = exists

        let placePart = showPlace ? placeName + ", " : ""
        accessibilityLabel = "\(record.title). \(placePart)\(SPFormat.dateTime(record.createdAt)), \(SPFormat.accessibleDuration(record.duration))"
        accessibilityHint = "Opens details"
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction]) {
                self.alpha = self.isHighlighted ? 0.8 : 1
                if !UIAccessibility.isReduceMotionEnabled {
                    self.transform = self.isHighlighted
                        ? CGAffineTransform(scaleX: 0.987, y: 0.987)
                        : .identity
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            layer.borderColor = SPColor.hairline.cgColor
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - 紧凑录音行

final class SPRecordingRowView: UIControl {
    private let iconTile = SPIconTile(symbol: "waveform", color: SPColor.accent, size: 42, pointSize: 15)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let durationLabel = UILabel()
    private let chevron = UIImageView()
    private var onTapHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        titleLabel.font = SPFont.text(15, weight: .semibold, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true

        durationLabel.font = SPFont.mono(11, weight: .medium, relativeTo: .caption1)
        durationLabel.textColor = SPColor.secondaryInk
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.adjustsFontForContentSizeCategory = true

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 7).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(durationLabel)
        row.addArrangedSubview(chevron)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 11, left: 4, bottom: 11, right: 4))
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with record: RecordingEntity, showPlace: Bool = true, onTap: (() -> Void)? = nil) {
        titleLabel.text = record.title
        let place = showPlace ? (record.place?.name ?? "Unassigned") : nil
        let date = SPFormat.relativeDate(record.createdAt) + " " + SPFormat.time.string(from: record.createdAt)
        subtitleLabel.text = [place, date].compactMap { $0 }.joined(separator: " · ")
        durationLabel.text = SPFormat.duration(record.duration)
        self.onTapHandler = onTap
        accessibilityLabel = "\(record.title), \(subtitleLabel.text ?? ""), \(SPFormat.accessibleDuration(record.duration))"
        accessibilityHint = "Opens details"
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }

    @objc private func tapped() {
        onTapHandler?()
    }
}

// MARK: - 地点卡片

final class SPPlaceCardView: UIControl {
    private let iconTile: SPIconTile
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let latestLabel = UILabel()
    private let tagsStack = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
    private let chevron = UIImageView()
    private let titleRow = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)
    private let archivedBadge = SPStatusBadge(text: "Archived", color: SPColor.tertiaryInk)
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        iconTile = SPIconTile(symbol: "mappin.and.ellipse", color: SPColor.accent, size: 46)
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.surface
        layer.cornerRadius = SPCardRadius.standard
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SPColor.hairline.cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button

        nameLabel.font = SPFont.display(19, relativeTo: .headline)
        nameLabel.textColor = SPColor.ink
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontForContentSizeCategory = true

        metaLabel.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
        metaLabel.textColor = SPColor.secondaryInk
        metaLabel.adjustsFontForContentSizeCategory = true

        latestLabel.font = SPFont.mono(10.5, weight: .regular, relativeTo: .caption2)
        latestLabel.textColor = SPColor.tertiaryInk
        latestLabel.adjustsFontForContentSizeCategory = true

        archivedBadge.isHidden = true
        titleRow.addArrangedSubview(nameLabel)
        titleRow.addArrangedSubview(archivedBadge)
        titleRow.addArrangedSubview(UIView())

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 8).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 4)
        textStack.addArrangedSubview(titleRow)
        textStack.addArrangedSubview(metaLabel)
        textStack.addArrangedSubview(latestLabel)
        textStack.setCustomSpacing(7, after: latestLabel)
        textStack.addArrangedSubview(tagsStack)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(iconTile)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(chevron)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15))
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with place: PlaceEntity) {
        let color = place.kind.color
        iconTile.update(symbol: place.kind.symbolName, color: color)

        nameLabel.text = place.name
        let count = place.recordings.count
        metaLabel.text = "\(place.kind.title) · \(count) recordings"
        latestLabel.text = SPFormat.lastRecorded(place.sortedRecordings.first?.createdAt)
        archivedBadge.isHidden = place.archivedAt == nil

        tagsStack.arrangedSubviews.forEach {
            tagsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for tag in place.tags.prefix(3) {
            tagsStack.addArrangedSubview(SPTagView(text: tag, color: color, background: place.kind.softColor))
        }
        tagsStack.addArrangedSubview(UIView())

        accessibilityLabel = "\(place.name). \(place.kind.title), \(count) recordings. \(latestLabel.text ?? "")"
        accessibilityHint = "Opens place details"
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction]) {
                self.alpha = self.isHighlighted ? 0.78 : 1
                if !UIAccessibility.isReduceMotionEnabled {
                    self.transform = self.isHighlighted
                        ? CGAffineTransform(scaleX: 0.988, y: 0.988)
                        : .identity
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            layer.borderColor = SPColor.hairline.cgColor
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - 首页横向地点卡片

final class SPPlaceMiniCardView: UIControl {
    private let iconTile: SPIconTile
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let lastLabel = UILabel()
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        iconTile = SPIconTile(symbol: "leaf.fill", color: SPColor.moss, size: 36, pointSize: 14)
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.surface
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SPColor.hairline.cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button
        widthAnchor.constraint(equalToConstant: 178).isActive = true

        nameLabel.font = SPFont.display(17, relativeTo: .headline)
        nameLabel.textColor = SPColor.ink
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true

        countLabel.font = SPFont.text(11, weight: .medium, relativeTo: .caption1)
        countLabel.textColor = SPColor.secondaryInk
        countLabel.adjustsFontForContentSizeCategory = true

        lastLabel.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
        lastLabel.textColor = SPColor.tertiaryInk
        lastLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(axis: .vertical, spacing: 0)
        stack.addArrangedSubview(iconTile)
        stack.setCustomSpacing(12, after: iconTile)
        stack.addArrangedSubview(nameLabel)
        stack.setCustomSpacing(4, after: nameLabel)
        stack.addArrangedSubview(countLabel)
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(lastLabel)
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with place: PlaceEntity) {
        iconTile.update(symbol: place.kind.symbolName, color: place.kind.color)
        nameLabel.text = place.name
        countLabel.text = "\(place.recordings.count) recordings"
        lastLabel.text = SPFormat.lastRecorded(place.sortedRecordings.first?.createdAt)
        accessibilityLabel = "\(place.name), \(place.recordings.count) recordings"
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    @objc private func tapped() { onTap?() }
}

// MARK: - 指标

final class SPMetricTile: UIView {
    private let label = UILabel()
    private let valueLabel = UILabel()
    private let unitLabel = UILabel()

    init(title: String, value: String, unit: String? = nil, accent: UIColor = SPColor.ink) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.sunken
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        label.text = title
        label.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        label.textColor = SPColor.secondaryInk
        label.adjustsFontForContentSizeCategory = true

        valueLabel.text = value
        valueLabel.font = SPFont.mono(22, weight: .medium, relativeTo: .title3)
        valueLabel.textColor = accent
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        unitLabel.text = unit
        unitLabel.font = SPFont.text(10, weight: .medium, relativeTo: .caption2)
        unitLabel.textColor = SPColor.tertiaryInk
        unitLabel.adjustsFontForContentSizeCategory = true

        let valueRow = UIStackView(axis: .horizontal, spacing: 3, alignment: .lastBaseline)
        valueRow.addArrangedSubview(valueLabel)
        if unit != nil {
            valueRow.addArrangedSubview(unitLabel)
        }
        let stack = UIStackView(axis: .vertical, spacing: 4)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(valueRow)
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 66).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(value)\(unit ?? "")"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 频带占比条

final class SPBandCompositionView: UIView {
    private let titleLabel = UILabel()
    private let bar = SPSegmentedBarView()
    private var legendLabels: [UILabel] = []

    init(title: String = "Frequency band composition") {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        let specs: [(String, UIColor)] = [
            ("Low band", SPColor.waveform),
            ("Mid band", SPColor.amber),
            ("High band", SPColor.accent)
        ]
        let legend = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        for spec in specs {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = spec.1
            dot.layer.cornerRadius = 2.5
            dot.widthAnchor.constraint(equalToConstant: 5).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 5).isActive = true
            let label = UILabel()
            label.text = spec.0
            label.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
            label.textColor = SPColor.secondaryInk
            label.adjustsFontForContentSizeCategory = true
            legendLabels.append(label)
            let item = UIStackView(axis: .horizontal, spacing: 4, alignment: .center)
            item.addArrangedSubview(dot)
            item.addArrangedSubview(label)
            legend.addArrangedSubview(item)
        }
        legend.addArrangedSubview(UIView())

        let stack = UIStackView(axis: .vertical, spacing: 9)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bar)
        stack.addArrangedSubview(legend)
        addSubview(stack)
        stack.pinEdges(to: self)
        isAccessibilityElement = true
        accessibilityLabel = "Frequency band composition"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(bands: BandShares) {
        bar.setSegments([
            (CGFloat(bands.low), SPColor.waveform),
            (CGFloat(bands.mid), SPColor.amber),
            (CGFloat(bands.high), SPColor.accent)
        ])
        if legendLabels.count == 3 {
            legendLabels[0].text = "Low band \(SPFormat.percent(bands.low))"
            legendLabels[1].text = "Mid band \(SPFormat.percent(bands.mid))"
            legendLabels[2].text = "High band \(SPFormat.percent(bands.high))"
        }
        accessibilityValue = "Low band \(SPFormat.percent(bands.low)), Mid band \(SPFormat.percent(bands.mid)), High band \(SPFormat.percent(bands.high))"
    }
}

// MARK: - 存储概览

final class SPStorageSummaryView: UIView {
    private let bar = SPSegmentedBarView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let lockIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        lockIcon.translatesAutoresizingMaskIntoConstraints = false
        lockIcon.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        lockIcon.tintColor = SPColor.moss
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.widthAnchor.constraint(equalToConstant: 11).isActive = true
        lockIcon.heightAnchor.constraint(equalToConstant: 11).isActive = true

        titleLabel.text = "On-Device Storage"
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .footnote)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = SPFont.mono(10.5, weight: .regular, relativeTo: .caption2)
        detailLabel.textColor = SPColor.tertiaryInk
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true

        let header = UIStackView(axis: .horizontal, spacing: 5, alignment: .center)
        header.addArrangedSubview(lockIcon)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(UIView())

        let stack = UIStackView(axis: .vertical, spacing: 8)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(bar)
        stack.addArrangedSubview(detailLabel)
        addSubview(stack)
        stack.pinEdges(to: self)
        isAccessibilityElement = true
        accessibilityLabel = "On-Device Storage"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(stats: StorageStats) {
        bar.setSegments([
            (CGFloat(stats.audioBytes), SPColor.accent),
            (CGFloat(stats.cacheBytes), SPColor.amber)
        ])
        let used = SPFormat.fileSize(stats.audioBytes + stats.cacheBytes)
        let free = SPFormat.fileSize(stats.availableBytes)
        detailLabel.text = "Recordings \(stats.recordingCount) · Audio \(SPFormat.fileSize(stats.audioBytes)) · Cache \(SPFormat.fileSize(stats.cacheBytes))"
        accessibilityValue = "\(stats.recordingCount) recordings, \(used) used, \(free) available"
    }
}

enum SPCardRadius {
    static let standard: CGFloat = 20
}
