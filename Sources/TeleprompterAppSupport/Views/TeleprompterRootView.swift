import AppKit
import SwiftUI

public struct TeleprompterRootView: View {
    @ObservedObject private var store: AppSessionStore
    @State private var emergencyScrollTask: Task<Void, Never>?

    public init(store: AppSessionStore) {
        self.store = store
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack {
                    teleprompterBackground
                        .ignoresSafeArea()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.045) {
                            statusHeader

                            if let previous = store.previousTeleprompterSegment {
                                segmentColumn(previous, role: .previous)
                            }

                            if let active = store.activeTeleprompterSegment {
                                segmentColumn(active, role: .active)
                                    .id(active.id)
                            }

                            ForEach(store.upcomingTeleprompterSegments) { segment in
                                segmentColumn(segment, role: .upcoming)
                            }

                            emergencyScrollFooter
                        }
                        .padding(.horizontal, max(geometry.size.width * 0.08, 72))
                        .padding(.vertical, max(geometry.size.height * 0.08, 56))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(x: store.isMirrorModeEnabled ? -1 : 1, y: 1, anchor: .center)
                }
                .overlay(alignment: .topTrailing) {
                    transportHUD
                        .padding(.top, 28)
                        .padding(.trailing, 32)
                }
                .background(
                    TeleprompterKeyboardBridge(
                        onSpace: { store.handleTogglePause() },
                        onPrevious: { store.handlePreviousSegment() },
                        onNext: { store.handleNextSegment() },
                        onMirrorToggle: { store.toggleMirrorMode() },
                        onIncreaseFont: { store.increaseTeleprompterFontSize() },
                        onDecreaseFont: { store.decreaseTeleprompterFontSize() },
                        onEmergencyScroll: { store.handleEmergencyScroll() }
                    )
                )
                .onAppear {
                    scrollToActiveSegment(with: proxy, animated: false)
                    syncEmergencyScrollLoop()
                }
                .onChange(of: store.currentSegmentIndex) { _, _ in
                    scrollToActiveSegment(with: proxy, animated: true)
                }
                .onChange(of: store.isEmergencyScrolling) { _, _ in
                    syncEmergencyScrollLoop()
                }
                .onDisappear {
                    emergencyScrollTask?.cancel()
                    emergencyScrollTask = nil
                }
            }
        }
        .frame(minWidth: 1280, minHeight: 720)
    }

    private var teleprompterBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.03, blue: 0.05),
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                    Color(red: 0.09, green: 0.12, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.97, green: 0.78, blue: 0.34).opacity(0.08))
                .frame(width: 520, height: 520)
                .blur(radius: 40)
                .offset(x: 320, y: -260)

            Circle()
                .fill(Color(red: 0.32, green: 0.67, blue: 0.95).opacity(0.1))
                .frame(width: 420, height: 420)
                .blur(radius: 28)
                .offset(x: -360, y: 240)
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                stateBadge
                Text(store.slideCounter)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("\(store.teleprompterCurrentSegmentNumber)/\(store.teleprompterSegmentCount)")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.activeSegmentTitle)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.79, blue: 0.39))
                Text(store.statusDetail)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(2)
            }
        }
    }

    private var transportHUD: some View {
        VStack(alignment: .trailing, spacing: 10) {
            hudPill(title: store.isMirrorModeEnabled ? "Mirror" : "Direct", value: store.isMirrorModeEnabled ? "MIRROR" : "LIVE")
            hudPill(title: "Font", value: "\(Int(store.teleprompterFontSize)) pt")
            hudPill(title: "Scroll", value: store.isEmergencyScrolling ? "FIXED \(Int(store.emergencyScrollWordsPerMinute)) WPM" : "ALIGNER")
        }
    }

    private var emergencyScrollFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            Text(store.isEmergencyScrolling ? "Emergency scroll is driving the prompt at a fixed pace." : "Keyboard: Space pause, Up/Down navigate, M mirror, +/- font, Escape fixed scroll.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(.top, 16)
    }

    private var stateBadge: some View {
        Text(store.sessionState.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).uppercased())
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .tracking(1.1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(stateBadgeColor.opacity(0.2))
            .foregroundStyle(stateBadgeColor)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(stateBadgeColor.opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
    }

    private var stateBadgeColor: Color {
        switch store.sessionState {
        case .idle, .preflight, .ready:
            return Color(red: 0.62, green: 0.75, blue: 0.92)
        case .countdown, .recoveringLocal, .recoveringCloud:
            return Color(red: 0.97, green: 0.77, blue: 0.35)
        case .liveAuto:
            return Color(red: 0.43, green: 0.86, blue: 0.62)
        case .liveFrozen:
            return Color(red: 0.76, green: 0.81, blue: 0.88)
        case .manualScroll, .error:
            return Color(red: 0.98, green: 0.42, blue: 0.37)
        }
    }

    private func segmentColumn(_ segment: TeleprompterSegmentSnapshot, role: SegmentRole) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let marker = store.slideMarker(beforeSegmentIndex: segment.segmentIndex) {
                slideMarker(marker)
            }

            Text(segment.sectionTitle.uppercased())
                .font(.system(size: role.sectionFontSize, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(role.sectionColor)

            highlightedText(for: segment, role: role)
                .font(.system(size: role.fontSize(base: store.teleprompterFontSize), weight: role.weight, design: .rounded))
                .lineSpacing(role.lineSpacing)
                .foregroundStyle(role.foregroundColor)
                .multilineTextAlignment(.leading)

            if role == .active {
                progressRail
            }
        }
        .padding(.vertical, role.verticalPadding)
        .padding(.horizontal, role.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(role.background)
        .overlay(
            RoundedRectangle(cornerRadius: role.cornerRadius, style: .continuous)
                .strokeBorder(role.borderColor, lineWidth: role.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: role.cornerRadius, style: .continuous))
        .opacity(role.opacity)
    }

    private func slideMarker(_ marker: TeleprompterSlideSnapshot) -> some View {
        HStack(spacing: 12) {
            Text("▶ \(marker.label)")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.4))
            Text("Slide \(marker.index)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule(style: .continuous))
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Current")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text(String(format: "%.0f%%", store.teleprompterProgressFraction * 100))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.4))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.82, blue: 0.4),
                                    Color(red: 0.33, green: 0.74, blue: 0.97),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geometry.size.width * store.teleprompterProgressFraction, 24))
                }
            }
            .frame(height: 12)
        }
    }

    private func highlightedText(for segment: TeleprompterSegmentSnapshot, role: SegmentRole) -> Text {
        guard role == .active else {
            return Text(segment.text)
        }

        let terms = store.hypothesisHighlightTerms
        let components = segment.text.split(separator: " ", omittingEmptySubsequences: false)
        return components.enumerated().reduce(Text("")) { partial, entry in
            let word = String(entry.element)
            let normalizedWord = word
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            let isHighlighted = terms.contains(normalizedWord)
            let piece = Text(word + (entry.offset == components.indices.last ? "" : " "))
                .foregroundStyle(isHighlighted ? Color(red: 0.99, green: 0.84, blue: 0.46) : role.foregroundColor)
            return partial + piece
        }
    }

    private func hudPill(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.4))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.26))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scrollToActiveSegment(with proxy: ScrollViewProxy, animated: Bool) {
        guard let activeID = store.activeTeleprompterSegment?.id else { return }
        let animation = Animation.easeInOut(duration: store.isEmergencyScrolling ? 0.18 : 0.38)

        if animated {
            withAnimation(animation) {
                proxy.scrollTo(activeID, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeID, anchor: .center)
        }
    }

    private func syncEmergencyScrollLoop() {
        emergencyScrollTask?.cancel()
        emergencyScrollTask = nil

        guard store.isEmergencyScrolling else { return }

        emergencyScrollTask = Task { @MainActor in
            while !Task.isCancelled && store.isEmergencyScrolling {
                let duration = store.emergencyScrollSegmentDuration
                do {
                    try await Task.sleep(for: .seconds(duration))
                } catch {
                    return
                }

                guard store.isEmergencyScrolling else { return }
                store.handleNextSegment()
            }
        }
    }
}

