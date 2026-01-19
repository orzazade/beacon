import SwiftUI

/// Editor for VIP contacts list
struct VIPContactsEditor: View {
    @Binding var emails: [String]
    let onSave: () -> Void

    @State private var editText: String = ""
    @State private var newEmail: String = ""
    @State private var showingBulkEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VIP Contacts")
                        .font(.headline)

                    Text("Emails from these senders get priority boost (weight: 0.30)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showingBulkEditor.toggle() }) {
                    Image(systemName: showingBulkEditor ? "list.bullet" : "text.alignleft")
                }
                .help(showingBulkEditor ? "Switch to list view" : "Switch to bulk edit")
            }

            if showingBulkEditor {
                // Bulk text editor
                bulkEditorView
            } else {
                // Individual email list
                listEditorView
            }
        }
    }

    // MARK: - List Editor

    private var listEditorView: some View {
        VStack(spacing: 12) {
            // Add new email
            HStack {
                TextField("Add email address", text: $newEmail)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addEmail)

                Button(action: addEmail) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newEmail.isEmpty || !isValidEmail(newEmail))
            }

            // Email list
            if emails.isEmpty {
                Text("No VIP contacts configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(emails, id: \.self) { email in
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)

                                Text(email)
                                    .font(.system(size: 12, design: .monospaced))

                                Spacer()

                                Button(action: { removeEmail(email) }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Bulk Editor

    private var bulkEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One email per line:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $editText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 150)
                .border(Color.secondary.opacity(0.2))
                .onAppear {
                    editText = emails.joined(separator: "\n")
                }

            HStack {
                Text("\(editText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) emails")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Apply") {
                    let newEmails = editText
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty && isValidEmail($0) }
                    emails = newEmails
                    onSave()
                }
            }
        }
    }

    // MARK: - Actions

    private func addEmail() {
        let normalized = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty, isValidEmail(normalized), !emails.contains(normalized) else {
            return
        }
        emails.append(normalized)
        newEmail = ""
        onSave()
    }

    private func removeEmail(_ email: String) {
        emails.removeAll { $0 == email }
        onSave()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Preview

#Preview("VIP Editor") {
    VIPContactsEditor(
        emails: .constant(["ceo@company.com", "manager@company.com"]),
        onSave: {}
    )
    .padding()
    .frame(width: 400)
}
