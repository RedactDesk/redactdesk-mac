import SwiftUI

/// Shared visual tokens for the redactor UI. Every screen and control should
/// read from here - the accent palette drives category colors, span highlights,
/// and paywall gradients later.
enum Design {
    // MARK: - Spacing (8pt grid)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let pill: CGFloat = 999
    }

    // MARK: - Typography
    //
    // The marketing design pairs Inter (sans) with Poly (serif) for display
    // headings. On macOS we use the system sans + the system serif (New York)
    // via `design: .serif` - keeps the app font-free and renders in the same
    // editorial register as Poly without bundling webfonts.

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .default)
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold, design: .default)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let callout = SwiftUI.Font.system(size: 12, weight: .regular, design: .default)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .medium, design: .default)
        static let monoSmall = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)

        /// Editorial serif headline - used on the welcome sheet and post-export
        /// attribution card to match the Poly usage on elephas.app.
        static let serifDisplay = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)
        static let serifTitle = SwiftUI.Font.system(size: 22, weight: .semibold, design: .serif)

        /// All-caps pill label used on the "N REDACTIONS" badge in the design.
        static let pillLabel = SwiftUI.Font.system(size: 11, weight: .bold, design: .default)
    }

    // MARK: - Brand palette (Elephas indigo)
    //
    // Tokens mirror the `:root` block in SafePaste.html. Hex values copied
    // verbatim so the macOS app matches the marketing site visually.

    enum Brand {
        static let primary         = Color(hex: 0x6366F1)   // indigo-500
        static let primaryHover    = Color(hex: 0x4F46E5)   // indigo-600
        static let primaryPress    = Color(hex: 0x4338CA)   // indigo-700
        static let primaryTint     = Color(hex: 0x6366F1).opacity(0.10)
        static let primaryRing     = Color(hex: 0x6366F1).opacity(0.20)

        static let purpleDeep      = Color(hex: 0x160041)
        static let purpleMid       = Color(hex: 0x2C1854)

        /// Indigo → violet gradient used on the brand icon tile and progress bars.
        static let gradient = LinearGradient(
            colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Semantic palette

    enum Palette {
        // Foreground (slate/gray ramp)
        static let fg        = Color(hex: 0x111827)   // gray-900
        static let fgStrong  = Color(hex: 0x0F172A)   // slate-900
        static let fgMuted   = Color(hex: 0x374151)   // gray-700
        static let fgSubtle  = Color(hex: 0x6B7280)   // gray-500
        static let fgFaint   = Color(hex: 0x9CA3AF)   // gray-400

        // Backgrounds
        static let bg        = Color(hex: 0xFFFFFF)
        static let bgSoft    = Color(hex: 0xF9FAFB)   // gray-50
        static let bgMuted   = Color(hex: 0xF3F4F6)   // gray-100
        static let bgSection = Color(hex: 0xF8FAFC)   // slate-50

        // Borders
        static let border       = Color(hex: 0xE5E7EB)
        static let borderStrong = Color(hex: 0xD1D5DB)
        static let borderSoft   = Color(hex: 0xF3F4F6)

        // Semantic
        static let success      = Color(hex: 0x10B981)
        static let successText  = Color(hex: 0x059669)
        static let successTint  = Color(hex: 0xECFDF5)
        static let danger       = Color(hex: 0xEF4444)
        static let dangerTint   = Color(hex: 0xFEF2F2)
    }

    // MARK: - Category palette

    enum Category {
        case person, email, phone, address, date, url, account, secret, other

        init(label: String) {
            switch label {
            case "private_person": self = .person
            case "private_email": self = .email
            case "private_phone": self = .phone
            case "private_address": self = .address
            case "private_date": self = .date
            case "private_url": self = .url
            case "account_number": self = .account
            case "secret": self = .secret
            default: self = .other
            }
        }

        var color: Color {
            switch self {
            case .person: Color(red: 0.36, green: 0.50, blue: 0.95)
            case .email: Color(red: 0.17, green: 0.68, blue: 0.72)
            case .phone: Color(red: 0.28, green: 0.74, blue: 0.58)
            case .address: Color(red: 0.44, green: 0.40, blue: 0.85)
            case .date: Color(red: 0.63, green: 0.40, blue: 0.85)
            case .url: Color(red: 0.22, green: 0.62, blue: 0.86)
            case .account: Color(red: 0.95, green: 0.62, blue: 0.30)
            case .secret: Color(red: 0.90, green: 0.38, blue: 0.38)
            case .other: Color.gray
            }
        }

        var title: String {
            switch self {
            case .person: "People"
            case .email: "Emails"
            case .phone: "Phone numbers"
            case .address: "Addresses"
            case .date: "Dates"
            case .url: "URLs"
            case .account: "Account numbers"
            case .secret: "Secrets"
            case .other: "Other"
            }
        }

        var icon: String {
            switch self {
            case .person: "person.fill"
            case .email: "envelope.fill"
            case .phone: "phone.fill"
            case .address: "mappin.and.ellipse"
            case .date: "calendar"
            case .url: "link"
            case .account: "creditcard.fill"
            case .secret: "key.fill"
            case .other: "questionmark.circle"
            }
        }

        /// Order in which categories appear in sidebar chips & lists.
        static let displayOrder: [Category] = [
            .person, .email, .phone, .address, .date, .url, .account, .secret, .other
        ]

        /// Raw label values grouped under this category (matches model output).
        var rawLabels: [String] {
            switch self {
            case .person: ["private_person"]
            case .email: ["private_email"]
            case .phone: ["private_phone"]
            case .address: ["private_address"]
            case .date: ["private_date"]
            case .url: ["private_url"]
            case .account: ["account_number"]
            case .secret: ["secret"]
            case .other: []
            }
        }
    }

    // MARK: - Surfaces
    //
    // `underPageBackgroundColor` is the medium-gray macOS uses behind document
    // pages in Preview. It reads as dim next to a bright canvas, so the
    // sidebar and split-view backdrops use the palette's slate-50 instead.

    static let surface = Color(NSColor.controlBackgroundColor)
    static let sidebarSurface = Palette.bgSoft        // #F9FAFB
    static let workspaceSurface = Palette.bgSection   // #F8FAFC
    static let separator = Color(NSColor.separatorColor)
    static let dropHighlight = Color.accentColor.opacity(0.15)
}

// MARK: - Reusable view modifiers

extension View {
    /// Applies a lightly bordered card surface with rounded corners.
    func cardSurface(
        padding: CGFloat = Design.Space.md,
        radius: CGFloat = Design.Radius.md
    ) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Design.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Design.separator.opacity(0.5), lineWidth: 0.5)
            )
    }
}

