//
//  AboutViewController.swift
//  Soundprint
//
//  产品理念与技术说明。
//

import UIKit

final class AboutViewController: SPViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About Soundprint"
        hidesBottomBarWhenPushed = true
        buildInterface()
    }

    private func buildInterface() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        let stack = UIStackView(axis: .vertical, spacing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let art = SPOrbitalArtView(variant: .large)
        let wordmark = UILabel()
        wordmark.text = "Soundprint"
        wordmark.font = SPFont.wordmark(34)
        wordmark.textColor = SPColor.ink
        wordmark.textAlignment = .center
        wordmark.adjustsFontForContentSizeCategory = true
        let tagline = UILabel()
        tagline.text = "Sound is a place's memory."
        tagline.font = SPFont.display(20, relativeTo: .title3)
        tagline.textColor = SPColor.accent
        tagline.textAlignment = .center
        tagline.adjustsFontForContentSizeCategory = true
        let versionLabel = UILabel()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        versionLabel.text = "Version \(version) (\(build))"
        versionLabel.font = SPFont.mono(10, weight: .regular, relativeTo: .caption2)
        versionLabel.textColor = SPColor.tertiaryInk
        versionLabel.textAlignment = .center
        versionLabel.adjustsFontForContentSizeCategory = true

        let artContainer = UIView()
        artContainer.translatesAutoresizingMaskIntoConstraints = false
        artContainer.addSubview(art)
        NSLayoutConstraint.activate([
            art.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            art.topAnchor.constraint(equalTo: artContainer.topAnchor),
            art.bottomAnchor.constraint(equalTo: artContainer.bottomAnchor),
            artContainer.heightAnchor.constraint(equalToConstant: 214)
        ])
        stack.addArrangedSubview(artContainer)
        stack.setCustomSpacing(8, after: artContainer)
        stack.addArrangedSubview(wordmark)
        stack.addArrangedSubview(tagline)
        stack.addArrangedSubview(versionLabel)

        let introCard = SPCardView(style: .surface)
        let intro = UILabel()
        intro.text = "Soundprint is a local tool for street corners, rooms, shorelines, and workshops. It keeps the sound of places you notice over time, so you can compare one day with another.\n\nWe built it not to consume sound as “the present state,” but to observe how a place changes over the long term."
        intro.font = SPFont.text(14, weight: .regular, relativeTo: .body)
        intro.textColor = SPColor.secondaryInk
        intro.numberOfLines = 0
        intro.adjustsFontForContentSizeCategory = true
        intro.setLineHeight(1.65)
        introCard.addContent(intro, insets: UIEdgeInsets(top: 18, left: 17, bottom: 18, right: 17))
        stack.addArrangedSubview(introCard)

        stack.addArrangedSubview(makeSection(title: "Design", items: [
            ("lock.shield", "Local First", "Recordings and records are stored on-device. No accounts, advertising, analytics SDKs, or cloud sync."),
            ("waveform", "Original Audio First", "Recordings are saved as AAC / M4A, while waveforms and analysis results are treated as regenerable caches."),
            ("arrow.triangle.2.circlepath", "Durable Saves", "Writes to a temporary file and moves it to its final location only after completion."),
            ("hand.raised", "Location Is Optional", "You can choose not to save location data, and choose whether to include coordinates when sharing.")
        ]))

        stack.addArrangedSubview(makeSection(title: "Technology", items: [
            ("cpu", "On-Device Signal Processing", "Waveform, RMS, and FFT analysis with AVFoundation, Accelerate, and vDSP."),
            ("externaldrive", "Core Data", "Metadata and audio files are managed separately."),
            ("iphone", "iOS 15 and Later", "Optimized for iPhone in portrait. Supports Dynamic Type, VoiceOver, and Dark Mode.")
        ]))

        stack.addArrangedSubview(SPInfoBanner(
            title: "About Measurements",
            message: "This app is not a calibrated sound level meter. RMS, peak, and frequency-band values are relative measurements of the recorded signal and cannot be used for dB SPL readings or regulatory determinations.",
            tone: .warning,
            symbol: "exclamationmark.triangle"
        ))

        let copyright = UILabel()
        copyright.text = "© 2026 Soundprint\nFor quiet observation."
        copyright.font = SPFont.text(10, weight: .regular, relativeTo: .caption2)
        copyright.textColor = SPColor.tertiaryInk
        copyright.textAlignment = .center
        copyright.numberOfLines = 0
        copyright.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(copyright)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: SPMetric.screenInset),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -SPMetric.screenInset),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset)
        ])
    }

    private func makeSection(title: String, items: [(String, String, String)]) -> UIView {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = SPFont.display(19, relativeTo: .headline)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(titleLabel)
        for (symbol, heading, body) in items {
            let icon = SPIconTile(symbol: symbol, color: SPColor.accent, size: 32, pointSize: 12)
            let headingLabel = UILabel()
            headingLabel.text = heading
            headingLabel.font = SPFont.text(13, weight: .semibold, relativeTo: .subheadline)
            headingLabel.textColor = SPColor.ink
            headingLabel.adjustsFontForContentSizeCategory = true
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.font = SPFont.text(11, weight: .regular, relativeTo: .caption1)
            bodyLabel.textColor = SPColor.secondaryInk
            bodyLabel.numberOfLines = 0
            bodyLabel.adjustsFontForContentSizeCategory = true
            let textStack = UIStackView(axis: .vertical, spacing: 2)
            textStack.addArrangedSubview(headingLabel)
            textStack.addArrangedSubview(bodyLabel)
            let row = UIStackView(axis: .horizontal, spacing: 10, alignment: .top)
            row.addArrangedSubview(icon)
            row.addArrangedSubview(textStack)
            stack.addArrangedSubview(row)
        }
        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 17, bottom: 17, right: 17))
        return card
    }
}
