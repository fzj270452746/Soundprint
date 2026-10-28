//
//  Controls.swift
//  Soundprint
//
//  可复用的 UIKit 控件：卡片、按钮、标签、提示条与空状态。
//

import UIKit

// MARK: - 卡片

class SPCardView: UIView {
    enum Style {
        case surface
        case raised
        case sunken
        case accent
        case clear
    }

    private let style: Style

    init(style: Style = .surface) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = SPMetric.cardRadius
        layer.cornerCurve = .continuous
        applyStyle()
        if style == .raised || style == .surface {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 8)
            layer.shadowRadius = 22
            layer.shadowOpacity = 0.055
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyStyle()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: SPMetric.cardRadius
        ).cgPath
    }

    @discardableResult
    func addContent(_ content: UIView, insets: UIEdgeInsets = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)) -> UIView {
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
        return content
    }

    private func applyStyle() {
        switch style {
        case .surface:
            backgroundColor = SPColor.surface
            layer.borderWidth = 1
            layer.borderColor = SPColor.hairline.cgColor
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.055
        case .raised:
            backgroundColor = SPColor.surface
            layer.borderWidth = 1
            layer.borderColor = SPColor.hairline.cgColor
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.075
        case .sunken:
            backgroundColor = SPColor.sunken
            layer.borderWidth = 0
            layer.shadowOpacity = 0
        case .accent:
            backgroundColor = SPColor.accentSoft
            layer.borderWidth = 1
            layer.borderColor = SPColor.accent.withAlphaComponent(0.18).cgColor
            layer.shadowOpacity = 0
        case .clear:
            backgroundColor = .clear
            layer.borderWidth = 0
            layer.shadowOpacity = 0
        }
    }
}

// MARK: - 按钮

final class SPButton: UIControl {
    enum Style {
        case primary
        case ink
        case secondary
        case ghost
        case danger

        var height: CGFloat {
            switch self {
            case .ghost: return 38
            default: return 52
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .ghost: return 12
            default: return 20
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .ghost: return 7
            default: return 14
            }
        }
    }

    private let style: Style
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let contentStack = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
    private var iconName: String?

    var title: String {
        get { titleLabel.text ?? "" }
        set {
            titleLabel.text = newValue
            accessibilityLabel = newValue
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard isEnabled else { return }
            let transform: CGAffineTransform
            if isHighlighted && !UIAccessibility.isReduceMotionEnabled {
                transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            } else {
                transform = .identity
            }
            UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.alpha = self.isHighlighted ? 0.82 : 1
                self.transform = transform
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.42
            accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        }
    }

    init(title: String, symbol: String? = nil, style: Style = .primary) {
        self.style = style
        self.iconName = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        titleLabel.text = title
        titleLabel.font = SPFont.text(style == .ghost ? 13 : 15, weight: .semibold, relativeTo: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.isUserInteractionEnabled = false

        contentStack.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        addSubview(contentStack)

        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        if let symbol {
            iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: style.horizontalPadding),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -style.horizontalPadding),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: style.verticalPadding),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -style.verticalPadding),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: symbol == nil ? 0 : 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: style.height)
        ])

        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ symbol: String?) {
        iconName = symbol
        if let symbol {
            iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyStyle()
        }
    }

    private func applyStyle() {
        switch style {
        case .primary:
            backgroundColor = SPColor.accent
            titleLabel.textColor = SPColor.onAccent
            iconView.tintColor = SPColor.onAccent
            layer.borderWidth = 0
        case .ink:
            backgroundColor = SPColor.ink
            titleLabel.textColor = SPColor.paper
            iconView.tintColor = SPColor.paper
            layer.borderWidth = 0
        case .secondary:
            backgroundColor = SPColor.surface
            titleLabel.textColor = SPColor.ink
            iconView.tintColor = SPColor.ink
            layer.borderWidth = 1
            layer.borderColor = SPColor.strongHairline.cgColor
        case .ghost:
            backgroundColor = .clear
            titleLabel.textColor = SPColor.accent
            iconView.tintColor = SPColor.accent
            layer.borderWidth = 0
        case .danger:
            backgroundColor = SPColor.dangerSoft
            titleLabel.textColor = SPColor.danger
            iconView.tintColor = SPColor.danger
            layer.borderWidth = 0
        }
    }
}

