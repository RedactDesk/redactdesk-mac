import SwiftUI

/// Persistent footer strip shown at the bottom of the main window. Mirrors
/// the mock: "SafePaste · by the Elephas team · v1.0" on the left, "View
/// source" on the right. Tiny, muted, always-present -falls under the
/// "Attribution" layer in the intensity gradient (background, always on).
struct AttributionFooter: View {
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("SafePaste")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Palette.fgMuted)
                Text("·")
                    .foregroundStyle(Design.Palette.fgFaint)
                Text("by the ")
                    .foregroundStyle(Design.Palette.fgSubtle)
                +
                Text("Elephas")
                    .foregroundStyle(Design.Brand.primary)
                +
                Text(" team")
                    .foregroundStyle(Design.Palette.fgSubtle)
                Text("·")
                    .foregroundStyle(Design.Palette.fgFaint)
                Text(versionString)
                    .foregroundStyle(Design.Palette.fgFaint)
            }
            .font(.system(size: 11))
            .onTapGesture {
                NSWorkspace.shared.open(ElephasLinks.landing(.footer))
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(ElephasLinks.repoURL)
            } label: {
                Text("View source")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Palette.fgSubtle)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(Design.Palette.bgSoft)
                .overlay(Rectangle().fill(Design.Palette.border).frame(height: 0.5), alignment: .top)
        )
    }
}
