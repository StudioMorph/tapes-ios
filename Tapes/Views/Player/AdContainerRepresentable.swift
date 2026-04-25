import SwiftUI
import UIKit

/// Hosts the UIView and UIViewController required by the IMA SDK's
/// `IMAAdDisplayContainer`. Exposes both via binding so `AdManager`
/// can reference them when requesting ads.
struct AdContainerRepresentable: UIViewControllerRepresentable {

    @Binding var containerView: UIView?
    @Binding var containerViewController: UIViewController?

    func makeUIViewController(context: Context) -> AdContainerViewController {
        let vc = AdContainerViewController()
        DispatchQueue.main.async {
            containerView = vc.adContainerView
            containerViewController = vc
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AdContainerViewController, context: Context) {}
}

final class AdContainerViewController: UIViewController {

    let adContainerView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        adContainerView.translatesAutoresizingMaskIntoConstraints = false
        adContainerView.backgroundColor = .black
        view.addSubview(adContainerView)

        NSLayoutConstraint.activate([
            adContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            adContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            adContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            adContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
