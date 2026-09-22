import SwiftUI

struct ArrangementProgressBanner: View {
    let progress: ArrangementProgress
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(progress.title)
            VStack(alignment: .leading, spacing: 5) {
                Text(progress.title).font(.headline)
                Text("Your current score stays safe. Editing resumes automatically when the draft is ready.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Cancel", action: cancel)
                .help("Stop arranging without changing the current score")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.09))
        .accessibilityIdentifier("arrangement-progress")
    }
}
