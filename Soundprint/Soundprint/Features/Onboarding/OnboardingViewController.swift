//
//  OnboardingViewController.swift
//  Soundprint
//
//  首次启动的三页引导。不请求任何权限，只说明产品价值与本地隐私原则。
//

import UIKit

final class OnboardingViewController: UIViewController {
    private let onFinish: () -> Void

    private let scrollView = UIScrollView()
    private let pagesStack = UIStackView(axis: .horizontal, spacing: 0)
    private let dotsView = UIStackView(axis: .horizontal, spacing: 7, alignment: .center)
    private let primaryButton = SPButton(title: "Next", symbol: "arrow.right", style: .primary)
    private let skipButton = SPTextButton(title: "Skip")
    private var pages: [OnboardingPageView] = []
    private var currentIndex = 0
    private var headerWordmark: UILabel!
    private var headerView: UIView!
    private var footerView: UIView!

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SPColor.paper
        buildHeader()
        buildFooter()
        buildPages()
        view.bringSubviewToFront(headerView)
        view.bringSubviewToFront(footerView)
        updateFooter(animated: false)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pages.first?.artView.startAnimating()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pages.forEach { $0.artView.stopAnimating() }
    }

    // MARK: - 顶部

    private func buildHeader() {
        headerWordmark = UILabel()
        headerWordmark.text = "Soundprint"
        headerWordmark.font = SPFont.wordmark(27)
        headerWordmark.textColor = SPColor.ink
        headerWordmark.adjustsFontForContentSizeCategory = true

        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        let header = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        header.addArrangedSubview(headerWordmark)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(skipButton)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset + 4),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
        headerView = header
    }

    // MARK: - 页面

    private func buildPages() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never

        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(pagesStack)
        view.addSubview(scrollView)

        let pageModels: [(String, String, String, OnboardingPageView.Art)] = [
            (
                "A Field Notebook for Sound",
                "The sound of a place,\nover time.",
                "A street corner, a room, a shoreline. Keep the sounds you notice where they happened, and listen back another day. Soundprint is a notebook for observing the sound of a place over time.",
                .orbital
            ),
            (
                "Listen for Change",
                "The same place,\nacross different days.",
                "Compare waveform, level, and frequency trends side by side. Recording conditions are noted as well, so you can read environmental change carefully.",
                .compare
            ),
            (
                "Local First",
                "All of it,\non this device.",
                "No account, no cloud. Recordings and records are stored only on this device, with no ads and no tracking.",
                .privacy
            )
        ]

        for model in pageModels {
            let page = OnboardingPageView(kicker: model.0, title: model.1, body: model.2, art: model.3)
            pages.append(page)
            pagesStack.addArrangedSubview(page)
            page.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).isActive = true
            page.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            pagesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        // 页面内容留出顶部与底部的固定区域。
        pages.forEach { page in
            page.contentTopInset = 96
            page.contentBottomInset = 16
        }
    }

    private func buildFooter() {
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        footerView = footer

        dotsView.translatesAutoresizingMaskIntoConstraints = false
        dotsView.alignment = .center
        let dotContainer = UIView()
        dotContainer.translatesAutoresizingMaskIntoConstraints = false
        dotContainer.addSubview(dotsView)
        NSLayoutConstraint.activate([
            dotsView.centerXAnchor.constraint(equalTo: dotContainer.centerXAnchor),
            dotsView.centerYAnchor.constraint(equalTo: dotContainer.centerYAnchor),
            dotContainer.heightAnchor.constraint(equalToConstant: 6)
        ])

        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        let footerStack = UIStackView(axis: .vertical, spacing: 18, alignment: .fill)
        footerStack.addArrangedSubview(dotContainer)
        footerStack.addArrangedSubview(primaryButton)
        let legal = UILabel()
        legal.text = "No account · Offline · No ads"
        legal.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        legal.textColor = SPColor.tertiaryInk
        legal.textAlignment = .center
        legal.adjustsFontForContentSizeCategory = true
        footerStack.addArrangedSubview(legal)
        footerStack.setCustomSpacing(14, after: primaryButton)

        footer.addSubview(footerStack)
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            footerStack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: SPMetric.screenInset),
            footerStack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -SPMetric.screenInset),
            footerStack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            footerStack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 10)
        ])

        rebuildDots()
    }

    private func rebuildDots() {
        dotsView.arrangedSubviews.forEach {
            dotsView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for index in 0..<3 {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 3
            dot.layer.cornerCurve = .continuous
            dot.backgroundColor = index == currentIndex ? SPColor.accent : SPColor.strongHairline.withAlphaComponent(0.5)
            let width: CGFloat = index == currentIndex ? 20 : 6
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: width),
                dot.heightAnchor.constraint(equalToConstant: 6)
            ])
            dotsView.addArrangedSubview(dot)
        }
    }

    // MARK: - 交互

    @objc private func primaryTapped() {
        if currentIndex >= pages.count - 1 {
            finish()
            return
        }
        let next = currentIndex + 1
        scrollView.setContentOffset(
            CGPoint(x: CGFloat(next) * scrollView.bounds.width, y: 0),
            animated: true
        )
        setCurrent(index: next, animated: true)
        SPHaptic.light()
    }

    @objc private func skipTapped() {
        finish()
    }

    private func finish() {
        SPHaptic.success()
        onFinish()
    }

    private func setCurrent(index: Int, animated: Bool) {
        guard index != currentIndex, pages.indices.contains(index) else { return }
        currentIndex = index
        rebuildDots()
        primaryButton.title = index == pages.count - 1 ? "Get Started" : "Next"
        primaryButton.setSymbol(index == pages.count - 1 ? "arrow.right.circle.fill" : "arrow.right")
        if animated {
            let dotStack = dotsView
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                dotStack.layoutIfNeeded()
            }
        }
        pages.forEach { $0.artView.stopAnimating() }
        pages[index].artView.startAnimating()
    }

    private func updateFooter(animated: Bool) {
        currentIndex = 0
        rebuildDots()
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        if page != currentIndex {
            setCurrent(index: max(0, min(pages.count - 1, page)), animated: true)
        }
    }
}

