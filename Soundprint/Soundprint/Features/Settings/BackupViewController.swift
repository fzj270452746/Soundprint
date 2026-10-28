//
//  BackupViewController.swift
//  Soundprint
//
//  手动备份与恢复。导出的 ZIP 只在用户主动分享时离开应用沙盒。
//

import UIKit
import UniformTypeIdentifiers

final class BackupViewController: SPViewController {
    private let backupService = BackupService.shared
    private let includeLocationRow = SPToggleRow(
        title: "Include Exact Location",
        subtitle: "Not included by default. Recordings and metadata are still saved without location.",
        isOn: false,
        symbol: "location"
    )
    private let exportButton = SPButton(title: "Export Backup", symbol: "archivebox", style: .primary)
    private let importButton = SPButton(title: "Restore from Backup", symbol: "square.and.arrow.down", style: .secondary)
    private let lastBackupLabel = UILabel()
    private var preview: BackupPreview?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Backup & Restore"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        buildInterface()
    }

    private func buildInterface() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        let stack = UIStackView(axis: .vertical, spacing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let intro = SPInfoBanner(
            title: "Keep a Copy Beyond This Device.",
            message: "Pack recordings, places, events, and notes into a single ZIP. Export before switching devices, or in case something goes wrong.",
            tone: .info
        )
        stack.addArrangedSubview(intro)

        let exportCard = SPCardView(style: .surface)
        let exportStack = UIStackView(axis: .vertical, spacing: 13)
        let exportTitle = UILabel()
        exportTitle.text = "Export"
        exportTitle.font = SPFont.display(21, relativeTo: .title3)
        exportTitle.textColor = SPColor.ink
        exportTitle.adjustsFontForContentSizeCategory = true
        let exportDetail = UILabel()
        exportDetail.text = "Includes audio files, places.json / recordings.json / events.json, and a CSV index. Analysis caches such as waveforms are not included; they are regenerated after restoring."
        exportDetail.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
        exportDetail.textColor = SPColor.secondaryInk
        exportDetail.numberOfLines = 0
        exportDetail.adjustsFontForContentSizeCategory = true
        exportStack.addArrangedSubview(exportTitle)
        exportStack.addArrangedSubview(exportDetail)
        exportStack.addArrangedSubview(SPDivider())
        exportStack.addArrangedSubview(includeLocationRow)

        lastBackupLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        lastBackupLabel.textColor = SPColor.tertiaryInk
        lastBackupLabel.numberOfLines = 0
        lastBackupLabel.adjustsFontForContentSizeCategory = true
        updateLastBackupLabel()
        exportStack.addArrangedSubview(lastBackupLabel)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        exportStack.addArrangedSubview(exportButton)
        exportCard.addContent(exportStack, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        stack.addArrangedSubview(exportCard)

        let importCard = SPCardView(style: .surface)
        let importStack = UIStackView(axis: .vertical, spacing: 12)
        let importTitle = UILabel()
        importTitle.text = "Restore"
        importTitle.font = SPFont.display(21, relativeTo: .title3)
        importTitle.textColor = SPColor.ink
        importTitle.adjustsFontForContentSizeCategory = true
        let importDetail = UILabel()
        importDetail.text = "Reads a ZIP exported from Soundprint. Existing data is not deleted. For duplicate items, you can choose to skip them or add them as copies."
        importDetail.font = SPFont.text(11.5, weight: .regular, relativeTo: .caption1)
        importDetail.textColor = SPColor.secondaryInk
        importDetail.numberOfLines = 0
        importDetail.adjustsFontForContentSizeCategory = true
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        importStack.addArrangedSubview(importTitle)
        importStack.addArrangedSubview(importDetail)
        importStack.addArrangedSubview(importButton)
        importCard.addContent(importStack, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        stack.addArrangedSubview(importCard)

        stack.addArrangedSubview(SPInfoBanner(
            message: "Backups are never uploaded to the cloud automatically. You choose where an exported ZIP is saved and shared.",
            tone: .neutral,
            symbol: "lock.shield"
        ))

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func updateLastBackupLabel() {
        if let date = UserDefaults.standard.object(forKey: "sp.backup.lastExport") as? Date {
            lastBackupLabel.text = "Last backup: \(SPFormat.dateTime(date))"
        } else {
            lastBackupLabel.text = "No backup has been created yet."
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func exportTapped() {
        exportButton.isEnabled = false
        let overlay = SPLoadingOverlay(message: "Creating backup…")
        overlay.show(in: view)

        backupService.exportBackup(includeExactLocation: includeLocationRow.toggle.isOn) { [weak self] result in
            guard let self else { return }
            self.exportButton.isEnabled = true
            overlay.hide()
            switch result {
            case .success(let url):
                UserDefaults.standard.set(Date(), forKey: "sp.backup.lastExport")
                self.updateLastBackupLabel()
                SPShare.present(items: [url], from: self) {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                }
            case .failure(let error):
                self.presentError(error, title: "Could Not Create Backup")
            }
        }
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func prepareImport(url: URL) {
        let overlay = SPLoadingOverlay(message: "Verifying backup…")
        overlay.show(in: view)
        backupService.prepareImport(from: url) { [weak self] result in
            guard let self else { return }
            overlay.hide()
            switch result {
            case .success(let preview):
                self.preview = preview
                self.presentImportPreview(preview)
            case .failure(let error):
                self.presentError(error, title: "Could Not Read Backup")
            }
        }
    }

    private func presentImportPreview(_ preview: BackupPreview) {
        let manifest = preview.manifest
        var lines: [String] = []
        lines.append("\(preview.places.count) places · \(preview.recordings.count) recordings · \(preview.events.count) events")
        lines.append("Exported: \(SPFormat.dateTime(manifest.exportedAt)) (v\(manifest.appVersion))")
        if preview.duplicatePlaces > 0 || preview.duplicateRecordings > 0 {
            lines.append("Duplicates: \(preview.duplicatePlaces) places · \(preview.duplicateRecordings) recordings")
        }
        if preview.missingAudioCount > 0 {
            lines.append("Recordings with missing audio: \(preview.missingAudioCount) (skipped on import)")
        }
        if manifest.includesExactLocation {
            lines.append("Includes exact location.")
        }
        lines.append("Existing data is not deleted.")

        let alert = UIAlertController(
            title: "Restore Backup",
            message: lines.joined(separator: "\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            guard let self, let preview = self.preview else { return }
            self.backupService.discard(preview: preview)
            self.preview = nil
        })

        if preview.duplicateRecordings > 0 || preview.duplicatePlaces > 0 {
            alert.addAction(UIAlertAction(title: "Skip Duplicates", style: .default) { [weak self] _ in
                self?.startImport(strategy: .skip)
            })
            alert.addAction(UIAlertAction(title: "Add as Copies", style: .default) { [weak self] _ in
                self?.startImport(strategy: .copy)
            })
        } else {
            alert.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
                self?.startImport(strategy: .skip)
            })
        }
        present(alert, animated: true)
    }

    private func startImport(strategy: BackupDuplicateStrategy) {
        guard let preview else { return }
        let overlay = SPLoadingOverlay(message: "Restoring recordings and records…")
        overlay.show(in: view)
        backupService.importBackup(preview: preview, strategy: strategy) { [weak self] result in
            guard let self else { return }
            overlay.hide()
            self.preview = nil
            switch result {
            case .success(let summary):
                SPHaptic.success()
                let alert = UIAlertController(
                    title: "Restore Complete",
                    message: "Added \(summary.importedPlaces) places, \(summary.importedRecordings) recordings, and \(summary.importedEvents) events.\nSkipped: \(summary.skipped).",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Close", style: .default))
                self.present(alert, animated: true)
            case .failure(let error):
                self.presentError(error, title: "Could Not Restore")
            }
        }
    }
}

extension BackupViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        prepareImport(url: url)
    }
}
