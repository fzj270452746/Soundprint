//
//  FormViews.swift
//  Soundprint
//
//  表单控件：文本输入、备注、选择行、开关与标签编辑。
//

import UIKit

final class SPTextFieldView: UIView, UITextFieldDelegate {
    let textField = UITextField()
    private let titleLabel = UILabel()
    private let container = UIView()
    private let errorLabel = UILabel()
    var onTextChanged: ((String) -> Void)?

    var text: String {
        get { textField.text ?? "" }
        set { textField.text = newValue }
    }

    init(
        title: String,
        placeholder: String,
        text: String = "",
        keyboardType: UIKeyboardType = .default,
        autocapitalization: UITextAutocapitalizationType = .sentences,
        symbol: String? = nil,
        isRequired: Bool = false
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title + (isRequired ? "  *" : "")
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = SPColor.sunken
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = SPColor.hairline.withAlphaComponent(0.65).cgColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.text = text
        textField.font = SPFont.text(16, weight: .regular)
        textField.textColor = SPColor.ink
        textField.tintColor = SPColor.accent
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalization
        textField.autocorrectionType = keyboardType == .URL ? .no : .default
        textField.returnKeyType = .done
        textField.delegate = self
        textField.adjustsFontForContentSizeCategory = true
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: SPFont.text(16, weight: .regular),
                .foregroundColor: SPColor.tertiaryInk
            ]
        )
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        var fieldLeading: CGFloat = 14
        if let symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = SPColor.tertiaryInk
            icon.contentMode = .scaleAspectFit
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18)
            ])
            fieldLeading = 42
        }

        container.addSubview(textField)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = SPFont.text(12, weight: .medium, relativeTo: .caption1)
        errorLabel.textColor = SPColor.danger
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.adjustsFontForContentSizeCategory = true

        addSubview(titleLabel)
        addSubview(container)
        addSubview(errorLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: fieldLeading),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            textField.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 5),
            errorLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
        container.layer.borderColor = (message == nil ? SPColor.hairline.withAlphaComponent(0.65) : SPColor.danger).cgColor
        container.layer.borderWidth = message == nil ? 1 : 1.5
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            if errorLabel.isHidden {
                container.layer.borderColor = SPColor.hairline.withAlphaComponent(0.65).cgColor
            }
        }
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textField.becomeFirstResponder()
    }

    @objc private func editingChanged() {
        onTextChanged?(text)
        if !errorLabel.isHidden {
            showError(nil)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class SPTextView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let titleLabel = UILabel()
    private let placeholderLabel = UILabel()
    private let container = UIView()
    private let countLabel = UILabel()
    private let maxLength: Int
    var onTextChanged: ((String) -> Void)?

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updatePlaceholder()
            updateCount()
        }
    }

    init(title: String, placeholder: String, text: String = "", maxLength: Int = 1000) {
        self.maxLength = maxLength
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = SPColor.sunken
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = SPColor.hairline.withAlphaComponent(0.65).cgColor

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = SPFont.text(15, weight: .regular)
        textView.textColor = SPColor.ink
        textView.tintColor = SPColor.accent
        textView.textContainerInset = UIEdgeInsets(top: 13, left: 9, bottom: 12, right: 9)
        textView.delegate = self
        textView.text = text
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = placeholder
        placeholderLabel.font = SPFont.text(15, weight: .regular)
        placeholderLabel.textColor = SPColor.tertiaryInk
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = SPFont.mono(10.5, weight: .regular, relativeTo: .caption2)
        countLabel.textColor = SPColor.tertiaryInk
        countLabel.textAlignment = .right

        container.addSubview(textView)
        container.addSubview(placeholderLabel)
        addSubview(titleLabel)
        addSubview(container)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 104),

            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5),
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),

            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            placeholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            placeholderLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),

            countLabel.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 5),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            countLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updatePlaceholder()
        updateCount()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > maxLength {
            textView.text = String(textView.text.prefix(maxLength))
        }
        updatePlaceholder()
        updateCount()
        onTextChanged?(textView.text ?? "")
        if textView.text.isEmpty {
            // no-op
        }
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
    }

    private func updateCount() {
        countLabel.text = "\(textView.text?.count ?? 0) / \(maxLength)"
    }
}

