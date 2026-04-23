import SwiftUI

/// Shared visual tokens for the redactor UI. Every screen and control should
/// read from here — the accent palette drives category colors, span highlights,
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
    }

    // MARK: - Typography

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .default)
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold, design: .default)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let callout = SwiftUI.Font.system(size: 12, weight: .regular, design: .default)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .medium, design: .default)
        static let monoSmall = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
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

    static let surface = Color(NSColor.controlBackgroundColor)
    static let sidebarSurface = Color(NSColor.underPageBackgroundColor)
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