private enum SegmentRole: Equatable {
    case previous
    case active
    case upcoming

    func fontSize(base: CGFloat) -> CGFloat {
        switch self {
        case .previous:
            return base * 0.7
        case .active:
            return base
        case .upcoming:
            return base * 0.8
        }
    }

    var sectionFontSize: CGFloat {
        switch self {
        case .previous:
            return 18
        case .active:
            return 20
        case .upcoming:
            return 18
        }
    }

    var weight: Font.Weight {
        switch self {
        case .previous:
            return .medium
        case .active:
            return .bold
        case .upcoming:
            return .semibold
        }
    }

    var foregroundColor: Color {
        switch self {
        case .previous:
            return Color.white.opacity(0.24)
        case .active:
            return Color.white
        case .upcoming:
            return Color.white.opacity(0.66)
        }
    }

    var sectionColor: Color {
        switch self {
        case .previous:
            return Color.white.opacity(0.18)
        case .active:
            return Color(red: 0.95, green: 0.79, blue: 0.39)
        case .upcoming:
            return Color.white.opacity(0.34)
        }
    }

    var background: Color {
        switch self {
        case .previous:
            return Color.white.opacity(0.02)
        case .active:
            return Color.white.opacity(0.06)
        case .upcoming:
            return Color.white.opacity(0.03)
        }
    }

