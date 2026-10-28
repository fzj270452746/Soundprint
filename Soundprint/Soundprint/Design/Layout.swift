//
//  Layout.swift
//  Soundprint
//
//  轻量 Auto Layout 与 UIKit 常用工具。
//

import UIKit

extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
    }

    func pinEdges(to view: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        ])
    }

    func setContentHugging(priority: UILayoutPriority = .required) {
        setContentHuggingPriority(priority, for: .horizontal)
        setContentHuggingPriority(priority, for: .vertical)
    }

    func roundCorners(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    /// 仅圆角上侧，用于底部面板。
    func roundTopCorners(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
    }
}

extension UIStackView {
    convenience init(
        axis: NSLayoutConstraint.Axis,
        spacing: CGFloat = 0,
        alignment: UIStackView.Alignment = .fill,
        distribution: UIStackView.Distribution = .fill
    ) {
        self.init()
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.distribution = distribution
        translatesAutoresizingMaskIntoConstraints = false
    }

    func addArrangedSubviews(_ views: [UIView]) {
        views.forEach { addArrangedSubview($0) }
    }

    func setCustomSpacing(after view: UIView, _ spacing: CGFloat) {
        setCustomSpacing(spacing, after: view)
    }
}

extension UIViewController {
    func presentAlert(title: String, message: String? = nil, actionTitle: String = "Close") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default))
        present(alert, animated: true)
    }

    func presentConfirm(
        title: String,
        message: String?,
        destructiveTitle: String,
        cancelTitle: String = "Cancel",
        destructive: Bool = true,
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        alert.addAction(UIAlertAction(title: destructiveTitle, style: destructive ? .destructive : .default) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    func embedInNavigationController() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        SPStyle.applyNavigationAppearance(to: nav)
        return nav
    }
}

extension UIWindow {
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

extension UIScrollView {
    func setVerticalContentInset(_ value: CGFloat) {
        contentInset = UIEdgeInsets(top: value, left: 0, bottom: value, right: 0)
    }
}
