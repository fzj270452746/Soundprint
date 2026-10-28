//
//  SplashViewController.swift
//  Soundprint
//
//  启动首屏：首帧与系统启动屏（UILaunchScreen）保持同一画面，
//  随后播放一次短暂动画，由 AppRouter 切换到实际界面。
//

import UIKit


final class SplashViewController: UIViewController {

    /// 动画开始前调用，用于预热即将展示的根控制器。
    var onPrepare: (() -> Void)?
    /// 动画结束后调用，由 AppRouter 完成根控制器切换。
    var onFinished: (() -> Void)?

    private let logoView = UIImageView(image: UIImage(named: "LaunchMark"))
    private var hasStarted = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // 与 LaunchPaper 完全一致，避免首帧与系统启动屏之间出现跳变。
        view.backgroundColor = UIColor(named: "LaunchPaper") ?? SPColor.paper

        // 尺寸交给图片自身的点尺寸（LaunchMark@3x 为 480px → 160pt），
        // 与系统启动屏按原始点尺寸居中的表现一致。
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.contentMode = .scaleAspectFit
        view.addSubview(logoView)

        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        startAnimation()
    }

    private func startAnimation() {
        // 先把根控制器建好，切换时才不会掉帧。
        onPrepare?()

        guard !UIAccessibility.isReduceMotionEnabled else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.onFinished?()
            }
            return
        }

        // 先静止片刻完成与系统启动屏的衔接，再轻微放大并淡出，
        // 避免“从透明淡入”造成的闪烁。
        UIView.animate(withDuration: 0.45, delay: 0.15, options: [.curveEaseIn]) {
            self.logoView.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
            self.logoView.alpha = 0
        } completion: { _ in
            self.onFinished?()
        }
    }
}
