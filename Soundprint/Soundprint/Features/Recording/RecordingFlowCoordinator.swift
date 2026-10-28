//
//  RecordingFlowCoordinator.swift
//  Soundprint
//
//  管理“录制 → 保存”全屏流程以及中断录音的恢复入口。
//

import UIKit

final class RecordingFlowCoordinator {
    static let shared = RecordingFlowCoordinator()

    private weak var presenter: UIViewController?
    private var navigationController: UINavigationController?
    private var service: RecordingService?
    private var onSaved: ((RecordingEntity?) -> Void)?

    var isActive: Bool { navigationController != nil }

    private init() {}

    func present(
        from presenter: UIViewController,
        placeID: UUID?,
        onSaved: @escaping (RecordingEntity?) -> Void
    ) {
        guard navigationController == nil else { return }
        self.presenter = presenter
        self.onSaved = onSaved

        let service = RecordingService()
        self.service = service
        let recording = RecordingViewController(service: service, placeID: placeID)
        recording.onFinished = { [weak self] result in
            self?.showSaveScreen(result: result, isRecovery: false, placeID: result.placeID)
        }
        recording.onCancel = { [weak self] in
            self?.finishWithoutResult()
        }

        let nav = UINavigationController(rootViewController: recording)
        nav.setNavigationBarHidden(true, animated: false)
        nav.modalPresentationStyle = .fullScreen
        navigationController = nav
        presenter.present(nav, animated: true)
    }

    func presentRecovery(from presenter: UIViewController, recovered: RecoveredRecording, onSaved: @escaping (RecordingEntity?) -> Void) {
        guard navigationController == nil else { return }
        self.presenter = presenter
        self.onSaved = onSaved

        let result = RecordingResult(
            id: recovered.draft.id,
            temporaryURL: recovered.temporaryURL,
            duration: recovered.duration,
            sampleRate: recovered.sampleRate,
            channelCount: recovered.channelCount,
            createdAt: recovered.draft.createdAt,
            markers: recovered.draft.markers,
            placeID: recovered.draft.placeID,
            quality: recovered.draft.quality
        )
        let save = SaveRecordingViewController(result: result, isRecovery: true)
        save.onSaved = { [weak self] record in
            self?.complete(record: record)
        }
        save.onDiscard = { [weak self] in
            self?.finishWithoutResult()
        }
        let nav = UINavigationController(rootViewController: save)
        SPStyle.applyNavigationAppearance(to: nav)
        nav.modalPresentationStyle = .fullScreen
        navigationController = nav
        presenter.present(nav, animated: true)
    }

    private func showSaveScreen(result: RecordingResult, isRecovery: Bool, placeID: UUID?) {
        guard let nav = navigationController, let service else { return }
        let save = SaveRecordingViewController(result: result, isRecovery: isRecovery)
        save.onSaved = { [weak self] record in
            service.markSessionSaved()
            self?.complete(record: record)
        }
        save.onDiscard = { [weak self] in
            service.discardSession()
            self?.finishWithoutResult()
        }
        nav.setNavigationBarHidden(false, animated: true)
        nav.pushViewController(save, animated: true)
    }

    private func complete(record: RecordingEntity) {
        guard let nav = navigationController else { return }
        let callback = onSaved
        cleanup()
        nav.dismiss(animated: true) {
            callback?(record)
        }
    }

    private func finishWithoutResult() {
        guard let nav = navigationController else { return }
        let callback = onSaved
        service?.discardSession()
        cleanup()
        nav.dismiss(animated: true) {
            callback?(nil)
        }
    }

    private func cleanup() {
        navigationController = nil
        service = nil
        presenter = nil
        onSaved = nil
    }
}
