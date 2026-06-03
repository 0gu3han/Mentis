import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    init() {
        // Dark tab bar to match the design system
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.mSurfaceContainerLow)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.mSecondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.mSecondary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.mPrimary)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.mPrimary)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            RoomListView()
                .tabItem {
                    Label("Rooms", systemImage: "cube.transparent")
                }

            ReviewView()
                .tabItem {
                    Label("Review", systemImage: "brain.head.profile")
                }
        }
        .tint(Color.mPrimary)
        .background(Color.mSurface.ignoresSafeArea(.all))
    }
}
