import SwiftUI

struct ScanOverlayView: View {
    @ObservedObject var scanner: LiDARScanner

    var onClose: () -> Void
    var onReset: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack {
            topBar
            Spacer()
            if let error = scanner.sessionError {
                errorBanner(error)
            }
            bottomBar
        }
        .padding()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Stats pill
            HStack(spacing: 12) {
                Label(scanner.vertexCount.formatted(), systemImage: "dot.radiowaves.up.forward")
                Label(scanner.meshAnchors.count.formatted() + " chunks", systemImage: "square.3.layers.3d")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Reset button
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Spacer()

            // Main capture/finish button
            Button(action: onFinish) {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 32, height: 32)
                }
            }
            .disabled(scanner.vertexCount == 0)
            .opacity(scanner.vertexCount == 0 ? 0.4 : 1)

            Spacer()
        }
        .padding(.bottom, 20)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
    }
}
