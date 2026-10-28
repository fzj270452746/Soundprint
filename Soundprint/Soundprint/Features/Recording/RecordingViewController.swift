//
//  RecordingViewController.swift
//  Soundprint
//
//  专注的录音界面。计时使用服务端的单调时钟，暂停不会累加时长。
//

import UIKit

final class RecordingViewController: SPViewController {
    var onFinished: ((RecordingResult) -> Void)?
    var onCancel: (() -> Void)?

    private let service: RecordingService
    private let placeID: UUID?
    private let library = LibraryService.shared

    private let statusContainer = UIView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let timerLabel = UILabel()
    private let placeLabel = UILabel()
    private let liveMeter = SPLiveMeterView()
    private let meterCard = SPCardView(style: .surface)
    private let bannerHolder = UIStackView(axis: .vertical, spacing: 0)
    private var interruptionBanner: SPInfoBanner?
    private let pauseButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let markerButton = UIButton(type: .system)
    private let pauseCaption = UILabel()
    private let stopCaption = UILabel()
    private let markerCaption = UILabel()
    private let closeButton = SPIconButton(symbol: "xmark", accessibilityLabel: "Close Recording", style: .plain, pointSize: 15)
    private var hasStarted = false
    private var isStopping = false
    private var recordingPlaceName: String?
    private var lastAnnouncedState: String?
    private var pulseLayer: CAShapeLayer?

