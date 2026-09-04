import SwiftUI

struct OnboardingView: View {
    let coordinator: AppCoordinator
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Welcome to Nexus").font(.largeTitle.bold())
                Text("Your desktops, on demand.").font(.title3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                bullet("rectangle.3.group", "See and switch between all your desktops from the menu bar")
                bullet("plus.square", "Create, rename, and delete desktops in seconds")
                bullet("keyboard", "Global keyboard shortcuts work from any app")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility access").font(.headline)
                Text("Switching, creating, and deleting desktops needs Accessibility access — it's the only way an app can control Mission Control, since macOS has no dedicated API for it. Nexus does not log keystrokes or read other apps' content. Renaming and the rest of the app work without this permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.accessibilityPermission.isTrusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(coordinator.accessibilityPermission.isTrusted ? "Access granted" : "Access not granted")
                        .font(.subheadline)
                }

                if !coordinator.accessibilityPermission.isTrusted {
                    HStack {
                        Button("Grant Access…") {
                            coordinator.accessibilityPermission.requestPermission()
                        }
                        Button("Open System Settings…") {
                            coordinator.accessibilityPermission.openSystemSettings()
                        }
                        Button("Recheck") {
                            coordinator.accessibilityPermission.refresh()
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Button("Skip for Now") { onFinish() }
                Spacer()
                Button(coordinator.accessibilityPermission.isTrusted ? "Get Started" : "Continue") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480, height: 540)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
    }
}