// MARK: - 圆形图标按钮

final class SPIconButton: UIButton {
    enum Style {
        case plain
        case filled
        case bordered
    }

    private let style: Style

    init(symbol: String, accessibilityLabel: String, style: Style = .plain, pointSize: CGFloat = 16) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)), for: .normal)
        self.accessibilityLabel = accessibilityLabel
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        applyStyle()
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = .zero
            self.configuration = configuration
        } else {
            contentEdgeInsets = .zero
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyStyle()
        }
    }

    private func applyStyle() {
        switch style {
        case .plain:
            backgroundColor = .clear
            tintColor = SPColor.ink
            layer.borderWidth = 0
        case .filled:
            backgroundColor = SPColor.surface
            tintColor = SPColor.ink
            layer.borderWidth = 1
            layer.borderColor = SPColor.hairline.cgColor
        case .bordered:
            backgroundColor = .clear
            tintColor = SPColor.ink
            layer.borderWidth = 1
            layer.borderColor = SPColor.strongHairline.cgColor
        }
    }
}

final class SPTextButton: UIButton {
    init(title: String, color: UIColor = SPColor.accent) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setTitle(title, for: .normal)
        setTitleColor(color, for: .normal)
        titleLabel?.font = SPFont.text(13, weight: .semibold, relativeTo: .footnote)
        titleLabel?.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            self.configuration = configuration
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 标签

final class SPTagView: UIView {
    private let label = UILabel()
    private let iconView = UIImageView()
    private let closeView = UIImageView()
    private let stack = UIStackView(axis: .horizontal, spacing: 5, alignment: .center)
    var onTap: (() -> Void)?

    init(
        text: String,
        symbol: String? = nil,
        color: UIColor = SPColor.secondaryInk,
        background: UIColor = SPColor.sunken,
        removable: Bool = false
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerCurve = .continuous
        backgroundColor = background

        label.text = text
        label.font = SPFont.text(11.5, weight: .medium, relativeTo: .caption1)
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1

        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        if let symbol {
            iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        closeView.tintColor = color.withAlphaComponent(0.7)
        closeView.contentMode = .scaleAspectFit
        closeView.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))
        closeView.isHidden = !removable

        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(closeView)
        addSubview(stack)

        let horizontal: CGFloat = 10
        let vertical: CGFloat = 6
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            iconView.widthAnchor.constraint(equalToConstant: symbol == nil ? 0 : 11),
            iconView.heightAnchor.constraint(equalToConstant: 11),
            closeView.widthAnchor.constraint(equalToConstant: removable ? 9 : 0),
            closeView.heightAnchor.constraint(equalToConstant: 9)
        ])

        if onTap != nil || removable {
            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
            accessibilityTraits = .button
        }
        isAccessibilityElement = true
        accessibilityLabel = text
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let content = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: content.width + 20, height: content.height + 12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return super.point(inside: point, with: event) }
        return bounds.insetBy(dx: -5, dy: -6).contains(point)
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - 标签流式布局

final class SPTagFlowView: UIView {
    private var heightConstraintInternal: NSLayoutConstraint!
    private var chips: [UIView] = []
    private var calculatedHeight: CGFloat = 34

