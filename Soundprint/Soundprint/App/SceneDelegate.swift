
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppRouter.shared.bootstrap(windowScene: windowScene)
        window = UIWindow.keyWindow()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        StorageManager.shared.retryPendingDeletions()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url, url.scheme == "soundprint" else { return }
        // Live Activity 点击后回到应用；录音流程仍在时无需跳转。
        if !RecordingFlowCoordinator.shared.isActive {
            AppRouter.shared.switchToMainTab(index: 0)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 录音由 RecordingService 自行处理后台与中断，这里不做额外操作。
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        NotificationCenter.default.post(name: SPNotification.storageDidChange, object: nil)
    }
}
