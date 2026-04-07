import SwiftUI

struct ScanCard: View {
    let scan: Scan
    @EnvironmentObject var store: ScanStore

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(scan.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(scan.formattedVertexCount)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbURL = store.thumbnailURL(for: scan),
           let data = try? Data(contentsOf: thumbURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