    var tags: [String] = [] {
        didSet { rebuild() }
    }
    var showsAddButton: Bool = false {
        didSet { rebuild() }
    }
    var removable: Bool = false {
        didSet { rebuild() }
    }
    var onRemove: ((Int) -> Void)?
    var onAdd: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: calculatedHeight)
    }

    init(tags: [String] = []) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraintInternal = heightAnchor.constraint(equalToConstant: 34)
        heightConstraintInternal.priority = UILayoutPriority(999)
        heightConstraintInternal.isActive = true
        self.tags = tags
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        layoutChips(width: bounds.width)
    }

    private func rebuild() {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()

        for (index, tag) in tags.enumerated() {
            let chip = SPTagView(
                text: tag,
                symbol: nil,
                color: removable ? SPColor.ink : SPColor.secondaryInk,
                background: removable ? SPColor.sunken : SPColor.sunken.withAlphaComponent(0.72),
                removable: removable
            )
            if removable {
                chip.onTap = { [weak self] in self?.onRemove?(index) }
            }
            addSubview(chip)
            chips.append(chip)
        }

        if showsAddButton {
            let addChip = SPTagView(
                text: "Add Tag",
                symbol: "plus",
                color: SPColor.accent,
                background: SPColor.accentSoft
            )
            addChip.onTap = { [weak self] in self?.onAdd?() }
            addSubview(addChip)
            chips.append(addChip)
        }

        setNeedsLayout()
        layoutIfNeeded()
        invalidateIntrinsicContentSize()
    }

    private func layoutChips(width: CGFloat) {
        guard !chips.isEmpty else {
            updateHeight(0)
            return
        }
        let gap: CGFloat = 8
        let lineGap: CGFloat = 8
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for chip in chips {
            let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let chipWidth = min(size.width, width)
            if x > 0, x + chipWidth > width {
                x = 0
                y += lineHeight + lineGap
                lineHeight = 0
            }
            chip.frame = CGRect(x: x, y: y, width: chipWidth, height: max(28, size.height))
            x += chipWidth + gap
            lineHeight = max(lineHeight, max(28, size.height))
        }
        updateHeight(y + lineHeight)
    }

    private func updateHeight(_ value: CGFloat) {
        let newValue = max(0, ceil(value))
        if abs(calculatedHeight - newValue) > 0.5 {
            calculatedHeight = newValue
            heightConstraintInternal.constant = newValue
            invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - 小节标题

final class SPSectionHeaderView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = SPTextButton(title: "")
    private let textStack = UIStackView(axis: .vertical, spacing: 3)
    private var action: (() -> Void)?

    init(title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = SPFont.display(23, relativeTo: .title2)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        if #available(iOS 15.0, *) {
            titleLabel.maximumContentSizeCategory = .accessibilityMedium
        }

        subtitleLabel.text = subtitle
        subtitleLabel.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = subtitle == nil

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(textStack)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let actionTitle, self.action != nil {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(actionButton)
        } else {
            actionButton.isHidden = true
        }

        addSubview(row)
        row.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func actionTapped() {
        action?()
    }
}

// MARK: - 空状态

final class SPEmptyStateView: UIView {
    private let circle = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let button: SPButton?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.button = actionTitle.map { SPButton(title: $0, symbol: nil, style: .primary) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.backgroundColor = SPColor.sunken
        circle.layer.cornerRadius = 33
        circle.layer.cornerCurve = .continuous

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
        imageView.tintColor = SPColor.secondaryInk
        imageView.contentMode = .scaleAspectFit

        titleLabel.text = title
        titleLabel.font = SPFont.display(24, relativeTo: .title2)
        titleLabel.textColor = SPColor.ink
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.text = message
        messageLabel.font = SPFont.text(14, weight: .regular, relativeTo: .subheadline)
        messageLabel.textColor = SPColor.secondaryInk
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        circle.addSubview(imageView)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 66),
            circle.heightAnchor.constraint(equalToConstant: 66),
            imageView.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
        ])

        let stack = UIStackView(axis: .vertical, spacing: 10, alignment: .center)
        stack.addArrangedSubview(circle)
        stack.setCustomSpacing(after: circle, 16)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        stack.setCustomSpacing(after: messageLabel, 18)

        if let button {
            button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
            stack.addArrangedSubview(button)
            self.action = action
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 310)
        ])
    }

    private var action: (() -> Void)?

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = max(0, bounds.width - 40)
        let titleWidth = available
        let messageWidth = min(310, available)
        if titleLabel.preferredMaxLayoutWidth != titleWidth {
            titleLabel.preferredMaxLayoutWidth = titleWidth
            titleLabel.invalidateIntrinsicContentSize()
        }
        if messageLabel.preferredMaxLayoutWidth != messageWidth {
            messageLabel.preferredMaxLayoutWidth = messageWidth
            messageLabel.invalidateIntrinsicContentSize()
        }
    }

    @objc private func buttonTapped() {
        action?()
    }
}

// MARK: - 信息提示条

final class SPInfoBanner: UIView {
    enum Tone {
        case neutral
        case info
        case warning
        case success

        var background: UIColor {
            switch self {
            case .neutral: return SPColor.sunken
            case .info: return SPColor.accentSoft
            case .warning: return SPColor.amberSoft
            case .success: return SPColor.mossSoft
            }
        }

        var foreground: UIColor {
            switch self {
            case .neutral: return SPColor.secondaryInk
            case .info: return SPColor.accent
            case .warning: return SPColor.amber
            case .success: return SPColor.moss
            }
        }

