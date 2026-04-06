import SwiftUI
import UIKit

// MARK: - Haptic Feedback
/// Lightweight haptic manager for tactile feedback on key interactions.
/// Uses pre-prepared generators for minimal latency.
enum Haptic {
    /// Light tap — Quick Log card open, picker changes
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// Medium tap — record saved, timer started
    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }

    /// Success notification — record saved / timer ended
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// Warning notification — delete confirmation shown
    static func warning() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }

    /// Error notification — save failed
    static func error() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.error)
    }

    /// Selection tick — segment changes, date pills, filter chips
    static func selection() {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        g.selectionChanged()
    }
}

// MARK: - Brand Colors
extension Color {
    // Primary – warm coral
    static let blPrimary      = Color(hex: "#FF7B6B")
    static let blPrimaryLight = Color(hex: "#FFB8B0")
    static let blPrimaryDark  = Color(hex: "#E55B4A")

    // Secondary – calm teal
    static let blTeal         = Color(hex: "#7EC8C8")
    static let blTealLight    = Color(hex: "#C2E8E8")

    // Activity semantic colors
    static let blFeeding      = Color(hex: "#4BAEE8")  // sky blue
    static let blSleep        = Color(hex: "#9B8EC4")  // lavender
    static let blDiaper       = Color(hex: "#55C189")  // mint
    static let blGrowth       = Color(hex: "#F5A623")  // amber
    static let blHealth       = Color(hex: "#E8788C")  // rose

    // Backgrounds
    static let blBackground   = Color(hex: "#FFF9F5")
    static let blSurface      = Color(hex: "#F5F0EB")
    static let blCard         = Color.white

    // Text
    static let blTextPrimary   = Color(hex: "#2C2C2E")
    static let blTextSecondary = Color(hex: "#8E8E93")
    static let blTextTertiary  = Color(hex: "#AEAEB2")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
        default: (a,r,g,b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r)/255,
                  green: Double(g)/255,
                  blue: Double(b)/255,
                  opacity: Double(a)/255)
    }
}

// MARK: - Card Modifier
struct BLCard: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Color.blCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}
extension View {
    func blCard(_ radius: CGFloat = 16) -> some View { modifier(BLCard(radius: radius)) }
}

// MARK: - Primary Button
struct BLPrimaryButton: ButtonStyle {
    var color: Color = .blPrimary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Quick Log Card
struct QuickLogCard: View {
    let icon: String
    let label: String
    let color: Color
    /// Optional contextual hint shown below the label (e.g. "2h ago", "Next: Right")
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.light()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                    .multilineTextAlignment(.center)
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .blCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(label)")
        .accessibilityHint("Double tap to record a new \(label.lowercased()) entry")
    }
}

// MARK: - Section Header
struct BLSectionHeader: View {
    let title: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.blTextPrimary)
            Spacer()
            if let action, let onTap {
                Button(action: onTap) {
                    Text(action)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blPrimary)
                }
            }
        }
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    var subtitle: String? = nil
    /// Shows how long since the last event (e.g. "1h 23m ago")
    var timeSince: String? = nil

    private var accessibilityText: String {
        var parts = ["\(value) \(label)"]
        if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let timeSince, !timeSince.isEmpty { parts.append(timeSince) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blTextSecondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            if let timeSince, !timeSince.isEmpty {
                Text(timeSince)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blTextTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .blCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Toast Notification
struct BLToastOverlay: ViewModifier {
    @EnvironmentObject var appState: AppState

    private var accentColor: Color {
        appState.toastColor ?? .blPrimary
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = appState.toastMessage {
                HStack(spacing: 10) {
                    if let icon = appState.toastIcon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

extension View {
    func blToastOverlay() -> some View {
        modifier(BLToastOverlay())
    }
}

// MARK: - Baby Avatar (reusable photo / fallback emoji)
struct BabyAvatarView: View {
    let baby: Baby
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let photoData = baby.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(hex: baby.gender.color).opacity(0.3), lineWidth: size > 60 ? 2 : 1.5)
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(Color(hex: baby.gender.color).opacity(0.2))
                        .frame(width: size, height: size)
                    Text(baby.gender.icon)
                        .font(.system(size: size * 0.5))
                }
            }
        }
        .accessibilityLabel("\(baby.name)'s photo")
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - Cached DateFormatters
/// DateFormatter is extremely expensive to allocate (~30× costlier than String formatting).
/// These cached instances are shared across the app for hot-path date formatting.
enum BLDateFormatters {
    /// "Today", "Yesterday" with relative formatting (short date, no time)
    static let relativeShort: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// "Today", "Yesterday" with relative formatting (medium date, no time)
    static let relativeMedium: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "Today", "Yesterday" with relative formatting (full date, no time)
    static let relativeFull: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    /// "Apr 3", "Jan 12" — short month + day
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// "Monday, Apr 3" — full weekday + month + day
    static let fullWeekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    /// "Mon", "Tue" — abbreviated weekday, uppercased by caller
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    /// "6", "14" — day number only
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d")
        return f
    }()

    /// "4/3", "1/12" — short month/day for chart axis labels
    static let monthDayCompact: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    /// "2026-04-06" — ISO-style for filenames
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Flow Layout (for wrapping chips/tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
