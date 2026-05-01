import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "cube.transparent.fill",
            iconColor: .blue,
            title: "Capture the World in 3D",
            body: "Laseris turns your iPhone into a 3D scanner using its built-in LiDAR sensor. Sweep your camera around an object or room and watch a 3D model build in real time."
        ),
        OnboardingPage(
            icon: "sensor.tag.radiowaves.forward.fill",
            iconColor: .orange,
            title: "How LiDAR Scanning Works",
            body: "Your iPhone projects invisible laser dots and measures how long they take to return. This builds an accurate mesh of every surface in front of you — colored by the camera at the same time."
        ),
        OnboardingPage(
            icon: "figure.walk.motion",
            iconColor: .green,
            title: "Tips for Great Scans",
            tips: [
                "Move slowly and smoothly — let the mesh fill in",
                "Bright, even light gives better colors",
                "Walk around your subject to get all angles",
                "Stay 0.5 to 5 meters from what you're scanning",
                "Watch for gaps — point the camera there to fill them"
            ]
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .indigo,
            title: "Private by Default",
            body: "Everything stays on your device. Scans are processed locally and saved to your iPhone — no servers, no uploads, no accounts. You decide what to share and with whom."
        )
    ]

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Bottom action button
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.18),
                Color(red: 0.10, green: 0.05, blue: 0.20),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Bottom button

    private var bottomButton: some View {
        Button {
            if page < pages.count - 1 {
                withAnimation { page += 1 }
            } else {
                dismiss()
            }
        } label: {
            HStack {
                Text(page < pages.count - 1 ? "Continue" : "Get Started")
                    .font(.headline)
                Image(systemName: page < pages.count - 1 ? "arrow.right" : "checkmark")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Page model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    var body: String? = nil
    var tips: [String]? = nil
}

// MARK: - Page view

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(page.iconColor)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 8)

            Text(page.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)

            if let body = page.body {
                Text(body)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }

            if let tips = page.tips {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                                .padding(.top, 2)
                            Text(tip)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()  // extra bottom space to leave room for paging dots + button
        }
    }
}