        var symbol: String {
            switch self {
            case .neutral: return "info.circle"
            case .info: return "waveform.circle"
            case .warning: return "exclamationmark.triangle"
            case .success: return "checkmark.circle"
            }
        }
    }

    init(title: String? = nil, message: String, tone: Tone = .neutral, symbol: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = tone.background
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: symbol ?? tone.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        imageView.tintColor = tone.foreground
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = SPFont.text(13, weight: .semibold, relativeTo: .footnote)
        titleLabel.textColor = tone.foreground
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isHidden = title == nil

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
        messageLabel.textColor = SPColor.secondaryInk
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(messageLabel)

        addSubview(imageView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13)
        ])
        isAccessibilityElement = true
        accessibilityLabel = [title, message].compactMap { $0 }.joined(separator: ". ")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 状态徽标

final class SPStatusBadge: UIView {
    private let dot = UIView()
    private let label = UILabel()
    private let stack = UIStackView(axis: .horizontal, spacing: 6, alignment: .center)

    init(text: String, color: UIColor, background: UIColor? = nil, symbol: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = background ?? color.withAlphaComponent(0.11)
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous

        if let symbol {
            let image = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)))
            image.tintColor = color
            image.translatesAutoresizingMaskIntoConstraints = false
            image.widthAnchor.constraint(equalToConstant: 10).isActive = true
            image.heightAnchor.constraint(equalToConstant: 10).isActive = true
            stack.addArrangedSubview(image)
        } else {
            dot.backgroundColor = color
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 3
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            stack.addArrangedSubview(dot)
        }

        label.text = text
        label.font = SPFont.text(10.5, weight: .semibold, relativeTo: .caption2)
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(label)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        isAccessibilityElement = true
        accessibilityLabel = text
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 分段占比条

final class SPSegmentedBarView: UIView {
    private var segments: [(value: CGFloat, color: UIColor)] = []
    var trackColor: UIColor = SPColor.sunken {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        heightAnchor.constraint(equalToConstant: 8).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSegments(_ segments: [(value: CGFloat, color: UIColor)]) {
        self.segments = segments
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let radius = rect.height / 2
        context.setFillColor(trackColor.cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        path.fill()

        let total = segments.reduce(CGFloat(0)) { $0 + max(0, $1.value) }
        guard total > 0 else { return }
        let clipped = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        context.saveGState()
        clipped.addClip()
        var x = rect.minX
        for segment in segments where segment.value > 0 {
            let width = rect.width * (segment.value / total)
            context.setFillColor(segment.color.cgColor)
            context.fill(CGRect(x: x, y: rect.minY, width: width + 0.6, height: rect.height))
            x += width
        }
        context.restoreGState()
    }
}

// MARK: - 可选中的小胶囊

final class SPFilterChip: UIControl {
    private let label = UILabel()
    private let stack = UIStackView(axis: .horizontal, spacing: 5, alignment: .center)
    private(set) var isSelectedState: Bool = false

    init(title: String, symbol: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        if let symbol {
            let image = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
            image.contentMode = .scaleAspectFit
            image.translatesAutoresizingMaskIntoConstraints = false
            image.widthAnchor.constraint(equalToConstant: 12).isActive = true
            image.heightAnchor.constraint(equalToConstant: 12).isActive = true
            image.tag = 99
            stack.addArrangedSubview(image)
        }

        label.text = title
        label.font = SPFont.text(12, weight: .medium, relativeTo: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        stack.addArrangedSubview(label)
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        apply(selected: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var selectedState: Bool {
        get { isSelectedState }
        set {
            isSelectedState = newValue
            apply(selected: newValue)
            accessibilityTraits = newValue ? [.button, .selected] : .button
        }
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -4, dy: -6).contains(point)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            apply(selected: isSelectedState)
        }
    }

    private func apply(selected: Bool) {
        backgroundColor = selected ? SPColor.ink : SPColor.surface
        label.textColor = selected ? SPColor.paper : SPColor.secondaryInk
        if let image = stack.arrangedSubviews.first as? UIImageView {
            image.tintColor = selected ? SPColor.paper : SPColor.secondaryInk
        }
        layer.borderWidth = selected ? 0 : 1
        layer.borderColor = SPColor.hairline.cgColor
    }
}
