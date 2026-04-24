import SwiftUI

/// Left-hand sidebar in the document workspace. Shows category toggles at
/// the top and a grouped list of detected entities below. Clicking an entity
/// focuses the PDF canvas on it.
struct EntitySidebar: View {
    @EnvironmentObject private var controller: DocumentController
    @Binding var focusedSpan: PageSpan?
    @State private var collapsedCategories: Set<Design.Category> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HairlineDivider()
            categoryToggles
            HairlineDivider()
            entityList
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Design.sidebarSurface)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Detections")
                .font(Design.Font.title)
            Spacer()
            if controller.spans.totalCount > 0 {
                Text("\(controller.spans.totalCount)")
                    .font(Design.Font.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.top, Design.Space.lg)
        .padding(.bottom, Design.Space.sm)
    }

    // MARK: - Category toggles

    private var categoryToggles: some View {
        let counts = controller.spans.categoryCounts()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Space.xs) {
                ForEach(Design.Category.displayOrder, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        count: counts.first(where: { $0.category == category })?.count ?? 0,
                        isEnabled: controller.enabledCategories.contains(category)
                    ) {
                        controller.toggle(category: category)
                    }
                }
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.vertical, Design.Space.sm)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Entity list

    @ViewBuilder
    private var entityList: some View {
        let all = controller.spans.all
        if all.isEmpty {
            emptyPlaceholder
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Design.Category.displayOrder, id: \.self) { category in
                        let inCategory = all.filter { $0.category == category }
                        if !inCategory.isEmpty {
                            let isCollapsed = collapsedCategories.contains(category)
                            Section {
                                if !isCollapsed {
                                    ForEach(inCategory) { span in
                                        EntityRow(
                                            span: span,
                                            isFocused: focusedSpan?.id == span.id,
                                            isEnabled: controller.enabledCategories.contains(category)
                                        ) {
                                            focusedSpan = span
                                        }
                                    }
                                }
                            } header: {
                                SectionHeader(
                                    category: category,
                                    count: inCategory.count,
                                    isCollapsed: isCollapsed
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if isCollapsed {
                                            collapsedCategories.remove(category)
                                        } else {
                                            collapsedCategories.insert(category)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, Design.Space.md)
            }
        }
    }

    @ViewBuilder
    private var emptyPlaceholder: some View {
        VStack(spacing: Design.Space.xs) {
            if case .running = controller.detectState {
                ProgressView().controlSize(.small)
                Text("Scanning document…")
                    .font(Design.Font.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let m) = controller.detectState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(m)
                    .font(Design.Font.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("No PII detected")
                    .font(Design.Font.captionStrong)
                    .foregroundStyle(.secondary)
                Text("This document appears clean.")
                    .font(Design.Font.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(Design.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Chip

private struct CategoryChip: View {
    let category: Design.Category
    let count: Int
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(category.title)
                    .font(Design.Font.captionStrong)
                if count > 0 {
                    Text("\(count)")
                        .font(Design.Font.captionStrong)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(isEnabled ? 0.35 : 0.0)))
                }
            }
            .foregroundStyle(chipForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(chipBackground)
            )
            .overlay(
                Capsule().strokeBorder(chipBorder, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .opacity(count == 0 ? 0.35 : 1)
        .disabled(count == 0)
        .help(isEnabled ? "Disable \(category.title.lowercased())" : "Enable \(category.title.lowercased())")
    }

    private var chipForeground: Color {
        isEnabled ? .white : category.color
    }
    private var chipBackground: Color {
        isEnabled ? category.color : category.color.opacity(0.12)
    }
    private var chipBorder: Color {
        isEnabled ? category.color : category.color.opacity(0.35)
    }
}

// MARK: - Section header + row

private struct SectionHeader: View {
    let category: Design.Category
    let count: Int
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(category.color)
                Text(category.title.uppercased())
                    .font(Design.Font.captionStrong)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(Design.Font.monoSmall)
                    .foregroundStyle(.secondary.opacity(0.7))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.top, Design.Space.md)
            .padding(.bottom, Design.Space.xxs)
            .background(Design.sidebarSurface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand \(category.title.lowercased())" : "Collapse \(category.title.lowercased())")
    }
}

private struct EntityRow: View {
    let span: PageSpan
    let isFocused: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(span.category.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(span.text)
                        .font(Design.Font.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text("Page \(span.pageIndex + 1)")
                        .font(Design.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.vertical, Design.Space.xs)
            .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