/// A thin spacer with a background blend used between header rows.
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Design.separator.opacity(0.5))
            .frame(height: 0.5)
    }
}

// MARK: - Color hex init

extension Color {
    /// Builds a `Color` from a 0xRRGGBB literal (design-token ergonomics).
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Pill button style

/// Primary indigo pill CTA - matches the elephas.app `.btn-brand` style.
struct BrandPillButtonStyle: ButtonStyle {
    enum Size { case regular, large }
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        let hPad: CGFloat = size == .large ? 28 : 20
        let vPad: CGFloat = size == .large ? 12 : 9
        let fontSize: CGFloat = size == .large ? 15 : 13
        return configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Design.Brand.primaryPress : Design.Brand.primary)
            )
            .shadow(color: Design.Brand.primary.opacity(configuration.isPressed ? 0.12 : 0.25),
                    radius: configuration.isPressed ? 4 : 10,
                    y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary outlined pill - used as "Keep using SafePaste" / "Not now".
struct GhostPillButtonStyle: ButtonStyle {
    enum Size { case regular, large }
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        let hPad: CGFloat = size == .large ? 28 : 20
        let vPad: CGFloat = size == .large ? 12 : 9
        let fontSize: CGFloat = size == .large ? 15 : 13
        return configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Design.Palette.fg)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Design.Palette.bgMuted : Color.white)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Design.Palette.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Brand badge

/// Soft indigo-tinted pill used as the "N REDACTIONS" milestone badge and as
/// the section tag on the Welcome sheet.
struct BrandBadge: View {
    let leading: String?
    let label: String

    init(_ label: String, leading: String? = nil) {
        self.label = label
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 6) {
            if let leading {
                Text(leading)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Design.Brand.primary)
            }
            Text(label.uppercased())
                .font(Design.Font.pillLabel)
                .tracking(0.8)
                .foregroundStyle(Design.Brand.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(Design.Brand.primaryTint)
        )
    }
}

/// Soft check chip used on the milestone modals (e.g. "✓ Folder-wide redaction").
struct FeatureChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Design.Palette.successText)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Palette.fgMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(Color.white)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Design.Palette.border, lineWidth: 1)
        )
    }
}
