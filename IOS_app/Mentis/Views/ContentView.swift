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

            Group {
                if #available(iOS 17.4, *) {
                    LanguageLearnView()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "translate")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.mSecondary)
                        Text("Language Learning requires iOS 17.4 or later.")
                            .font(.mBody())
                            .foregroundStyle(Color.mSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.mSurface)
                }
            }
            .tabItem {
                Label("Learn", systemImage: "translate")
            }
        }
        .tint(Color.mPrimary)
        .background(Color.mSurface.ignoresSafeArea(.all))
    }
}
