//
//  RootTabBarController.swift
//  Soundprint
//
//  Four main tabs: Home, Places, Compare, Settings.
//

import UIKit

final class RootTabBarController: UITabBarController {
    private var didCheckRecovery = false
    private var previouslySelectedIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = SPColor.paper
        SPStyle.applyTabBarAppearance(tabBar)

        let explore = ExploreViewController().configuredForTab(
            title: "Home",
            symbol: "waveform",
            selectedSymbol: "waveform"
        )
        let places = PlacesViewController().configuredForTab(
            title: "Places",
            symbol: "mappin.and.ellipse",
            selectedSymbol: "mappin.and.ellipse"
        )
        let compare = CompareViewController().configuredForTab(
            title: "Compare",
            symbol: "rectangle.split.2x1",
            selectedSymbol: "rectangle.split.2x1"
        )
        let settings = SettingsViewController().configuredForTab(
            title: "Settings",
            symbol: "gearshape",
            selectedSymbol: "gearshape.fill"
        )
        viewControllers = [explore, places, compare, settings]
        selectedIndex = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didCheckRecovery else { return }
        didCheckRecovery = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.checkRecoveredRecording()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    private func checkRecoveredRecording() {
        guard !RecordingFlowCoordinator.shared.isActive else { return }
        guard let recovered = RecordingDraftStore.shared.recoverIfNeeded() else { return }

        let alert = UIAlertController(
            title: "Interrupted Recording Found",
            message: "You can recover your previous recording (\(SPFormat.duration(recovered.duration))). Review it and save.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            try? FileManager.default.removeItem(at: recovered.temporaryURL)
            RecordingDraftStore.shared.clear()
            self?.view.setNeedsLayout()
        })
        alert.addAction(UIAlertAction(title: "Recover", style: .default) { [weak self] _ in
            guard let self else { return }
            RecordingFlowCoordinator.shared.presentRecovery(from: self, recovered: recovered) { [weak self] record in
                guard let self, let record else { return }
                self.openRecordingAfterRecovery(record)
            }
        })
        present(alert, animated: true)
    }

    private func openRecordingAfterRecovery(_ record: RecordingEntity) {
        selectedIndex = 0
        guard let nav = viewControllers?.first as? UINavigationController else { return }
        nav.popToRootViewController(animated: false)
        let detail = RecordingDetailViewController(recordingID: record.id)
        nav.pushViewController(detail, animated: true)
        SPToast.show("Recording recovered", in: nav.view)
    }
}

extension RootTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        SPHaptic.selection()
        let isReselecting = previouslySelectedIndex == tabBarController.selectedIndex
        previouslySelectedIndex = tabBarController.selectedIndex
        guard isReselecting,
              let nav = viewController as? UINavigationController,
              nav.viewControllers.count > 1 else { return }
        nav.popToRootViewController(animated: true)
    }
}
