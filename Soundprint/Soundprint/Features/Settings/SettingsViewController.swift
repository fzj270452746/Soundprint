//
//  SettingsViewController.swift
//  Soundprint
//
//  录音质量、存储、备份、隐私与数据删除。所有选项都直接反映本地行为。
//

import UIKit

final class SettingsViewController: SPViewController {
    private let library = LibraryService.shared
    private let storage = StorageManager.shared
    private let analysis = AudioAnalysisService.shared
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 24)
    private let qualityRow = SettingsRow(title: "Recording Quality", symbol: "waveform")
    private let autoAnalysisToggle = SPToggleRow(
        title: "Analyze Sound Automatically",
        subtitle: "Computes the waveform, RMS, and frequency bands on-device after saving.",
        isOn: true,
        symbol: "waveform.path.ecg"
    )
    private let suggestionToggle = SPToggleRow(
        title: "Show Sound Event Suggestions",
        subtitle: "Suggests events from on-device volume changes. Suggestions are not confirmed events.",
        isOn: true,
        symbol: "waveform"
    )
    private let storageSummary = SPStorageSummaryView()
    private let cacheRow = SettingsRow(title: "Clear Cache", symbol: "arrow.clockwise")
    private let integrityRow = SettingsRow(title: "Check Data Integrity", symbol: "checkmark.shield")
    private let storageDetailLabel = UILabel()
    private var stats: StorageStats?
    private var statsWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        observe()
        refreshPreferences()
        refreshStorage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshPreferences()
        refreshStorage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private func buildInterface() {
        let header = UIStackView(axis: .vertical, spacing: 3)
        let title = UILabel()
        title.text = "Settings"
        title.font = SPFont.display(34, relativeTo: .largeTitle)
        title.textColor = SPColor.ink
        title.adjustsFontForContentSizeCategory = true
        let subtitle = UILabel()
        subtitle.text = "The quality of your records, and how your data is handled."
        subtitle.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
        subtitle.textColor = SPColor.tertiaryInk
        subtitle.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(subtitle)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])

        buildRecordingSection()
        buildStorageSection()
        buildBackupSection()
        buildPrivacySection()
        buildDataSection()
        buildAboutSection()

        let footer = UILabel()
        footer.text = "Soundprint does not use cloud sync.\nYour recordings and records live only on this device."
        footer.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        footer.textColor = SPColor.tertiaryInk
        footer.textAlignment = .center
        footer.numberOfLines = 0
        footer.adjustsFontForContentSizeCategory = true
        contentStack.addArrangedSubview(footer)
    }

    private func makeSection(title: String, card: UIView) -> UIView {
        let section = UIStackView(axis: .vertical, spacing: 10)
        section.addArrangedSubview(UILabel.sectionLabel(title))
        section.addArrangedSubview(card)
        return section
    }

    private func buildRecordingSection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        qualityRow.addTarget(self, action: #selector(qualityTapped), for: .touchUpInside)
        stack.addArrangedSubview(qualityRow)
        stack.addArrangedSubview(SPDivider())
        autoAnalysisToggle.toggle.addTarget(self, action: #selector(autoAnalysisChanged), for: .valueChanged)
        let toggleWrapper = UIView()
        toggleWrapper.addSubview(autoAnalysisToggle)
        autoAnalysisToggle.pinEdges(to: toggleWrapper, insets: UIEdgeInsets(top: 12, left: 15, bottom: 12, right: 15))
        stack.addArrangedSubview(toggleWrapper)
        stack.addArrangedSubview(SPDivider())
        suggestionToggle.toggle.addTarget(self, action: #selector(suggestionsChanged), for: .valueChanged)
        let suggestionWrapper = UIView()
        suggestionWrapper.addSubview(suggestionToggle)
        suggestionToggle.pinEdges(to: suggestionWrapper, insets: UIEdgeInsets(top: 12, left: 15, bottom: 12, right: 15))
        stack.addArrangedSubview(suggestionWrapper)

        let note = UILabel()
        note.text = "Quality applies from your next recording. Recordings are saved as AAC / M4A. Waveforms are always generated, and you can analyze manually even with automatic analysis off."
        note.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true
        let noteWrapper = UIView()
        noteWrapper.addSubview(note)
        note.pinEdges(to: noteWrapper, insets: UIEdgeInsets(top: 10, left: 15, bottom: 14, right: 15))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(noteWrapper)
        card.addContent(stack, insets: UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0))
        contentStack.addArrangedSubview(makeSection(title: "Recording & Analysis", card: card))
    }

    private func buildStorageSection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 14)
        stack.addArrangedSubview(storageSummary)

        storageDetailLabel.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
        storageDetailLabel.textColor = SPColor.secondaryInk
        storageDetailLabel.numberOfLines = 0
        storageDetailLabel.adjustsFontForContentSizeCategory = true
        storageDetailLabel.text = "Calculating…"
        stack.addArrangedSubview(storageDetailLabel)
        stack.addArrangedSubview(SPDivider())

        cacheRow.addTarget(self, action: #selector(clearCacheTapped), for: .touchUpInside)
        integrityRow.addTarget(self, action: #selector(integrityTapped), for: .touchUpInside)
        stack.addArrangedSubview(cacheRow)
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(integrityRow)
        card.addContent(stack, insets: UIEdgeInsets(top: 16, left: 15, bottom: 4, right: 15))
        contentStack.addArrangedSubview(makeSection(title: "Local Storage", card: card))
    }

    private func buildBackupSection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let backupRow = SettingsRow(title: "Backup & Restore", symbol: "archivebox")
        backupRow.value = "ZIP"
        backupRow.addTarget(self, action: #selector(backupTapped), for: .touchUpInside)
        stack.addArrangedSubview(backupRow)
        let note = UILabel()
        note.text = "Before switching devices or deleting the app, export your audio and records to a location you control. Analysis results are regenerated after restoring."
        note.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true
        let wrapper = UIView()
        wrapper.addSubview(note)
        note.pinEdges(to: wrapper, insets: UIEdgeInsets(top: 0, left: 15, bottom: 14, right: 15))
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(wrapper)
        card.addContent(stack, insets: UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0))
        contentStack.addArrangedSubview(makeSection(title: "Backup", card: card))
    }

    private func buildPrivacySection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let permissions = SettingsRow(title: "Microphone & Location Access", symbol: "hand.raised")
        permissions.value = "Settings"
        permissions.addTarget(self, action: #selector(openSystemSettings), for: .touchUpInside)
        let privacy = SettingsRow(title: "Privacy Policy", symbol: "lock.shield")
        privacy.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)
        stack.addArrangedSubview(permissions)
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(privacy)
        card.addContent(stack, insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        contentStack.addArrangedSubview(makeSection(title: "Privacy", card: card))
        contentStack.addArrangedSubview(SPInfoBanner(
            title: "Recordings Are Not Sent Off-Device",
            message: "No accounts, advertising, analytics SDKs, or cloud sync. Apple Maps is used only to display maps. Recordings and records are never sent automatically.",
            tone: .success,
            symbol: "lock.shield"
        ))
    }

    private func buildDataSection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let delete = SettingsRow(title: "Delete All Data", symbol: "trash", danger: true)
        delete.addTarget(self, action: #selector(deleteAllTapped), for: .touchUpInside)
        stack.addArrangedSubview(delete)
        card.addContent(stack, insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        contentStack.addArrangedSubview(makeSection(title: "Data", card: card))
    }

    private func buildAboutSection() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 0)
        let about = SettingsRow(title: "About Soundprint", symbol: "info.circle")
        about.addTarget(self, action: #selector(aboutTapped), for: .touchUpInside)
        let version = SettingsRow(title: "Version", symbol: "number")
        let info = Bundle.main.infoDictionary
        let versionString = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        version.value = "\(versionString) (\(build))"
        version.isUserInteractionEnabled = false
        stack.addArrangedSubview(about)
        stack.addArrangedSubview(SPDivider())
        stack.addArrangedSubview(version)
        card.addContent(stack, insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        contentStack.addArrangedSubview(makeSection(title: "About This App", card: card))
    }

    // MARK: - 偏好

    private func refreshPreferences() {
        let quality = RecordingQuality.current
        qualityRow.value = quality.title
        autoAnalysisToggle.toggle.isOn = UserDefaults.standard.object(forKey: SPDefaultsKey.autoAnalysis) as? Bool ?? true
        suggestionToggle.toggle.isOn = EventSuggestionService.isEnabled
    }

    @objc private func suggestionsChanged() {
        let isOn = suggestionToggle.toggle.isOn
        UserDefaults.standard.set(isOn, forKey: SPDefaultsKey.suggestEvents)
        if isOn {
            EventSuggestionService.shared.scheduleAllIfNeeded()
            SPToast.show("Sound event suggestions turned on", in: view, symbol: "waveform")
        } else {
            SPToast.show("Sound event suggestions turned off", in: view, symbol: "waveform")
        }
    }

    @objc private func qualityTapped() {
        let current = RecordingQuality.current
        let sheet = UIAlertController(
            title: "Recording Quality",
            message: "Applies from your next recording.",
            preferredStyle: .actionSheet
        )
        for quality in RecordingQuality.allCases {
            let prefix = quality == current ? "✓ " : ""
            sheet.addAction(UIAlertAction(
                title: "\(prefix)\(quality.title) — \(quality.detail)",
                style: .default
            ) { _ in
                RecordingQuality.setCurrent(quality)
                self.qualityRow.value = quality.title
                SPHaptic.selection()
                SPToast.show("Recording quality changed to “\(quality.title)”", in: self.view, symbol: "waveform")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = qualityRow
            popover.sourceRect = qualityRow.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func autoAnalysisChanged() {
        let isOn = autoAnalysisToggle.toggle.isOn
        UserDefaults.standard.set(isOn, forKey: SPDefaultsKey.autoAnalysis)
        guard isOn else {
            SPToast.show("Automatic analysis turned off", in: view, symbol: "waveform")
            return
        }
        let records = library.fetchRecordings().filter { $0.analysisState != .ready }
        for record in records {
            analysis.schedule(recordingID: record.id, force: false)
        }
        SPToast.show("Automatic analysis turned on", in: view, symbol: "waveform.path.ecg")
    }

    // MARK: - 存储

    private func observe() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageChanged),
            name: SPNotification.storageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageChanged),
            name: SPNotification.libraryDidChange,
            object: nil
        )
    }

    @objc private func storageChanged() {
        refreshStorage()
    }

    private func refreshStorage() {
        statsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.storage.stats { stats in
                self.stats = stats
                self.applyStats(stats)
            }
        }
        statsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func applyStats(_ stats: StorageStats) {
        storageSummary.configure(stats: stats)
        storageDetailLabel.text = "Available storage: \(SPFormat.fileSize(stats.availableBytes))"
        cacheRow.value = SPFormat.fileSize(stats.cacheBytes)
    }

    @objc private func clearCacheTapped() {
        let size = stats.map { SPFormat.fileSize($0.cacheBytes) } ?? "Cache"
        presentConfirm(
            title: "Delete Waveform and Analysis Caches?",
            message: "This deletes \(size) of regenerable data. Audio files are not deleted. Analyzed recordings will be analyzed again.",
            destructiveTitle: "Clear Cache"
        ) { [weak self] in
            guard let self else { return }
            let overlay = SPLoadingOverlay(message: "Clearing cache…")
            overlay.show(in: self.view)
            DispatchQueue.main.async {
                do {
                    try self.library.clearCachesAndScheduleRegeneration()
                    self.analysis.invalidateCaches()
                    overlay.hide()
                    self.refreshStorage()
                    SPToast.show("Cache cleared", in: self.view)
                } catch {
                    overlay.hide()
                    self.presentError(error)
                }
            }
        }
    }

    @objc private func integrityTapped() {
        let overlay = SPLoadingOverlay(message: "Checking data…")
        overlay.show(in: view)
        library.integrityReport { [weak self] report in
            guard let self else { return }
            overlay.hide()
            var lines: [String] = []
            lines.append("Recordings with missing audio: \(report.missingAudio.count)")
            lines.append("Orphaned audio files: \(report.orphanAudio.count)")
            lines.append("Orphaned caches: \(report.orphanCache.count)")
            lines.append("Pending deletions: \(report.pendingDeletions.count)")
            if !report.hasIssues {
                lines.append("")
                lines.append("No issues found.")
            } else if !report.missingAudio.isEmpty {
                lines.append("")
                lines.append("Recordings with missing audio can be deleted from their detail screen while keeping their metadata.")
            }
            let alert = UIAlertController(title: "Data Integrity", message: lines.joined(separator: "\n"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel))
            if !report.orphanAudio.isEmpty || !report.orphanCache.isEmpty || !report.pendingDeletions.isEmpty {
                alert.addAction(UIAlertAction(title: "Clean Up Orphaned Files", style: .default) { [weak self] _ in
                    guard let self else { return }
                    let cleaning = SPLoadingOverlay(message: "Cleaning up files…")
                    cleaning.show(in: self.view)
                    self.library.cleanOrphans { audio, cache in
                        cleaning.hide()
                        self.refreshStorage()
                        SPToast.show("Cleaned up \(audio) audio files and \(cache) caches", in: self.view)
                    }
                })
            }
            self.present(alert, animated: true)
        }
    }

    // MARK: - 其他

    @objc private func backupTapped() {
        let controller = BackupViewController()
        let nav = UINavigationController(rootViewController: controller)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func privacyTapped() {
        let controller = PrivacyPolicyViewController()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func aboutTapped() {
        let controller = AboutViewController()
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func deleteAllTapped() {
        let first = UIAlertController(
            title: "Delete All Data",
            message: "This deletes all Soundprint local data, including recordings, places, events, analysis caches, and backup history. This cannot be undone.",
            preferredStyle: .alert
        )
        first.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        first.addAction(UIAlertAction(title: "Next", style: .destructive) { [weak self] _ in
            self?.confirmDeleteAll()
        })
        present(first, animated: true)
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(
            title: "Final Confirmation",
            message: "Type “Delete” to continue. If you have not exported a backup, your data cannot be recovered.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Delete"
            field.autocapitalizationType = .none
            field.font = SPFont.text(15)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self, weak alert] _ in
            guard let self else { return }
            guard alert?.textFields?.first?.text == "Delete" else {
                self.presentAlert(title: "Could Not Delete", message: "Type “Delete” to confirm.")
                return
            }
            self.performDeleteAll()
        })
        present(alert, animated: true)
    }

    private func performDeleteAll() {
        let overlay = SPLoadingOverlay(message: "Deleting local data…")
        overlay.show(in: view)
        do {
            try library.deleteAllData()
            RecordingDraftStore.shared.clear()
            analysis.invalidateCaches()
            UserDefaults.standard.removeObject(forKey: "sp.backup.lastExport")
            overlay.hide()
            SPHaptic.success()
            refreshStorage()
            SPToast.show("All data deleted", in: view, symbol: "trash")
        } catch {
            overlay.hide()
            presentError(error, title: "Could Not Delete")
        }
    }
}

// MARK: - 设置行

private final class SettingsRow: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevron = UIImageView()

    var value: String? {
        get { valueLabel.text }
        set {
            valueLabel.text = newValue
            valueLabel.isHidden = newValue == nil
            accessibilityValue = newValue
        }
    }

    init(title: String, symbol: String, danger: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        iconView.tintColor = danger ? SPColor.danger : SPColor.secondaryInk
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        titleLabel.text = title
        titleLabel.font = SPFont.text(14.5, weight: .regular, relativeTo: .body)
        titleLabel.textColor = danger ? SPColor.danger : SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = SPFont.text(11.5, weight: .regular, relativeTo: .footnote)
        valueLabel.textColor = SPColor.tertiaryInk
        valueLabel.textAlignment = .right
        valueLabel.isHidden = true
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.widthAnchor.constraint(equalToConstant: 7).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 11).isActive = true

        let row = UIStackView(axis: .horizontal, spacing: 11, alignment: .center)
        row.isUserInteractionEnabled = false
        row.addArrangedSubview(iconView)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(chevron)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 13, left: 15, bottom: 13, right: 15))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.62 : 1 }
    }
}
