import SwiftUI

// Matches the demo rooms shown on the web app — visible to every user
private struct DemoRoom: Identifiable {
    let id: String
    let name: String
    let sketchfabId: String
    var safariURL: URL { URL(string: "https://sketchfab.com/models/\(sketchfabId)")! }
}

private let DEMO_ROOMS: [DemoRoom] = [
    DemoRoom(id: "sf-1", name: "Living Room",              sketchfabId: "927ef282eceb47e29397b52147d4d6c3"),
    DemoRoom(id: "sf-2", name: "Loft Apartment",           sketchfabId: "44e7a9cfed67431e827d0cbaabd462c7"),
    DemoRoom(id: "sf-3", name: "Modular Classroom Preview",sketchfabId: "3ecfa670dbd946ec80b49d7df74ab453"),
    DemoRoom(id: "sf-4", name: "The Billiards Room",       sketchfabId: "79615d823a9149069dcd06c20bc9707f"),
]

struct RoomListView: View {
    @EnvironmentObject var appState: AppState
    @State private var rooms: [Room] = []
    @State private var isLoading = false
    @State private var showScan = false
    @State private var selectedDemoRoom: DemoRoom?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mSurface.ignoresSafeArea()

                Group {
                    if isLoading && rooms.isEmpty {
                        ProgressView()
                            .tint(Color.mPrimary)
                    } else if rooms.isEmpty {
                        emptyState
                    } else {
                        roomList
                    }
                }
            }
            .navigationTitle("My Rooms")
            .toolbarBackground(Color.mSurfaceContainerLow, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showScan = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.mPrimary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out") { appState.logout() }
                        .font(.mLabel())
                        .foregroundStyle(Color.mSecondary)
                }
            }
            .task { await loadRooms() }
            .refreshable { await loadRooms() }
            .sheet(isPresented: $showScan) {
                ScanView()
            }
            .onChange(of: showScan) { isShowing in
                if !isShowing { Task { await loadRooms() } }
            }
            .sheet(item: $selectedDemoRoom) { demo in
                SafariView(url: demo.safariURL)
                    .ignoresSafeArea()
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Glowing icon
            ZStack {
                Circle()
                    .fill(Color.mSecondary.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.mSecondary)
            }
            VStack(spacing: 8) {
                Text("No Rooms Yet")
                    .font(.mTitle())
                    .foregroundStyle(Color.mOnSurface)
                Text("Scan or create a room to start\nbuilding your memory palace.")
                    .font(.mBody())
                    .foregroundStyle(Color.mSecondary)
                    .multilineTextAlignment(.center)
            }
            Button { showScan = true } label: {
                Text("Create First Room")
                    .font(.mLabel(13))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.mGradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Room List

    private var roomList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                // ── My Rooms ──
                if !rooms.isEmpty {
                    sectionLabel("MY ROOMS")
                    ForEach(rooms) { room in
                        NavigationLink(destination: RoomDetailView(room: room)) {
                            RoomRow(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ── Demo Rooms (always shown) ──
                sectionLabel("DEMO ROOMS")
                ForEach(DEMO_ROOMS) { demo in
                    Button { selectedDemoRoom = demo } label: {
                        DemoRoomRow(demo: demo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.mLabel(11))
            .tracking(0.8)
            .foregroundStyle(Color.mSecondary)
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    private func loadRooms() async {
        isLoading = true
        do {
            rooms = try await APIClient.shared.listRooms()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

}

// MARK: - Safari View (for demo rooms)

import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Demo Room Row

private struct DemoRoomRow: View {
    let demo: DemoRoom
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.mSurfaceContainerHigh)
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .foregroundStyle(Color.mSecondaryFixedDim)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(demo.name)
                    .font(.mTitle(15))
                    .foregroundStyle(Color.mOnSurface)
                Text("Sketchfab · tap to open in browser")
                    .font(.mLabel(11))
                    .tracking(0.3)
                    .foregroundStyle(Color.mSecondary)
            }
            Spacer()
            Image(systemName: "safari")
                .font(.system(size: 14))
                .foregroundStyle(Color.mOutlineVariant)
        }
        .padding(16)
        .background(Color.mSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 8)
    }
}

// MARK: - Room Row

private struct RoomRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 16) {
            // Icon pedestal
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.mSurfaceContainerHigh)
                    .frame(width: 44, height: 44)
                Image(systemName: "cube.transparent.fill")
                    .foregroundStyle(Color.mPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.mTitle(15))
                    .foregroundStyle(Color.mOnSurface)
                Text(formattedDate)
                    .font(.mLabel(11))
                    .tracking(0.3)
                    .foregroundStyle(Color.mSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.mOutlineVariant)
        }
        .padding(16)
        .background(Color.mSurfaceContainerHigh,
                    in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 8)
    }

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: room.created_at) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return room.created_at
    }
}

// MARK: - Room Detail

struct RoomDetailView: View {
    let room: Room
    @State private var anchors: [Anchor] = []
    @State private var isLoading = false
    @State private var showModel = false

    var body: some View {
        ZStack {
            Color.mSurface.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Mode selection cards
                    HStack(spacing: 12) {
                        // AR Mode — opens in a separate UIWindow so it's fully isolated
                        ModeCard(
                            icon: "arkit",
                            title: "AR Mode",
                            subtitle: "Live camera\nanchor placement"
                        ) { ARWindowPresenter.shared.present(room: room) }

                        // 3D Model
                        ModeCard(
                            icon: "cube.transparent",
                            title: "3D Model",
                            subtitle: "View mesh · place\nanchors · export"
                        ) { showModel = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Anchors section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ANCHORS")
                            .font(.mLabel())
                            .tracking(0.8)
                            .foregroundStyle(Color.mSecondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        if anchors.isEmpty && !isLoading {
                            Text("No anchors yet. Use AR or 3D mode to place them.")
                                .font(.mBody())
                                .foregroundStyle(Color.mSecondary)
                                .padding(.horizontal, 16)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(anchors) { anchor in
                                    AnchorRow(anchor: anchor)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.mSurfaceContainerLow, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadAnchors() }
        .refreshable { await loadAnchors() }
        .fullScreenCover(isPresented: $showModel) {
            ModelViewerView(room: room)
        }
        .onChange(of: showModel) { if !$0 { Task { await loadAnchors() } } }
    }

    private func loadAnchors() async {
        isLoading = true
        anchors = (try? await APIClient.shared.listAnchors(roomId: room.id)) ?? []
        isLoading = false
    }
}

// MARK: - Mode Card

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.mPrimaryContainer.opacity(0.6))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.mPrimary)
                }
                VStack(spacing: 4) {
                    Text(title)
                        .font(.mTitle(14))
                        .foregroundStyle(Color.mOnSurface)
                    Text(subtitle)
                        .font(.mLabel(11))
                        .tracking(0.2)
                        .foregroundStyle(Color.mSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.mSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Anchor Row

private struct AnchorRow: View {
    let anchor: Anchor

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.mPrimary.opacity(0.2))
                .frame(width: 8, height: 8)
                .overlay(Circle().fill(Color.mPrimary).frame(width: 4, height: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(anchor.label.isEmpty ? "(unlabeled)" : anchor.label)
                    .font(.mTitle(14))
                    .foregroundStyle(Color.mOnSurface)
                Text("\(anchor.objects.count) item\(anchor.objects.count == 1 ? "" : "s")")
                    .font(.mLabel(11))
                    .foregroundStyle(Color.mSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.mSurfaceContainer,
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
