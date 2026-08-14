import SwiftUI

struct NewGroupSheet: View {
    @Binding var name: String
    let message: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Group")
                .font(.title2.weight(.semibold))

            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createIfPossible)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: createIfPossible)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(.horizontal, AppGeometry.windowEdgeControlInset)
        .padding(.top, AppGeometry.windowContentInset)
        .padding(.bottom, AppGeometry.windowEdgeControlInset)
        .frame(width: 420)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createIfPossible() {
        guard !trimmedName.isEmpty else { return }
        onCreate()
    }
}
