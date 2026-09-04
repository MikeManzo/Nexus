import SwiftUI

/// The landing zone's content: a small pill showing the active desktop, which grows in place —
/// same window, same view, no travel distance — to reveal the tile grid on hover. Collapses back
/// after a short debounce once the cursor truly leaves (the *current*, possibly-expanded) bounds.
struct LandingZoneView: View {
    let coordinator: AppCoordinator
    var onSizeChange: () -> Void

    @State private var isExpanded = false
    @State private var collapseWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pill
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            if isExpanded {
                grid
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
            }
        }
        // Collapsed height (pill + tight padding) lands close to the menu bar's own thickness,
        // so it reads as occupying the menu bar row rather than floating below it.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: isExpanded ? 16 : 10))
        .onHover { hovering in
            if hovering {
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                isExpanded = true
            } else {
                let item = DispatchWorkItem { isExpanded = false }
                collapseWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
            }
        }
        .onChange(of: isExpanded) { _, _ in onSizeChange() }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if let active = coordinator.activeSpace {
                Circle().fill(active.accentColor).frame(width: 7, height: 7)
                Text(active.displayName).font(.subheadline.weight(.semibold))
            } else {
                Text("Nexus").font(.subheadline.weight(.semibold))
            }
        }
        .frame(minWidth: 90)
    }

    private var grid: some View {
        Group {
            if coordinator.spaces.isEmpty {
                Text(coordinator.accessibilityPermission.isTrusted ? "No desktops found yet." : "Grant Accessibility access in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 66), spacing: 10)], spacing: 12) {
                    ForEach(coordinator.spaces) { space in
                        DesktopTile(space: space, isBusy: coordinator.isBusy) {
                            Task { await coordinator.activate(space) }
                        }
                    }
                }
                .frame(width: 260)
            }
        }
    }
}