    init(service: RecordingService, placeID: UUID?) {
        self.service = service
        self.placeID = placeID
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SPColor.paper
        buildInterface()
        bindService()
        updatePlace()
        updateState(.preparing)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        service.start(placeID: placeID)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    // MARK: - 界面

    private func buildInterface() {
        let backdrop = SPWaveBackdropView()
        view.addSubview(backdrop)
        backdrop.pinEdges(to: view)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        let centerTitle = UILabel()
        centerTitle.text = "Recording"
        centerTitle.font = SPFont.text(11, weight: .semibold, relativeTo: .caption1)
        centerTitle.textColor = SPColor.secondaryInk
        centerTitle.textAlignment = .center
        centerTitle.adjustsFontForContentSizeCategory = true
        centerTitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(centerTitle)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            centerTitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerTitle.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])

        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.layer.cornerRadius = 12
        statusContainer.layer.cornerCurve = .continuous
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.layer.cornerRadius = 4
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = SPFont.text(11, weight: .semibold, relativeTo: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusContainer.addSubview(statusDot)
        statusContainer.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 10),
            statusDot.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 7),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -11),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 6),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -6)
        ])

        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.font = SPFont.mono(62, weight: .light, relativeTo: .largeTitle)
        timerLabel.textColor = SPColor.ink
        timerLabel.textAlignment = .center
        timerLabel.text = "0:00"
        timerLabel.adjustsFontForContentSizeCategory = true
        timerLabel.adjustsFontSizeToFitWidth = true
        timerLabel.minimumScaleFactor = 0.5
        timerLabel.accessibilityLabel = "Recording time"

        let pin = UIImageView(image: UIImage(systemName: "mappin", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)))
        pin.tintColor = SPColor.tertiaryInk
        pin.contentMode = .scaleAspectFit
        pin.widthAnchor.constraint(equalToConstant: 11).isActive = true
        placeLabel.font = SPFont.text(12, weight: .medium, relativeTo: .footnote)
        placeLabel.textColor = SPColor.secondaryInk
        placeLabel.adjustsFontForContentSizeCategory = true
        placeLabel.numberOfLines = 1
        let placeRow = UIStackView(axis: .horizontal, spacing: 5, alignment: .center)
        placeRow.addArrangedSubview(pin)
        placeRow.addArrangedSubview(placeLabel)

        let statusRow = UIStackView(axis: .vertical, spacing: 13, alignment: .center)
        statusRow.addArrangedSubview(statusContainer)
        statusRow.addArrangedSubview(timerLabel)
        statusRow.addArrangedSubview(placeRow)
        view.addSubview(statusRow)
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusRow.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 28),
            statusRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            timerLabel.widthAnchor.constraint(equalTo: statusRow.widthAnchor)
        ])

        buildMeterCard()
        view.addSubview(meterCard)
        NSLayoutConstraint.activate([
            meterCard.topAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: 26),
            meterCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            meterCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        bannerHolder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerHolder)
        NSLayoutConstraint.activate([
            bannerHolder.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bannerHolder.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bannerHolder.topAnchor.constraint(equalTo: meterCard.bottomAnchor, constant: 10)
        ])

        buildControls()
        view.addSubview(pauseButton)
        view.addSubview(stopButton)
        view.addSubview(markerButton)
        view.addSubview(pauseCaption)
        view.addSubview(stopCaption)
        view.addSubview(markerCaption)

        let controls = UIStackView(axis: .horizontal, spacing: 8, alignment: .center, distribution: .fillEqually)
        for item in [makeControlStack(button: pauseButton, caption: pauseCaption),
                     makeControlStack(button: stopButton, caption: stopCaption),
                     makeControlStack(button: markerButton, caption: markerCaption)] {
            controls.addArrangedSubview(item)
        }
        view.addSubview(controls)
        controls.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = "Recording continues even if you lock the screen."
        hint.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        hint.textColor = SPColor.tertiaryInk
        hint.textAlignment = .center
        hint.adjustsFontForContentSizeCategory = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -14),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bannerHolder.bottomAnchor.constraint(lessThanOrEqualTo: controls.topAnchor, constant: -12)
        ])

        // 小屏时压缩中间间距。
        let compact = meterCard.topAnchor.constraint(equalTo: bannerHolder.bottomAnchor, constant: -120)
        compact.priority = .defaultLow
        compact.isActive = true

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        markerButton.addTarget(self, action: #selector(markerTapped), for: .touchUpInside)
    }

    private func buildMeterCard() {
        let stack = UIStackView(axis: .vertical, spacing: 10)
        let header = UIStackView(axis: .horizontal, spacing: 8, alignment: .center)
        let title = UILabel()
        title.text = "Input level"
        title.font = SPFont.text(11, weight: .semibold, relativeTo: .caption1)
        title.textColor = SPColor.secondaryInk
        title.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        let liveLabel = UILabel()
        liveLabel.text = "Live"
        liveLabel.font = SPFont.mono(9, weight: .semibold, relativeTo: .caption2)
        liveLabel.textColor = SPColor.record
        liveLabel.adjustsFontForContentSizeCategory = true
        header.addArrangedSubview(liveLabel)
        stack.addArrangedSubview(header)
        liveMeter.heightAnchor.constraint(equalToConstant: 98).isActive = true
        stack.addArrangedSubview(liveMeter)
        meterCard.addContent(stack, insets: UIEdgeInsets(top: 14, left: 16, bottom: 13, right: 16))
    }

    private func buildControls() {
        configureCircleButton(pauseButton, diameter: 68, background: SPColor.sunken, tint: SPColor.ink, pointSize: 22)
        configureCircleButton(stopButton, diameter: 82, background: SPColor.record, tint: .white, pointSize: 26)
        configureCircleButton(markerButton, diameter: 56, background: SPColor.accentSoft, tint: SPColor.accent, pointSize: 18)

        pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
        stopButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)), for: .normal)
        markerButton.setImage(UIImage(systemName: "bookmark.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)

        pauseButton.accessibilityLabel = "Pause"
        stopButton.accessibilityLabel = "Stop Recording"
        markerButton.accessibilityLabel = "Record Sound Event"

        pauseCaption.text = "Pause"
        stopCaption.text = "Stop"
        markerCaption.text = "Marker"
        for label in [pauseCaption, stopCaption, markerCaption] {
            label.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
            label.textColor = SPColor.secondaryInk
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
        }
        stopCaption.textColor = SPColor.record
    }

    private func configureCircleButton(_ button: UIButton, diameter: CGFloat, background: UIColor, tint: UIColor, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = background
        button.tintColor = tint
        button.layer.cornerRadius = diameter / 2
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        button.accessibilityTraits = .button
    }

    private func makeControlStack(button: UIButton, caption: UILabel) -> UIView {
        let container = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        container.addSubview(caption)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            caption.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 9),
            caption.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func bindService() {
        service.onStateChange = { [weak self] state in
            self?.updateState(state)
        }
        service.onUpdate = { [weak self] elapsed, level, history in
            guard let self else { return }
            self.timerLabel.text = SPFormat.duration(elapsed)
            self.timerLabel.accessibilityValue = SPFormat.accessibleDuration(elapsed)
            self.liveMeter.update(levels: history, level: level, active: self.service.state == .recording)
        }
        service.onInterruption = { [weak self] message in
            self?.showBanner(message: message)
        }
        service.onError = { [weak self] message in
            self?.showRecordingError(message)
        }
    }

    // MARK: - 状态

    private func updateState(_ state: RecordingState) {
        switch state {
        case .preparing:
            setStatus(text: "Preparing", dotColor: SPColor.amber, background: SPColor.amberSoft)
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            markerButton.isEnabled = false
        case .recording:
            setStatus(text: "Recording", dotColor: SPColor.record, background: SPColor.record.withAlphaComponent(0.11))
            pauseButton.isEnabled = true
            stopButton.isEnabled = true
            markerButton.isEnabled = true
            pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
            pauseCaption.text = "Pause"
            pauseButton.accessibilityLabel = "Pause"
            startPulse()
        case .paused:
            setStatus(text: "Paused", dotColor: SPColor.amber, background: SPColor.amberSoft)
            pauseButton.isEnabled = true
            stopButton.isEnabled = true
            markerButton.isEnabled = true
            pauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
            pauseCaption.text = "Resume"
            pauseButton.accessibilityLabel = "Resume Recording"
            stopPulse()
        case .finalizing:
            setStatus(text: "Finalizing", dotColor: SPColor.accent, background: SPColor.accentSoft)
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            markerButton.isEnabled = false
            stopPulse()
        case .failed(let message):
            setStatus(text: "Recording error", dotColor: SPColor.danger, background: SPColor.dangerSoft)
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            markerButton.isEnabled = false
            showBanner(message: message)
            stopPulse()
        case .idle:
            if isStopping { return }
            setStatus(text: "Idle", dotColor: SPColor.tertiaryInk, background: SPColor.sunken)
        }
        pauseButton.alpha = pauseButton.isEnabled ? 1 : 0.42
        stopButton.alpha = stopButton.isEnabled ? 1 : 0.48
        markerButton.alpha = markerButton.isEnabled ? 1 : 0.42
        pauseCaption.alpha = pauseButton.isEnabled ? 1 : 0.55
        stopCaption.alpha = stopButton.isEnabled ? 1 : 0.55
        markerCaption.alpha = markerButton.isEnabled ? 1 : 0.55
        updateLiveActivity(for: state)
        announceIfNeeded(state)
    }

    private func announceIfNeeded(_ state: RecordingState) {
        let message: String?
        switch state {
        case .recording:
            message = pauseCaption.text == "Resume" ? "Recording paused" : "Recording started"
        case .paused:
            message = "Recording paused"
        case .finalizing:
            message = "Saving recording"
        case .failed(let reason):
            message = "Recording error. \(reason)"
        case .preparing, .idle:
            message = nil
        }
        guard let message, message != lastAnnouncedState else { return }
        lastAnnouncedState = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func setStatus(text: String, dotColor: UIColor, background: UIColor) {
        statusLabel.text = text
        statusLabel.textColor = dotColor
        statusDot.backgroundColor = dotColor
        statusContainer.backgroundColor = background
        statusContainer.accessibilityLabel = text
    }

    private func startPulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        stopPulse()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.25
        animation.duration = 0.85
        animation.autoreverses = true
        animation.repeatCount = .infinity
        statusDot.layer.add(animation, forKey: "pulse")
    }

    private func stopPulse() {
        statusDot.layer.removeAnimation(forKey: "pulse")
    }

    private func showBanner(message: String) {
        interruptionBanner?.removeFromSuperview()
        let banner = SPInfoBanner(title: "Recording Notice", message: message, tone: .warning)
        bannerHolder.addArrangedSubview(banner)
        interruptionBanner = banner
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func hideBanner() {
        interruptionBanner?.removeFromSuperview()
        interruptionBanner = nil
    }

    private func updatePlace() {
        if let placeID, let place = library.fetchPlace(id: placeID) {
            placeLabel.text = place.name
            recordingPlaceName = place.name
        } else {
            placeLabel.text = "You can set a place when saving"
            recordingPlaceName = nil
        }
    }

    private func updateLiveActivity(for state: RecordingState) {
        guard #available(iOS 16.2, *) else { return }
        let manager = RecordingLiveActivityManager.shared
        switch state {
        case .recording:
            if manager.isActive {
                manager.update(
                    elapsed: service.currentElapsed,
                    isPaused: false,
                    placeName: recordingPlaceName
                )
            } else {
                manager.start(placeName: recordingPlaceName, quality: RecordingQuality.current)
            }
        case .paused:
            manager.update(
                elapsed: service.currentElapsed,
                isPaused: true,
                placeName: recordingPlaceName
            )
        case .finalizing, .failed, .idle:
            manager.end()
        case .preparing:
            break
        }
    }

    private func showRecordingError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Recording Failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: - 操作

    @objc private func pauseTapped() {
        if service.state == .recording {
            service.pause()
        } else if service.state == .paused {
            hideBanner()
            service.resume()
        }
    }

    @objc private func markerTapped() {
        let sheet = UIAlertController(title: "Record Sound Event", message: "Adds a marker at the current position.", preferredStyle: .actionSheet)
        if !service.markers.isEmpty {
            sheet.addAction(UIAlertAction(title: "Remove Last Marker", style: .destructive) { [weak self] _ in
                self?.service.removeLastMarker()
                self?.updateMarkerCaption()
            })
        }
        for kind in EventKind.allCases {
            sheet.addAction(UIAlertAction(title: kind.title, style: .default) { [weak self] _ in
                self?.service.addMarker(kind: kind)
                self?.updateMarkerCaption()
                UIAccessibility.post(notification: .announcement, argument: "Added a \(kind.title) marker")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = markerButton
            popover.sourceRect = markerButton.bounds
        }
        present(sheet, animated: true)
    }

    private func updateMarkerCaption() {
        let count = service.markers.count
        markerCaption.text = count == 0 ? "Marker" : "Marker \(count)"
        markerButton.accessibilityLabel = count == 0
            ? "Record Sound Event"
            : "Record Sound Event, \(count) markers"
    }

    @objc private func stopTapped() {
        guard !isStopping else { return }
        isStopping = true
        stopButton.isEnabled = false
        pauseButton.isEnabled = false
        markerButton.isEnabled = false
        let overlay = SPLoadingOverlay(message: "Saving recording safely…")
        overlay.show(in: view)
        service.stop { [weak self] result in
            guard let self else { return }
            overlay.hide()
            self.isStopping = false
            switch result {
            case .success(let recording):
                self.onFinished?(recording)
            case .failure(let error):
                self.stopButton.isEnabled = true
                self.pauseButton.isEnabled = self.service.state == .paused
                self.markerButton.isEnabled = false
                let alert = UIAlertController(
                    title: "Could Not Finish Recording",
                    message: "\(error.localizedDescription)\nThe recorded file has been kept as far as possible.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }

    @objc private func closeTapped() {
        let active: Bool
        switch service.state {
        case .recording, .paused, .preparing, .finalizing: active = true
        default: active = false
        }
        if service.state == .finalizing { return }
        if !active {
            service.discardSession()
            onCancel?()
            return
        }
        presentConfirm(
            title: "Discard This Recording?",
            message: "The recording so far will not be saved.",
            destructiveTitle: "Discard"
        ) { [weak self] in
            guard let self else { return }
            self.service.discardSession()
            self.onCancel?()
        }
    }
}
