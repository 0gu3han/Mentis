import UIKit
import SwiftUI

/// Presents the AR placement view in a dedicated UIWindow that sits above the main app window.
/// This isolates the AR session completely — the NavigationStack and TabView are unaffected.
final class ARWindowPresenter {
    static let shared = ARWindowPresenter()
    private var arWindow: UIWindow?

    private init() {}

    func present(room: Room) {
        guard arWindow == nil,
              let windowScene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first else { return }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert

        let rootView = ARPlacementHostView(room: room, onWindowDismiss: { [weak self] in
            self?.dismiss()
        })
        let vc = UIHostingController(rootView: rootView)
        vc.view.backgroundColor = .black
        window.rootViewController = vc
        window.makeKeyAndVisible()
        arWindow = window
    }

    func dismiss() {
        arWindow?.isHidden = true
        arWindow = nil
    }
}
