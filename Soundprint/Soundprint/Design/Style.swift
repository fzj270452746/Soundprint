//
//  Style.swift
//  Soundprint
//
//  导航栏、标签栏与全局外观。界面保持原生手感，同时带有安静的纸质档案气质。
//

import UIKit

enum SPStyle {
    static func applyGlobalAppearance() {
        let navigation = UINavigationBar.appearance()
        navigation.tintColor = SPColor.accent

        let tab = UITabBar.appearance()
        tab.tintColor = SPColor.accent
        tab.unselectedItemTintColor = SPColor.secondaryInk
        applyTabBarAppearance(tab)
    }

    static func applyNavigationAppearance(to navigationController: UINavigationController) {
        let bar = navigationController.navigationBar
        bar.tintColor = SPColor.accent
        bar.prefersLargeTitles = false
        bar.isTranslucent = true

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.backgroundColor = SPColor.paper.withAlphaComponent(0.94)
        standard.shadowColor = SPColor.hairline
        standard.titleTextAttributes = [
            .font: SPFont.text(16, weight: .semibold),
            .foregroundColor: SPColor.ink
        ]
        standard.largeTitleTextAttributes = [
            .font: SPFont.display(32),
            .foregroundColor: SPColor.ink
        ]

        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.titleTextAttributes = standard.titleTextAttributes
        transparent.largeTitleTextAttributes = standard.largeTitleTextAttributes

        let compact = UINavigationBarAppearance()
        compact.configureWithDefaultBackground()
        compact.backgroundColor = SPColor.paper.withAlphaComponent(0.98)
        compact.shadowColor = SPColor.hairline
        compact.titleTextAttributes = standard.titleTextAttributes

        bar.standardAppearance = standard
        bar.scrollEdgeAppearance = transparent
        bar.compactAppearance = compact
        if #available(iOS 15.0, *) {
            bar.compactScrollEdgeAppearance = transparent
        }
    }

    static func applyTabBarAppearance(_ tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = SPColor.paper
        appearance.shadowColor = SPColor.hairline
        appearance.stackedLayoutAppearance.normal.iconColor = SPColor.secondaryInk
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: SPFont.text(10, weight: .medium, relativeTo: .caption2),
            .foregroundColor: SPColor.secondaryInk
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = SPColor.accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: SPFont.text(10, weight: .semibold, relativeTo: .caption2),
            .foregroundColor: SPColor.accent
        ]
        appearance.inlineLayoutAppearance = appearance.stackedLayoutAppearance
        appearance.compactInlineLayoutAppearance = appearance.stackedLayoutAppearance
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    static func makeTabBarItem(title: String, symbol: String, selectedSymbol: String) -> UITabBarItem {
        let item = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbol),
            selectedImage: UIImage(systemName: selectedSymbol) ?? UIImage(systemName: symbol)
        )
        item.setTitleTextAttributes([
            .font: SPFont.text(10, weight: .medium, relativeTo: .caption2)
        ], for: .normal)
        item.setTitleTextAttributes([
            .font: SPFont.text(10, weight: .semibold, relativeTo: .caption2)
        ], for: .selected)
        return item
    }
}

class SPViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SPColor.paper
        navigationItem.largeTitleDisplayMode = .never
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    func presentError(_ error: Error, title: String = "Something Went Wrong") {
        presentAlert(title: title, message: error.localizedDescription)
    }
}

// MARK: - 便捷标签栏页面容器

extension UIViewController {
    func configuredForTab(title: String, symbol: String, selectedSymbol: String) -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.tabBarItem = SPStyle.makeTabBarItem(title: title, symbol: symbol, selectedSymbol: selectedSymbol)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }
}

// MARK: - Toast

enum SPToast {
    static func show(_ message: String, in view: UIView, symbol: String = "checkmark.circle.fill") {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = SPColor.ink
        container.alpha = 0
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        UIAccessibility.post(notification: .announcement, argument: message)

        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = SPColor.accent
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = SPFont.text(14, weight: .medium)
        label.textColor = SPColor.paper
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(image)
        container.addSubview(label)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            image.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        let bottom = container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -74)
        bottom.isActive = true

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            container.alpha = 1
            container.transform = .identity
        }
        if !UIAccessibility.isReduceMotionEnabled {
            container.transform = CGAffineTransform(translationX: 0, y: 12)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            UIView.animate(withDuration: 0.25, animations: {
                container.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled {
                    container.transform = CGAffineTransform(translationX: 0, y: 8)
                }
            }, completion: { _ in
                container.removeFromSuperview()
            })
        }
    }
}

// MARK: - 加载遮罩

final class SPLoadingOverlay: UIView {
    private let card = SPCardView(style: .raised)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = SPColor.scrim
        alpha = 0

        card.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = SPColor.accent
        spinner.startAnimating()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.font = SPFont.text(14, weight: .medium)
        label.textColor = SPColor.ink
        label.numberOfLines = 0
        label.textAlignment = .center

        card.addSubview(spinner)
        card.addSubview(label)
        addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        pinEdges(to: view)
        UIView.animate(withDuration: 0.18) { self.alpha = 1 }
    }

    func hide() {
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}

// MARK: - 自绘控件图像

enum SPImage {
    static func sliderThumb(diameter: CGFloat = 18) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ring = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            SPColor.surface.setFill()
            ring.fill()
            let inset: CGFloat = 2.2
            let circle = UIBezierPath(ovalIn: CGRect(
                x: inset,
                y: inset,
                width: diameter - inset * 2,
                height: diameter - inset * 2
            ))
            SPColor.accent.setFill()
            circle.fill()
            context.cgContext.setStrokeColor(SPColor.accent.withAlphaComponent(0.25).cgColor)
            context.cgContext.setLineWidth(0.5)
            context.cgContext.strokeEllipse(in: CGRect(x: 0.25, y: 0.25, width: diameter - 0.5, height: diameter - 0.5))
        }
    }
}

// MARK: - 分享面板

enum SPShare {
    static func present(
        items: [Any],
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        completion: (() -> Void)? = nil
    ) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = sourceView ?? viewController.view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 1, height: 1)
        }
        viewController.present(controller, animated: true)
    }
}