// MARK: - 选择行

final class SPMenuRow: UIControl {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let iconView = UIImageView()
    private let chevron = UIImageView()
    var value: String? {
        get { valueLabel.text }
        set {
            valueLabel.text = newValue
            valueLabel.textColor = newValue == nil ? SPColor.tertiaryInk : SPColor.ink
            accessibilityValue = newValue
        }
    }
    var title: String {
        get { titleLabel.text ?? "" }
        set {
            titleLabel.text = newValue
            accessibilityLabel = newValue
        }
    }

    init(title: String, value: String? = nil, symbol: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
        accessibilityValue = value
        backgroundColor = SPColor.sunken
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SPColor.hairline.withAlphaComponent(0.65).cgColor

        titleLabel.text = title
        titleLabel.font = SPFont.text(13, weight: .medium, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.text = value
        valueLabel.font = SPFont.text(15, weight: .medium, relativeTo: .body)
        valueLabel.textColor = value == nil ? SPColor.tertiaryInk : SPColor.ink
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.8
        valueLabel.adjustsFontForContentSizeCategory = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = SPColor.accent
        if let symbol {
            iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        chevron.tintColor = SPColor.tertiaryInk
        chevron.contentMode = .scaleAspectFit

        let stack = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        stack.isUserInteractionEnabled = false
        if symbol != nil { stack.addArrangedSubview(iconView) }
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(chevron)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            iconView.widthAnchor.constraint(equalToConstant: symbol == nil ? 0 : 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - 开关行

final class SPToggleRow: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    let toggle = UISwitch()
    var onChange: ((Bool) -> Void)?

    init(title: String, subtitle: String? = nil, isOn: Bool, symbol: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = SPFont.text(15, weight: .medium, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = subtitle
        subtitleLabel.font = SPFont.text(12, weight: .regular, relativeTo: .caption1)
        subtitleLabel.textColor = SPColor.tertiaryInk
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.adjustsFontForContentSizeCategory = true

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = isOn
        toggle.onTintColor = SPColor.accent
        toggle.addTarget(self, action: #selector(changed), for: .valueChanged)

        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        if let symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
            icon.tintColor = SPColor.secondaryInk
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            row.addArrangedSubview(icon)
        }
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(toggle)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        toggle.setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() {
        onChange?(toggle.isOn)
    }
}

// MARK: - 值行

final class SPValueRow: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String, value: String, valueColor: UIColor = SPColor.ink) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = SPFont.text(13, weight: .regular, relativeTo: .subheadline)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.text = value
        valueLabel.font = SPFont.mono(12.5, weight: .medium, relativeTo: .subheadline)
        valueLabel.textColor = valueColor
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(axis: .horizontal, spacing: 16, alignment: .top)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(row)
        row.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 分割线

final class SPDivider: UIView {
    init(color: UIColor = SPColor.hairline) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = color
        heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 选项行

final class SPOptionRow: UIControl {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkView = UIImageView()
    var isChosen: Bool = false {
        didSet { updateSelection() }
    }

    init(title: String, detail: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: ", ")
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        titleLabel.text = title
        titleLabel.font = SPFont.text(15, weight: .medium, relativeTo: .body)
        titleLabel.textColor = SPColor.ink
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.text = detail
        detailLabel.font = SPFont.text(12, weight: .regular, relativeTo: .caption1)
        detailLabel.textColor = SPColor.tertiaryInk
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.isHidden = detail == nil

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        checkView.tintColor = SPColor.onAccent
        checkView.contentMode = .scaleAspectFit
        checkView.backgroundColor = SPColor.accent
        checkView.layer.cornerRadius = 11
        checkView.layer.cornerCurve = .continuous
        checkView.clipsToBounds = true

        let textStack = UIStackView(axis: .vertical, spacing: 3)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        let row = UIStackView(axis: .horizontal, spacing: 12, alignment: .center)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(checkView)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 13, left: 14, bottom: 13, right: 14))

        NSLayoutConstraint.activate([
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22)
        ])
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : 1 }
    }

    private func updateSelection() {
        backgroundColor = isChosen ? SPColor.accentSoft : SPColor.sunken
        layer.borderColor = (isChosen ? SPColor.accent.withAlphaComponent(0.45) : SPColor.hairline).cgColor
        checkView.alpha = isChosen ? 1 : 0
        accessibilityTraits = isChosen ? [.button, .selected] : .button
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateSelection()
        }
    }
}

