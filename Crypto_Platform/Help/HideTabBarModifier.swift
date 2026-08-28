//
//  HideTabBarModifier.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 19.11.2025.
//

import SwiftUI

struct HideTabBarModifier: ViewModifier {
    @EnvironmentObject var nav: NavigationState

    func body(content: Content) -> some View {
        content
            .onAppear {
                print("HideTabBarModifier ON")
                nav.hideTabBar = true
            }
            .onDisappear {
                print("HideTabBarModifier OFF")
                nav.hideTabBar = false
            }
    }
}

extension View {
    func hideTabBarOnPush() -> some View {
        self.modifier(HideTabBarModifier())
    }
}
