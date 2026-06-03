import SwiftUI
import simd

/// Full-screen SwiftUI host: AR view + overlay UI + sheets.
struct ARPlacementHostView: View {
    let room: Room
    var onWindowDismiss: (() -> Void)? = nil  // set when presented as UIWindow

    @Environment(\.dismiss) private var dismiss
    @State private var anchors: [Anchor] = []
    @State private var pendingPosition: simd_float3?
    @State private var showAddAnchorSheet = false
    @State private var selectedAnchor: Anchor?
    @State private var errorMessage: String?
    @State private var trackingStatus: String = "Initialising…"

    var body: some View {
        ZStack(alignment: .top) {
            // AR scene fills the screen
            ARPlacementView(
                roomId: room.id,
                anchors: anchors,
                onSurfaceTapped: { pos in
                    pendingPosition = pos
                    showAddAnchorSheet = true
                },
                onAnchorTapped: { anchorId in
                    selectedAnchor = anchors.first(where: { $0.id == anchorId })
                },
                onTrackingStatus: { status in
                    trackingStatus = status
                }
            )
            .ignoresSafeArea()

            // Top bar
            topBar

            // Bottom hint
            VStack {
                Spacer()
                hintBanner
                    .padding(.bottom, 32)
            }
        }
        .statusBarHidden()
        .task { await loadAnchors() }
        // Add anchor sheet
        .sheet(isPresented: $showAddAnchorSheet) {
            if let pos = pendingPosition {
                AddAnchorSheet(position: pos) { label in
                    await createAnchor(label: label, pos: pos)
                }
                .presentationDetents([.medium])
            }
        }
        // Anchor detail sheet
        .sheet(item: $selectedAnchor) { anchor in
            AnchorDetailSheet(anchor: anchor, onObjectAdded: {
                Task { await loadAnchors() }
            })
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

    // MARK: - UI Pieces

    private var topBar: some View {
        HStack {
            Button {
                if let onWindowDismiss { onWindowDismiss() } else { dismiss() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.mOnSurface)
            }
            Spacer()
            Text(room.name)
                .font(.mTitle(15))
                .foregroundStyle(Color.mOnSurface)
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.mSurfaceContainerLow.opacity(0.85))
    }

    private var hintBanner: some View {
        VStack(spacing: 6) {
            // Tracking / scanning status (hidden when normal)
            if !trackingStatus.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.mSecondaryFixedDim)
                    Text(trackingStatus)
                        .font(.mLabel(11))
                        .tracking(0.2)
                        .foregroundStyle(Color.mSecondaryFixedDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.mSurfaceContainerHighest.opacity(0.9), in: Capsule())
            }

            // Action hint
            Text(anchors.isEmpty
                 ? "Tap a surface to place your first anchor"
                 : "Tap a surface to add · tap an anchor to open")
                .font(.mLabel(12))
                .tracking(0.2)
                .foregroundStyle(Color.mOnSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.mSurfaceContainerHigh.opacity(0.85), in: Capsule())
        }
    }

    // MARK: - Data

    private func loadAnchors() async {
        do {
            anchors = try await APIClient.shared.listAnchors(roomId: room.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAnchor(label: String, pos: simd_float3) async {
        do {
            _ = try await APIClient.shared.createAnchor(
                roomId: room.id,
                label: label,
                pos: [pos.x, pos.y, pos.z],
                normal: [0, 1, 0]
            )
            await loadAnchors()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Anchor Sheet

private struct AddAnchorSheet: View {
    let position: simd_float3
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Capital of France", text: $label)
                }
                Section {
                    Text("Position: (\(position.x, specifier: "%.2f"), \(position.y, specifier: "%.2f"), \(position.z, specifier: "%.2f")) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Anchor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(label)
                            dismiss()
                        }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Anchor Detail Sheet

private struct AnchorDetailSheet: View {
    let anchor: Anchor
    let onObjectAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAddObject = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Position") {
                    Text("(\(anchor.pos[0], specifier: "%.2f"), \(anchor.pos[1], specifier: "%.2f"), \(anchor.pos[2], specifier: "%.2f")) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Attached Items (\(anchor.objects.count))") {
                    if anchor.objects.isEmpty {
                        Text("No items yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(anchor.objects) { obj in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(obj.title).font(.subheadline.bold())
                                if !obj.body.isEmpty {
                                    Text(obj.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Button {
                        showAddObject = true
                    } label: {
                        Label("Add Learning Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(anchor.label.isEmpty ? "Anchor" : anchor.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddObject) {
                AddObjectSheet(anchorId: anchor.id, onSaved: {
                    onObjectAdded()
                    dismiss()
                })
                .presentationDetents([.medium])
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
}

// MARK: - Add Object Sheet

private struct AddObjectSheet: View {
    let anchorId: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_  = ""
    @State private var kind   = "text"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Question / Prompt") {
                    TextField("e.g. What is the capital of France?", text: $title)
                }
                Section("Answer / Content") {
                    Picker("Kind", selection: $kind) {
                        Text("Text").tag("text")
                        Text("Link").tag("link")
                    }
                    .pickerStyle(.segmented)

                    if kind == "link" {
                        TextField("https://…", text: $body_)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    } else {
                        TextField("Answer goes here", text: $body_, axis: .vertical)
                            .lineLimit(4...8)
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
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

    private func save() async {
        isSaving = true
        do {
            _ = try await APIClient.shared.createObject(
                anchorId: anchorId,
                title: title.trimmingCharacters(in: .whitespaces),
                kind: kind,
                body: body_.trimmingCharacters(in: .whitespaces)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