// MARK: - 页面视图

private final class OnboardingPageView: UIView {
    enum Art {
        case orbital
        case compare
        case privacy
    }

    let artView: SPOrbitalArtView
    private let kickerLabel = UILabel()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let artContainer = UIView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 0, alignment: .center)

    var contentTopInset: CGFloat = 92 {
        didSet { topConstraint.constant = contentTopInset }
    }
    var contentBottomInset: CGFloat = 136 {
        didSet { bottomConstraint.constant = -contentBottomInset }
    }

    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!

    init(kicker: String, title: String, body: String, art: Art) {
        if art == .compare {
            artView = SPOrbitalArtView(variant: .dual)
        } else if art == .privacy {
            artView = SPOrbitalArtView(variant: .compact)
        } else {
            artView = SPOrbitalArtView(variant: .large)
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        artContainer.translatesAutoresizingMaskIntoConstraints = false
        artContainer.backgroundColor = .clear
        artContainer.addSubview(artView)

        kickerLabel.attributedText = NSAttributedString(
            string: kicker,
            attributes: [
                .font: SPFont.text(11, weight: .semibold, relativeTo: .caption1),
                .foregroundColor: SPColor.accent,
                .kern: 1.5
            ]
        )
        kickerLabel.textAlignment = .center
        kickerLabel.adjustsFontForContentSizeCategory = true

        titleLabel.text = title
        titleLabel.font = SPFont.display(34, relativeTo: .largeTitle)
        titleLabel.textColor = SPColor.ink
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            titleLabel.maximumContentSizeCategory = .accessibilityMedium
        }

        bodyLabel.text = body
        bodyLabel.font = SPFont.text(15, weight: .regular, relativeTo: .body)
        bodyLabel.textColor = SPColor.secondaryInk
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(axis: .vertical, spacing: 13, alignment: .center)
        textStack.addArrangedSubview(kickerLabel)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.setCustomSpacing(18, after: titleLabel)

        contentStack.addArrangedSubview(artContainer)
        contentStack.setCustomSpacing(24, after: artContainer)
        contentStack.addArrangedSubview(textStack)
        contentStack.setCustomSpacing(20, after: bodyLabel)
        if art == .privacy {
            let badges = privacyBadges()
            badges.widthAnchor.constraint(equalToConstant: 300).isActive = true
            contentStack.setCustomSpacing(18, after: textStack)
            contentStack.addArrangedSubview(badges)
        }

        addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SPMetric.screenInset + 4),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SPMetric.screenInset - 4),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),

            artView.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            artView.centerYAnchor.constraint(equalTo: artContainer.centerYAnchor),
            artView.topAnchor.constraint(greaterThanOrEqualTo: artContainer.topAnchor),
            artView.bottomAnchor.constraint(lessThanOrEqualTo: artContainer.bottomAnchor),
            artContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            artContainer.heightAnchor.constraint(equalToConstant: art == .compare ? 140 : 200),

            textStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        ])

        // 顶部与底部区域避让固定栏。
        topConstraint = contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: contentTopInset)
        topConstraint.isActive = true
        bottomConstraint = contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -contentBottomInset)
        bottomConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func privacyBadges() -> UIView {
        let items: [(String, String)] = [
            ("lock.shield", "Stored on-device"),
            ("wifi.slash", "Offline"),
            ("eye.slash", "No tracking")
        ]
        let stack = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        stack.distribution = .fillEqually
        for item in items {
            let label = UILabel()
            label.text = item.1
            label.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
            label.textColor = SPColor.secondaryInk
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontForContentSizeCategory = true

            let icon = UIImageView(image: UIImage(systemName: item.0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)))
            icon.tintColor = SPColor.accent
            icon.contentMode = .scaleAspectFit

            let vertical = UIStackView(axis: .vertical, spacing: 5, alignment: .center)
            vertical.addArrangedSubview(icon)
            vertical.addArrangedSubview(label)
            stack.addArrangedSubview(vertical)
        }
        return stack
    }
}
