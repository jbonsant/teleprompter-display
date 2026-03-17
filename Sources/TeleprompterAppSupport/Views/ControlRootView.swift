import SwiftUI

public struct ControlRootView: View {
    @ObservedObject private var store: AppSessionStore

    public init(store: AppSessionStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("GPSN Teleprompter Control")
                .font(.system(size: 28, weight: .semibold))

            HStack(spacing: 16) {
                statusCard(title: "Session", value: store.sessionState.rawValue)
                statusCard(title: "Slide", value: store.slideCounter)
                statusCard(title: "Segment", value: store.activeSegmentTitle)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next implementation steps")
                    .font(.headline)
                Text("1. Expand the bundle contracts.")
                Text("2. Replace the compiler stub with real parsing and slide-marker extraction.")
                Text("3. Build the rehearsal harness before tuning alignment thresholds.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.headline)
                Text(store.statusDetail)
                    .foregroundStyle(.secondary)
                Text("References: \(store.referenceDirectory.path)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 860, minHeight: 540)
    }

    private func statusCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .medium))
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
