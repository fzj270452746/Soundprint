//
//  ExportOptionsViewController.swift
//  Soundprint
//
//  导出前明确选择是否附带元数据与精确坐标。默认不包含坐标。
//

import UIKit

final class ExportOptionsViewController: SPViewController {
    private let record: RecordingEntity
    private let onExport: (RecordingExportOptions) -> Void
    private let metadataRow: SPToggleRow
    private let locationRow: SPToggleRow

    init(record: RecordingEntity, onExport: @escaping (RecordingExportOptions) -> Void) {
        self.record = record
        self.onExport = onExport
        self.metadataRow = SPToggleRow(
            title: "Include Metadata",
            subtitle: "Exports the title, tags, notes, events, and analysis values as JSON.",
            isOn: true,
            symbol: "doc.text"
        )
        self.locationRow = SPToggleRow(
            title: "Include Precise Location",
            subtitle: "Location is not included by default.",
            isOn: false,
            symbol: "location"
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SPColor.paper
        buildInterface()
    }

    private func buildInterface() {
        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = SPColor.strongHairline
        grabber.layer.cornerRadius = 2.5
        grabber.widthAnchor.constraint(equalToConstant: 38).isActive = true
        grabber.heightAnchor.constraint(equalToConstant: 5).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = "Export"
        titleLabel.font = SPFont.display(27, relativeTo: .title1)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true

        let close = SPIconButton(symbol: "xmark", accessibilityLabel: "Close", style: .plain, pointSize: 14)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(close)

        let summary = UILabel()
        summary.text = "\(record.title)\n\(SPFormat.dateTime(record.createdAt)) · \(SPFormat.duration(record.duration)) · \(SPFormat.fileSize(record.fileSize))"
        summary.font = SPFont.text(12, weight: .regular, relativeTo: .footnote)
        summary.textColor = SPColor.secondaryInk
        summary.numberOfLines = 0
        summary.adjustsFontForContentSizeCategory = true

        let metadataCard = SPCardView(style: .surface)
        let metadataStack = UIStackView(axis: .vertical, spacing: 14)
        metadataStack.addArrangedSubview(metadataRow)
        metadataStack.addArrangedSubview(SPDivider())
        metadataStack.addArrangedSubview(locationRow)
        metadataCard.addContent(metadataStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        metadataRow.onChange = { [weak self] isOn in
            guard let self else { return }
            self.locationRow.toggle.isEnabled = isOn
            self.locationRow.alpha = isOn ? 1 : 0.4
            if !isOn {
                self.locationRow.toggle.setOn(false, animated: true)
            }
        }

        let banner = SPInfoBanner(
            title: nil,
            message: "Only the content you select is passed to the app or service you share with. Even with location excluded, the recording itself is not sent off this device.",
            tone: .neutral,
            symbol: "lock.shield"
        )

        let exportButton = SPButton(title: "Share", symbol: "square.and.arrow.up", style: .primary)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        let stack = UIStackView(axis: .vertical, spacing: 16)
        stack.addArrangedSubview(grabber)
        stack.setCustomSpacing(10, after: grabber)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(summary)
        stack.addArrangedSubview(metadataCard)
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(exportButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            grabber.centerXAnchor.constraint(equalTo: stack.centerXAnchor)
        ])

        locationRow.toggle.isEnabled = false
        locationRow.alpha = 0.4
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func exportTapped() {
        let options = RecordingExportOptions(
            includeMetadata: metadataRow.toggle.isOn,
            includeExactLocation: metadataRow.toggle.isOn && locationRow.toggle.isOn
        )
        dismiss(animated: true) { [onExport] in
            onExport(options)
        }
    }
}
