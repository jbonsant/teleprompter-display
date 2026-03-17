import SwiftUI

public struct TeleprompterRootView: View {
    @ObservedObject private var store: AppSessionStore

    public init(store: AppSessionStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.13, green: 0.15, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(store.activeSegmentTitle)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.45))

                ForEach(Array(store.teleprompterBlocks.enumerated()), id: \.offset) { index, block in
                    Text(block)
                        .font(.system(size: index == 0 ? 42 : 34, weight: index == 0 ? .bold : .regular))
                        .foregroundStyle(.white)
                        .opacity(index == 0 ? 1.0 : 0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label(store.slideCounter, systemImage: "play.rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(red: 0.88, green: 0.91, blue: 0.95))

                Spacer()
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 56)
        }
        .frame(minWidth: 1280, minHeight: 720)
    }
}
