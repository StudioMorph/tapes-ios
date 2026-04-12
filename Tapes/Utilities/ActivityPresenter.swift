import UIKit

/// Presents `UIActivityViewController` from the topmost view controller so it works when
/// the caller is already inside a SwiftUI sheet (presenting from `rootViewController` alone fails).
enum ActivityPresenter {
    static func present(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let ac = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
            if let pop = ac.popoverPresentationController {
                pop.sourceView = top.view
                let b = top.view?.bounds ?? .zero
                pop.sourceRect = CGRect(x: b.midX, y: b.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            top.present(ac, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                if let root = window.rootViewController {
                    return findTop(from: root)
                }
            }
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            return findTop(from: root)
        }
        return nil
    }

    private static func findTop(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return findTop(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return findTop(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return findTop(from: selected)
        }
        return vc
    }
}
