import SwiftUI

/// The full desktop-management window: rename, delete, create, and (via double-click) switch.
struct SpaceManagerView: View {
    let coordinator: AppCoordinator

    @State private var renamingSpace: DesktopSpace?
    @State private var renameText = ""
    @State private var pendingDeletion: DesktopSpace?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            List {
                ForEach(coordinator.spaces) { space in
                    row(for: space)
                }
            }
            .listStyle(.inset)
            .disabled(coordinator.isBusy)
            Divider()
            HStack {
                Button {
                    Task { await coordinator.createSpace() }
                } label: {
                    Label("Create Desktop", systemImage: "plus")
                }
                .disabled(coordinator.isBusy)
                if coordinator.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 420, minHeight: 480)
        .task { await coordinator.refresh() }
        .sheet(item: $renamingSpace) { space in
            renameSheet(for: space)
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.displayName ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in if !isPresented { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let space = pendingDeletion {
                    Task { await coordinator.delete(space) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
        .alert(item: errorBinding) { error in
            Alert(title: Text("Nexus"), message: Text(error.errorDescription ?? "Something went wrong."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Desktops").font(.title2.bold())
            Text("\(coordinator.spaces.count) desktops")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }

    private func row(for space: DesktopSpace) -> some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                .background(Circle().fill(space.isActive ? Color.accentColor : .clear))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayName).font(.body.weight(.medium))
                Text("Desktop \(space.order + 1)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Rename") {
                renameText = space.customName ?? ""
                renamingSpace = space
            }
            .buttonStyle(.link)
            .accessibilityLabel("Rename \(space.displayName)")

            Button("Delete") {
                pendingDeletion = space
            }
            .buttonStyle(.link)
            .foregroundStyle(.red)
            .disabled(coordinator.spaces.count <= 1)
            .accessibilityLabel("Delete \(space.displayName)")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(space.isActive ? "\(space.displayName), current desktop" : space.displayName)
        .accessibilityHint("Double-click to switch to this desktop")
        .onTapGesture(count: 2) {
            guard !coordinator.isBusy else { return }
            Task { await coordinator.activate(space) }
        }
    }

    private func renameSheet(for space: DesktopSpace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Desktop").font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(for: space) }
            HStack {
                Spacer()
                Button("Cancel") { renamingSpace = nil }
                Button("Save") { commitRename(for: space) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func commitRename(for space: DesktopSpace) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await coordinator.rename(space, to: name) }
        renamingSpace = nil
    }

    private var errorBinding: Binding<SpaceError?> {
        Binding(get: { coordinator.lastError }, set: { coordinator.lastError = $0 })
    }
}
