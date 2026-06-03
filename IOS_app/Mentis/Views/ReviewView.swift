import SwiftUI

struct ReviewView: View {
    @State private var current: ReviewResponse?
    @State private var isLoading = false
    @State private var showAnswer = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mSurface.ignoresSafeArea()

                Group {
                    if isLoading {
                        ProgressView()
                            .tint(Color.mPrimary)
                    } else if let item = current, item.review_id != nil {
                        reviewCard(item)
                    } else {
                        allDoneView
                    }
                }
            }
            .navigationTitle("Review")
            .toolbarBackground(Color.mSurfaceContainerLow, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await loadNext() }
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

    // MARK: - All Done

    private var allDoneView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.mSecondaryFixedDim.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.mSecondaryFixedDim)
            }
            VStack(spacing: 8) {
                Text("All caught up!")
                    .font(.mTitle(22))
                    .foregroundStyle(Color.mOnSurface)
                Text("No reviews due right now.\nCome back later.")
                    .font(.mBody())
                    .foregroundStyle(Color.mSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Refresh") { Task { await loadNext() } }
                .font(.mLabel(13))
                .tracking(0.4)
                .foregroundStyle(Color.mPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.mSurfaceContainerHigh,
                             in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Review Card

    @ViewBuilder
    private func reviewCard(_ item: ReviewResponse) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Anchor location badge
                    if let anchor = item.anchor {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.mPrimary)
                                .frame(width: 6, height: 6)
                            Text("ANCHOR #\(anchor.id)")
                                .font(.mLabel(11))
                                .tracking(0.8)
                                .foregroundStyle(Color.mSecondary)
                        }
                    }

                    if let obj = item.object {
                        // Question
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RECALL")
                                .font(.mLabel())
                                .tracking(0.8)
                                .foregroundStyle(Color.mSecondary)

                            Text(obj.title)
                                .font(.mDisplay(28))
                                .foregroundStyle(Color.mOnSurface)
                                .tracking(-0.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Divider — "ghost border"
                        Rectangle()
                            .fill(Color.mOutlineVariant.opacity(0.15))
                            .frame(height: 1)

                        // Answer
                        if showAnswer {
                            answerSection(obj)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showAnswer = true
                                }
                            } label: {
                                Text("Show Answer")
                                    .font(.mTitle(15))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(Color.mOnSurface)
                                    .background(Color.mSurfaceContainerHigh,
                                                in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(24)
            }

            if showAnswer, let reviewId = item.review_id {
                gradeBar(reviewId: reviewId)
            }
        }
    }

    @ViewBuilder
    private func answerSection(_ obj: LearningObject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ANSWER")
                .font(.mLabel())
                .tracking(0.8)
                .foregroundStyle(Color.mSecondary)

            if obj.kind == "link", let url = URL(string: obj.body) {
                Link(obj.body, destination: url)
                    .font(.mBody())
                    .foregroundStyle(Color.mPrimary)
            } else {
                Text(obj.body.isEmpty ? "(no content)" : obj.body)
                    .font(.mBody())
                    .foregroundStyle(Color.mOnSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.mSurfaceContainer,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func gradeBar(reviewId: Int) -> some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.mOutlineVariant.opacity(0.15))
                .frame(height: 1)

            Text("HOW WELL DID YOU REMEMBER?")
                .font(.mLabel(10))
                .tracking(0.8)
                .foregroundStyle(Color.mSecondary)

            HStack(spacing: 10) {
                gradeButton("Again", grade: 0,  reviewId: reviewId, color: Color(hex: "#ff6b8a"))
                gradeButton("Hard",  grade: 3,  reviewId: reviewId, color: Color(hex: "#f5a623"))
                gradeButton("Good",  grade: 4,  reviewId: reviewId, color: Color.mPrimary)
                gradeButton("Easy",  grade: 5,  reviewId: reviewId, color: Color.mSecondaryFixedDim)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.mSurfaceContainerLow)
    }

    private func gradeButton(_ label: String, grade: Int, reviewId: Int, color: Color) -> some View {
        Button {
            Task { await submit(reviewId: reviewId, grade: grade) }
        } label: {
            Text(label)
                .font(.mLabel(12))
                .tracking(0.3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(color)
                .background(color.opacity(0.12),
                             in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Actions

    private func loadNext() async {
        isLoading = true
        showAnswer = false
        do {
            current = try await APIClient.shared.nextReview()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submit(reviewId: Int, grade: Int) async {
        do {
            try await APIClient.shared.submitReview(reviewId: reviewId, grade: grade)
            await loadNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