// MARK: - 表单卡片容器

final class SPFormCard: SPCardView {
    let contentStack = UIStackView(axis: .vertical, spacing: 14)

    init(title: String? = nil, subtitle: String? = nil) {
        super.init(style: .surface)
        let wrapper = UIStackView(axis: .vertical, spacing: 14)
        if let title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = SPFont.display(19, relativeTo: .headline)
            titleLabel.textColor = SPColor.ink
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.numberOfLines = 0
            wrapper.addArrangedSubview(titleLabel)
            if let subtitle {
                let subtitleLabel = UILabel()
                subtitleLabel.text = subtitle
                subtitleLabel.font = SPFont.text(12.5, weight: .regular, relativeTo: .footnote)
                subtitleLabel.textColor = SPColor.tertiaryInk
                subtitleLabel.numberOfLines = 0
                subtitleLabel.adjustsFontForContentSizeCategory = true
                wrapper.addArrangedSubview(subtitleLabel)
                wrapper.setCustomSpacing(4, after: titleLabel)
            }
            wrapper.setCustomSpacing(16, after: subtitle == nil ? titleLabel : wrapper.arrangedSubviews.last!)
        }
        wrapper.addArrangedSubview(contentStack)
        addContent(wrapper)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 搜索框

final class SPSearchField: UIView, UITextFieldDelegate {
    let textField = UITextField()
    private let icon = UIImageView()
    private let clearButton = UIButton(type: .system)
    var onTextChanged: ((String) -> Void)?
    var onReturn: (() -> Void)?

