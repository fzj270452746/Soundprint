//
//  AppRouter.swift
//  Soundprint
//
//  管理根控制器切换（引导页 / 主界面）以及最上层的展示容器。
//

import UIKit


enum RStyle {
    case record
    case stop
}

final class AppRouter {
    static let shared = AppRouter()

    private weak var window: UIWindow?
    private var isTransitioning = false
    /// 启动首屏动画期间预建好的根控制器。
    private var prewarmedRoot: UIViewController?

    private init() {}

    func bootstrap(windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        SPStyle.applyGlobalAppearance()

        // 首屏与系统启动屏（UILaunchScreen）保持同一画面，动画结束后再切入实际界面。
        let splash = SplashViewController()
//        splash.onPrepare = { [weak self] in self?.prepareRootAfterSplash() }
        
        splash.onFinished = { [weak self] in
            self?.finishSplash()
        }
        window.rootViewController = splash
        window.makeKeyAndVisible()
    }

    // MARK: - 启动首屏

    /// 动画期间建立并布局即将展示的根控制器，减少切换时的掉帧。
    private func prepareRootAfterSplash() {
        guard prewarmedRoot == nil else { return }
        let root = makeInitialRoot()
        root.view.layoutIfNeeded()
        prewarmedRoot = root
    }

    private func finishSplash() {
        guard let window else { return }
        
        let root = prewarmedRoot ?? makeInitialRoot()

        guard !UIAccessibility.isReduceMotionEnabled else {
            window.rootViewController = root
            return
        }

        UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve]) {
            window.rootViewController = root
        }
    }

    /// 启动首屏结束后要展示的界面。
    private func makeInitialRoot() -> UIViewController {
        // 引导页逻辑暂时关闭（与 bootstrap 原有行为一致）；
        // 恢复时改为按 SPDefaultsKey.onboardingCompleted 分流到 makeOnboardingRoot()。
        makeMainRoot()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: SPDefaultsKey.onboardingCompleted)
        showMain(animated: true)
    }

    func showMain(animated: Bool = true) {
        guard let window, !isTransitioning else { return }
        let root = makeMainRoot()
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            window.rootViewController = root
            return
        }
        isTransitioning = true
        UIView.transition(with: window, duration: 0.42, options: [.transitionCrossDissolve]) {
            window.rootViewController = root
        } completion: { _ in
            self.isTransitioning = false
        }
    }

    func showOnboarding() {
        guard let window else { return }
        UserDefaults.standard.set(false, forKey: SPDefaultsKey.onboardingCompleted)
        window.rootViewController = makeOnboardingRoot()
    }

    private func makeMainRoot() -> UIViewController {
        RootTabBarController()
    }

    private func makeOnboardingRoot() -> UIViewController {
        OnboardingViewController { [weak self] in
            self?.completeOnboarding()
        }
    }

    // MARK: - 顶层容器

    func topViewController() -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        if let tab = controller as? UITabBarController {
            var selected = tab.selectedViewController
            while let nav = selected as? UINavigationController {
                selected = nav.visibleViewController ?? nav
                break
            }
            if let nav = tab.selectedViewController as? UINavigationController {
                var visible = nav.visibleViewController
                while let presented = visible?.presentedViewController {
                    visible = presented
                }
                return visible ?? nav
            }
            return selected
        }
        if let nav = controller as? UINavigationController {
            return nav.visibleViewController ?? nav
        }
        return controller
    }

    func switchToMainTab(index: Int) {
        guard let tab = window?.rootViewController as? RootTabBarController else { return }
        tab.selectedIndex = min(max(0, index), tab.viewControllers?.count ?? 1 - 1)
    }
}
