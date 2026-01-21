import SwiftUI

/// Ollama configuration section
/// Shows connection status, URL configuration, and embedding model selection
struct OllamaSection: View {
    @ObservedObject private var settings = OllamaSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Connection status row
            HStack {
                Circle()
                    .fill(settings.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                if settings.isConnected {
                    Text("Connected")
                        .font(.subheadline)
                    if let version = settings.ollamaVersion {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Not connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if settings.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Test") {
                        Task {
                            await settings.checkConnection()
                        }
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            // URL field
            HStack {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                TextField("http://localhost:11434", text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Embedding model picker (only if connected and models available)
            if settings.isConnected && !settings.availableModels.isEmpty {
                HStack {
                    Text("Model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Picker("", selection: $settings.embeddingModel) {
                        ForEach(settings.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Error display
            if let error = settings.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            // Help text
            Text("Ollama provides local embeddings for search. Core features work without it.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear {
            Task { await settings.checkConnection() }
        }
    }
}

#Preview {
    OllamaSection()
        .padding()
        .frame(width: 300)
}
