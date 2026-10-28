//
//  PrivacyPolicyViewController.swift
//  Soundprint
//
//  与真实数据行为一致的应用内隐私说明。
//

import UIKit

final class PrivacyPolicyViewController: SPViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 20)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy Policy"
        hidesBottomBarWhenPushed = true
        buildInterface()
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let intro = SPInfoBanner(
            title: "Your Data, on This Device.",
            message: "Soundprint uses no accounts, advertising, analytics, or cloud sync. Recordings are never sent automatically to the developer or any third party. Apple Maps connects only when a map is displayed; recordings and notes are never transmitted.",
            tone: .success,
            symbol: "lock.shield"
        )
        contentStack.addArrangedSubview(intro)
        contentStack.addArrangedSubview(section(
            title: "1. Information We Store",
            body: "The app stores on your device the recording files you create, along with titles, place names and kinds, optional location data, tags, notes, weather, sound events, and analysis results. Location data is saved only when you explicitly choose to capture it."
        ))
        contentStack.addArrangedSubview(section(
            title: "2. Information We Do Not Store",
            body: "We do not collect your name, email address, phone number, contacts, account information, or advertising identifiers. The app does not transcribe conversations or identify speakers."
        ))
        contentStack.addArrangedSubview(section(
            title: "3. Permissions",
            body: "Microphone access is requested only when you start recording. Location access is requested only when you choose “Get Current Location.” The app does not use notification, photo, contacts, or tracking permissions. You can change permissions at any time in iOS Settings.\n\nOn iOS 16.2 and later, a Live Activity can show on the Lock Screen and Dynamic Island whether recording is active, along with elapsed time, place name, and recording quality. You can turn off Live Activities at any time in iOS Settings."
        ))
        contentStack.addArrangedSubview(section(
            title: "4. Sound Analysis",
            body: "Waveforms, RMS, peaks, frequency-band ratios, and simplified spectrograms are computed on-device using AVFoundation and Accelerate. No audio or data is sent to an external server for analysis. Maps that display location data use Apple Maps, which contacts Apple's services only to fetch map tiles.\n\nSound event suggestions are estimates generated from waveform energy changes on-device and are never confirmed automatically. An event is recorded only when you review a suggestion and save it."
        ))
        contentStack.addArrangedSubview(section(
            title: "5. Sharing and Export",
            body: "Sharing recordings, exporting metadata as JSON, creating comparison report PDFs, and making ZIP backups run only when you explicitly choose to do so. You decide where exported files are saved and shared. Location data is not included by default; you choose each time whether to include exact coordinates."
        ))
        contentStack.addArrangedSubview(section(
            title: "6. Device Backups",
            body: "App data may be included in the iOS device backup you have enabled. This is Apple's backup feature; Soundprint does not provide a cloud service of its own. You can manage what is backed up in iOS Settings."
        ))
        contentStack.addArrangedSubview(section(
            title: "7. Deletion",
            body: "Recordings can be deleted from their detail screen. When you delete a place, you can choose to delete its recordings with it or keep them as Unassigned Recordings. Delete All Data in Settings removes all recordings, places, events, and caches from the device at once."
        ))
        contentStack.addArrangedSubview(section(
            title: "8. Use by Minors",
            body: "The app does not ask for personal information or account registration. If a minor uses it under a guardian's supervision, please review the device's permission and backup settings."
        ))
        contentStack.addArrangedSubview(section(
            title: "9. Changes to This Policy",
            body: "If this policy changes as features are added, we will provide notice in the app or in the latest App Store information. We will notify you of significant changes when the app is updated."
        ))
        contentStack.addArrangedSubview(section(
            title: "10. Contact",
            body: "For questions about this app, please contact us through the App Store support page."
        ))
        let updated = UILabel()
        updated.text = "Last updated: October 22, 2026 (Version 1.1)"
        updated.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        updated.textColor = SPColor.tertiaryInk
        updated.adjustsFontForContentSizeCategory = true
        contentStack.addArrangedSubview(updated)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func section(title: String, body: String) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 8)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = SPFont.display(18, relativeTo: .headline)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = SPFont.text(13, weight: .regular, relativeTo: .body)
        bodyLabel.textColor = SPColor.secondaryInk
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.setLineHeight(1.65)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 16, bottom: 17, right: 16))
        return card
    }
}

extension UILabel {
    func setLineHeight(_ multiple: CGFloat) {
        guard let text else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = multiple
        attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font as Any,
                .foregroundColor: textColor as Any,
                .paragraphStyle: paragraph
            ]
        )
    }
}