    var borderColor: Color {
        switch self {
        case .previous:
            return Color.white.opacity(0.05)
        case .active:
            return Color(red: 0.98, green: 0.82, blue: 0.4).opacity(0.28)
        case .upcoming:
            return Color.white.opacity(0.06)
        }
    }

    var borderWidth: CGFloat {
        self == .active ? 1.5 : 1
    }

    var cornerRadius: CGFloat {
        self == .active ? 30 : 26
    }

    var opacity: Double {
        switch self {
        case .previous:
            return 0.82
        case .active:
            return 1
        case .upcoming:
            return 0.96
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .previous:
            return 16
        case .active:
            return 22
        case .upcoming:
            return 18
        }
    }

    var verticalPadding: CGFloat {
        self == .active ? 28 : 22
    }

    var horizontalPadding: CGFloat {
        self == .active ? 30 : 24
    }
}

private struct TeleprompterKeyboardBridge: NSViewRepresentable {
    let onSpace: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onMirrorToggle: () -> Void
    let onIncreaseFont: () -> Void
    let onDecreaseFont: () -> Void
    let onEmergencyScroll: () -> Void

    func makeNSView(context: Context) -> KeyboardCaptureView {
        let view = KeyboardCaptureView()
        view.onEvent = { event in
            switch event.keyCode {
            case 49:
                onSpace()
                return true
            case 126:
                onPrevious()
                return true
            case 125:
                onNext()
                return true
            case 53:
                onEmergencyScroll()
                return true
            case 46:
                onMirrorToggle()
                return true
            case 24:
                onIncreaseFont()
                return true
            case 27:
                onDecreaseFont()
                return true
            default:
                guard let key = event.charactersIgnoringModifiers?.lowercased() else {
                    return false
                }

                switch key {
                case "m":
                    onMirrorToggle()
                    return true
                case "+", "=":
                    onIncreaseFont()
                    return true
                case "-", "_":
                    onDecreaseFont()
                    return true
                default:
                    return false
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureView, context: Context) {
        nsView.onEvent = { event in
            switch event.keyCode {
            case 49:
                onSpace()
                return true
            case 126:
                onPrevious()
                return true
            case 125:
                onNext()
                return true
            case 53:
                onEmergencyScroll()
                return true
            case 46:
                onMirrorToggle()
                return true
            case 24:
                onIncreaseFont()
                return true
            case 27:
                onDecreaseFont()
                return true
            default:
                guard let key = event.charactersIgnoringModifiers?.lowercased() else {
                    return false
                }

                switch key {
                case "m":
                    onMirrorToggle()
                    return true
                case "+", "=":
                    onIncreaseFont()
                    return true
                case "-", "_":
                    onDecreaseFont()
                    return true
                default:
                    return false
                }
            }
        }
    }
}

@MainActor
private final class KeyboardCaptureView: NSView {
    var onEvent: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.onEvent?(event) == true ? nil : event
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }
}