    var text: String {
        get { textField.text ?? "" }
        set {
            textField.text = newValue
            updateClear()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SPColor.sunken
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SPColor.hairline.withAlphaComponent(0.7).cgColor
        heightAnchor.constraint(equalToConstant: 46).isActive = true

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        icon.tintColor = SPColor.tertiaryInk
        icon.contentMode = .scaleAspectFit

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = SPFont.text(15, weight: .regular)
        textField.textColor = SPColor.ink
        textField.tintColor = SPColor.accent
        textField.keyboardType = .default
        textField.returnKeyType = .search
        textField.clearButtonMode = .never
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.adjustsFontForContentSizeCategory = true
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search places, recordings, and tags",
            attributes: [
                .font: SPFont.text(15, weight: .regular),
                .foregroundColor: SPColor.tertiaryInk
            ]
        )
        textField.addTarget(self, action: #selector(changed), for: .editingChanged)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)), for: .normal)
        clearButton.tintColor = SPColor.tertiaryInk
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.isHidden = true

        addSubview(icon)
        addSubview(textField)
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 24),
            clearButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPlaceholder(_ value: String) {
        textField.attributedPlaceholder = NSAttributedString(
            string: value,
            attributes: [
                .font: SPFont.text(15, weight: .regular),
                .foregroundColor: SPColor.tertiaryInk
            ]
        )
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textField.becomeFirstResponder()
    }

    @objc private func changed() {
        updateClear()
        onTextChanged?(text)
    }

    @objc private func clearTapped() {
        textField.text = ""
        updateClear()
        onTextChanged?("")
        textField.becomeFirstResponder()
    }

    private func updateClear() {
        clearButton.isHidden = (textField.text ?? "").isEmpty
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?()
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - 地点类型选择

final class SPPlaceKindPicker: UIView {
    private let stack = UIStackView(axis: .vertical, spacing: 8)
    private var options: [SPKindOption] = []
    private(set) var selectedKind: PlaceKind = .other
    var onChange: ((PlaceKind) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)

        let kinds = PlaceKind.allCases
        var index = 0
        while index < kinds.count {
            let row = UIStackView(axis: .horizontal, spacing: 8, distribution: .fillEqually)
            for _ in 0..<4 {
                if index < kinds.count {
                    let option = SPKindOption(kind: kinds[index])
                    option.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
                    options.append(option)
                    row.addArrangedSubview(option)
                    index += 1
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            stack.addArrangedSubview(row)
        }
        select(.other, notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ kind: PlaceKind, notify: Bool = true) {
        selectedKind = kind
        for option in options {
            option.setSelected(option.kind == kind)
        }
        if notify { onChange?(kind) }
    }

    @objc private func optionTapped(_ sender: SPKindOption) {
        SPHaptic.selection()
        select(sender.kind)
    }
}

private final class SPKindOption: UIControl {
    let kind: PlaceKind
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView(axis: .vertical, spacing: 5, alignment: .center)

    init(kind: PlaceKind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: kind.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        label.text = kind.title
        label.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.62

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
        isAccessibilityElement = true
        accessibilityLabel = kind.title
        accessibilityTraits = .button
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ selected: Bool) {
        iconView.tintColor = selected ? SPColor.onAccent : kind.color
        label.textColor = selected ? SPColor.onAccent : SPColor.secondaryInk
        backgroundColor = selected ? kind.color : kind.softColor
        layer.borderColor = (selected ? kind.color : SPColor.hairline.withAlphaComponent(0.5)).cgColor
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.68 : 1 }
    }
}

// MARK: - 事件类型选择

final class SPEventKindPicker: UIView {
    private let stack = UIStackView(axis: .vertical, spacing: 8)
    private var options: [SPEventKindOption] = []
    private(set) var selectedKind: EventKind = .other
    var onChange: ((EventKind) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)
        let kinds = EventKind.allCases
        var index = 0
        while index < kinds.count {
            let row = UIStackView(axis: .horizontal, spacing: 7, distribution: .fillEqually)
            for _ in 0..<3 {
                if index < kinds.count {
                    let option = SPEventKindOption(kind: kinds[index])
                    option.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
                    options.append(option)
                    row.addArrangedSubview(option)
                    index += 1
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            stack.addArrangedSubview(row)
        }
        select(.other, notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ kind: EventKind, notify: Bool = true) {
        selectedKind = kind
        options.forEach { $0.setSelected($0.kind == kind) }
        if notify { onChange?(kind) }
    }

    @objc private func tapped(_ sender: SPEventKindOption) {
        SPHaptic.selection()
        select(sender.kind)
    }
}

private final class SPEventKindOption: UIControl {
    let kind: EventKind
    private let iconView = UIImageView()
    private let label = UILabel()

    init(kind: EventKind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: kind.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        label.text = kind.title
        label.font = SPFont.text(10, weight: .medium, relativeTo: .caption2)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.62

        let stack = UIStackView(axis: .vertical, spacing: 4, alignment: .center)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        isAccessibilityElement = true
        accessibilityLabel = kind.title
        accessibilityTraits = .button
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ selected: Bool) {
        backgroundColor = selected ? kind.color : kind.color.withAlphaComponent(0.1)
        iconView.tintColor = selected ? .white : kind.color
        label.textColor = selected ? .white : SPColor.secondaryInk
        layer.borderColor = (selected ? kind.color : SPColor.hairline.withAlphaComponent(0.5)).cgColor
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - 时间滑块

final class SPTimeSliderView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let duration: Double
    var onChange: ((Double) -> Void)?

    var value: Double {
        get { Double(slider.value) }
        set {
            slider.value = Float(max(0, min(duration, newValue)))
            updateValue()
        }
    }

    init(title: String, value: Double, duration: Double) {
        self.duration = max(0.1, duration)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = SPFont.mono(13, weight: .medium, relativeTo: .subheadline)
        valueLabel.textColor = SPColor.accent
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(valueLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = Float(self.duration)
        slider.value = Float(max(0, min(self.duration, value)))
        slider.tintColor = SPColor.accent
        slider.setThumbImage(SPImage.sliderThumb(diameter: 16), for: .normal)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.accessibilityLabel = title

        let stack = UIStackView(axis: .vertical, spacing: 6)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(slider)
        addSubview(stack)
        stack.pinEdges(to: self)
        updateValue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func sliderChanged() {
        updateValue()
        onChange?(Double(slider.value))
    }

    private func updateValue() {
        valueLabel.text = SPFormat.duration(Double(slider.value))
        slider.accessibilityValue = SPFormat.accessibleDuration(Double(slider.value))
    }
}
