import SwiftUI
import TeleprompterDomain

public struct ControlRootView: View {
    @ObservedObject private var store: AppSessionStore
    @State private var isRunningPreflight = false
    @State private var rerunningChecks: Set<String> = []

    public init(store: AppSessionStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                readinessPanel
                transportPanel
                    .disabled(store.shouldShowBlockingReadinessScreen)
                    .opacity(store.shouldShowBlockingReadinessScreen ? 0.45 : 1)
                HStack(alignment: .top, spacing: 18) {
                    jumpListsColumn
                        .disabled(store.shouldShowBlockingReadinessScreen)
                        .opacity(store.shouldShowBlockingReadinessScreen ? 0.45 : 1)
                    statusColumn
                }
            }
            .padding(24)
        }
        .background(backgroundGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(store.attentionBorderRequired ? Color.red.opacity(0.9) : Color.white.opacity(0.08), lineWidth: store.attentionBorderRequired ? 4 : 1)
                .padding(10)
        )
        .frame(minWidth: 1180, minHeight: 760)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.14),
                Color(red: 0.11, green: 0.14, blue: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GPSN Teleprompter Control")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    stateBadge
                    Text(store.statusDetail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 20)

            timerMetricCard
            topMetricCard(title: "Slide", value: store.slideCounter)
            topMetricCard(title: "Segment", value: store.segmentPositionText)
        }
        .padding(20)
        .panelBackground()
    }

    private var stateBadge: some View {
        Text(store.stateDisplayName)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(stateBadgeColor.gradient, in: Capsule())
    }

    private var transportPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Transport", detail: "Mouse and keyboard controls stay in sync with the transport state machine.")

            HStack(spacing: 12) {
                Button(action: store.handlePlayPause) {
                    transportLabel(store.playPauseButtonLabel, shortcut: "Space", symbol: store.playPauseButtonLabel == "Pause" ? "pause.fill" : "play.fill")
                }
                .buttonStyle(TransportButtonStyle(tint: .blue))
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!store.canTriggerPlayPause || (store.sessionState == .ready && !store.canStartSession))

                Button(action: store.handleFreeze) {
                    transportLabel(store.freezeButtonLabel, shortcut: "F", symbol: "snowflake")
                }
                .buttonStyle(TransportButtonStyle(tint: .indigo))
                .keyboardShortcut("f", modifiers: [])
                .disabled(!store.canTriggerFreeze)

                Button(action: store.handlePreviousSegment) {
                    transportLabel("Prev Segment", shortcut: "Left", symbol: "chevron.left")
                }
                .buttonStyle(TransportButtonStyle(tint: .gray))
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!store.canMoveToPreviousSegment)

                Button(action: store.handleNextSegment) {
                    transportLabel("Next Segment", shortcut: "Right", symbol: "chevron.right")
                }
                .buttonStyle(TransportButtonStyle(tint: .gray))
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!store.canMoveToNextSegment)

                Toggle(isOn: Binding(
                    get: { store.isEmergencyScrolling },
                    set: { _ in store.handleEmergencyScroll() }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Emergency Scroll", systemImage: store.isEmergencyScrolling ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Escape")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .red))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .panelBackground()
    }

    private var jumpListsColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            bookmarkPanel(title: "Section Jump List", bookmarks: store.sectionBookmarks, emptyText: "No section bookmarks loaded.")
            bookmarkPanel(title: "Q&A Jump List", bookmarks: store.questionBookmarks, emptyText: "No Q&A bookmarks loaded.")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            syncPanel
            recoveryPanel
            microphonePanel
        }
        .frame(maxWidth: 410, alignment: .topLeading)
    }

    private func bookmarkPanel(title: String, bookmarks: [AppSessionStore.ControlBookmarkSummary], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, detail: "\(bookmarks.count) targets")

            if bookmarks.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                store.jumpToBookmark(bookmark)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                        Text("Segment \(bookmark.segmentIndex + 1)" + (bookmark.slideIndex.map { " • Slide \($0)" } ?? ""))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(0.62))
                                    }

                                    Spacer(minLength: 10)

                                    if store.isCurrentBookmark(bookmark) {
                                        Text("LIVE")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Color(red: 0.97, green: 0.80, blue: 0.25), in: Capsule())
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(bookmarkBackground(for: bookmark), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 210, maxHeight: 290)
            }
        }
        .padding(18)
        .panelBackground()
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Sync Status", detail: "Confirmed stream drives the operator view.")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Confidence")
                    Spacer()
                    Text("\(Int((store.alignmentConfidence * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(syncConfidenceColor.gradient)
                            .frame(width: max(18, proxy.size.width * store.alignmentConfidence))
                    }
                }
                .frame(height: 12)
            }

            previewCard(title: "Current Segment", text: store.currentSegmentPreview)
            previewCard(title: "Next Segment", text: store.nextSegmentPreview.isEmpty ? "No upcoming segment." : store.nextSegmentPreview)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    metricPill(title: "Mic", value: store.selectedAudioInputName)
                    metricPill(title: "Model", value: store.activeModelID)
                }
                GridRow {
                    metricPill(title: "Hypothesis", value: latencyString(store.latencySnapshot.latestHypothesisLatencySeconds))
                    metricPill(title: "Confirmed", value: latencyString(store.latencySnapshot.latestConfirmedLatencySeconds))
                }
            }
        }
        .padding(18)
        .panelBackground()
    }

    private var microphonePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Mic Selector", detail: "Input changes write directly into AppSessionStore.")

            Picker("Audio Input", selection: Binding(
                get: { store.selectedAudioInputID ?? "__default__" },
                set: { selection in
                    let selectedID = selection == "__default__" ? nil : selection
                    Task {
                        await store.selectMicrophone(id: selectedID)
                    }
                }
            )) {
                Text("System Default").tag("__default__")
                ForEach(store.availableAudioInputs) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Refresh Devices") {
                    Task {
                        await store.refreshAudioInputs()
                    }
                }
                .buttonStyle(.bordered)

                Button("Start ASR") {
                    Task {
                        await store.startASR()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Current input: \(store.selectedAudioInputName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .padding(18)
        .panelBackground()
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Readiness Gate", detail: "Every blocking preflight check must pass before the session can start.")

            HStack(alignment: .center, spacing: 10) {
                Button(isRunningPreflight ? "Running…" : "Run Preflight") {
                    isRunningPreflight = true
                    Task {
                        await store.runPreflight()
                        await MainActor.run {
                            isRunningPreflight = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningPreflight)

                Button("Start") {
                    store.handlePlayPause()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canStartSession)

                Button("Reload Script") {
                    store.reloadReferenceBundle()
                }
                .buttonStyle(.bordered)

                Button("Reset") {
                    store.resetToIdle()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 16)

                Text(store.canStartSession ? "Ready" : "Blocked")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.canStartSession ? Color.green : Color.orange)
            }

            Text("Mic prompt: \(SessionConfiguration.microphonePrompt)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))

            VStack(spacing: 10) {
                ForEach(store.preflightResults, id: \.checkID) { result in
                    preflightRow(result)
                }
            }

            if let reportURL = store.lastPreflightReportURL {
                Text("Report saved to \(reportURL.path)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(18)
        .panelBackground()
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Recovery", detail: "Optional cloud recovery arms below 0.55 confidence for 30 seconds and allows one retry.")

            Toggle(isOn: Binding(
                get: { store.isCloudRecoveryEnabled },
                set: { store.setCloudRecoveryEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Groq Cloud Recovery")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(store.isGroqAPIKeyConfigured ? "GROQ_API_KEY detected." : "Missing GROQ_API_KEY or .env fallback.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .mint))

            previewCard(title: "Cloud Status", text: store.lastCloudRecoveryDetail)
        }
        .padding(18)
        .panelBackground()
    }

    private func preflightRow(_ result: PreflightResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preflightIcon(for: result.status))
                .foregroundStyle(preflightColor(for: result.status))
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(result.checkName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(result.status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(preflightColor(for: result.status))
                }

                Text(result.detail.isEmpty ? "Pending." : result.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Spacer(minLength: 12)

            Button(rerunningChecks.contains(result.checkID) ? "Running…" : "Re-run") {
                rerunningChecks.insert(result.checkID)
                Task {
                    await store.rerunPreflightCheck(preflightKind(for: result))
                    await MainActor.run {
                        _ = rerunningChecks.remove(result.checkID)
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(rerunningChecks.contains(result.checkID))
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func previewCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.48))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func topMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 150, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
        }
    }

    private func transportLabel(_ title: String, shortcut: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(shortcut)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func bookmarkBackground(for bookmark: AppSessionStore.ControlBookmarkSummary) -> some ShapeStyle {
        if store.isCurrentBookmark(bookmark) {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.17, green: 0.39, blue: 0.65),
                        Color(red: 0.11, green: 0.27, blue: 0.47),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(0.05))
    }

    private var timerMetricCard: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            topMetricCard(title: "Timer", value: formatTimer(at: context.date))
        }
    }

    private func formatTimer(at date: Date) -> String {
        if store.sessionState == .countdown, let countdownTarget = store.countdownTargetDate {
            return "T-\(max(0, Int(countdownTarget.timeIntervalSince(date).rounded(.up))))"
        }

        guard let startedAt = store.sessionStartedAt else {
            return "00:00"
        }

        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func latencyString(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.2fs", seconds)
    }

    private var stateBadgeColor: Color {
        switch store.sessionState {
        case .idle:
            return .gray
        case .preflight:
            return .orange
        case .ready:
            return .green
        case .countdown:
            return .yellow
        case .liveAuto:
            return .blue
        case .liveFrozen:
            return .indigo
        case .manualScroll:
            return .red
        case .recoveringLocal:
            return .mint
        case .recoveringCloud:
            return .purple
        case .error:
            return .red
        }
    }

    private var syncConfidenceColor: Color {
        switch store.alignmentConfidence {
        case ..<0.35:
            return .red
        case ..<0.7:
            return .orange
        default:
            return .green
        }
    }

    private func preflightColor(for status: PreflightCheckStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .running:
            return .orange
        case .pass:
            return .green
        case .fail:
            return .red
        }
    }

    private func preflightIcon(for status: PreflightCheckStatus) -> String {
        switch status {
        case .pending:
            return "circle.dashed"
        case .running:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .pass:
            return "checkmark.circle.fill"
        case .fail:
            return "xmark.octagon.fill"
        }
    }

    private func preflightKind(for result: PreflightResult) -> PreflightCheckKind {
        PreflightCheckKind(rawValue: result.checkID) ?? .bundleLoaded
    }
}

private extension View {
    func panelBackground() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.20))
        )
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 0.95))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
