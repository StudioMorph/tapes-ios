//
//  AppearanceConfigurator.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import UIKit

enum AppearanceConfigurator {
    static func setupNavigationBar(overlayColor: UIColor? = nil) {
        // Use our primary background color instead of transparent
        let primaryBackground = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#14202F") : UIColor(hex: "#FFFFFF")
        }
        
        let base = UINavigationBarAppearance()
        base.configureWithOpaqueBackground()
        base.backgroundEffect = nil
        base.backgroundColor = overlayColor ?? primaryBackground
        base.shadowColor = .clear
        base.titleTextAttributes = [.foregroundColor: UIColor.label]
        base.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        let nav = UINavigationBar.appearance()
        nav.isTranslucent = false
        nav.standardAppearance = base
        nav.scrollEdgeAppearance = base
        nav.compactAppearance = base
        if #available(iOS 15.0, *) {
            nav.compactScrollEdgeAppearance = base
        }
    }
}
