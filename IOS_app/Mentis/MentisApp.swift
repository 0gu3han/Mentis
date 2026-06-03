import SwiftUI

@main
struct MentisApp: App {
    @StateObject private var appState = AppState()

    init() {
        let surface    = UIColor(Color.mSurface)
        let surfaceLow = UIColor(Color.mSurfaceContainerLow)

        // Window background — eliminates white flash during transitions
        UIWindow.appearance().backgroundColor = surface

        // Navigation bar — dark globally
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = surfaceLow
        navAppearance.titleTextAttributes      = [.foregroundColor: UIColor(Color.mOnSurface)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.mOnSurface)]
        UINavigationBar.appearance().standardAppearance   = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance    = navAppearance
        UINavigationBar.appearance().tintColor            = UIColor(Color.mPrimary)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Fills status bar, home indicator, and any transition gaps
                Color.mSurface
                    .ignoresSafeArea(.all)

                if appState.isLoggedIn {
                    ContentView()
                        .environmentObject(appState)
                } else {
                    LoginView()
                        .environmentObject(appState)
                }
            }
            .ignoresSafeArea(.keyboard)   // keyboard slides over content, doesn't push it
            .preferredColorScheme(.dark)
        }
    }
}
