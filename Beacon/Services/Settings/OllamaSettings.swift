import Foundation
import Combine

/// Persistent settings for Ollama configuration
/// Manages connection URL, embedding model selection, and connection status
class OllamaSettings: ObservableObject {
    // Singleton
    static let shared = OllamaSettings()

    // UserDefaults keys
    private enum Keys {
        static let baseURL = "ollama.baseURL"
        static let embeddingModel = "ollama.embeddingModel"
    }

    // MARK: - Published Settings (Persisted)

    /// Ollama server base URL (default localhost:11434)
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
        }
    }

    /// Selected embedding model name (default nomic-embed-text)
    @Published var embeddingModel: String {
        didSet {
            UserDefaults.standard.set(embeddingModel, forKey: Keys.embeddingModel)
        }
    }

    // MARK: - Runtime State (Not Persisted)

    /// Whether Ollama is currently connected and running
    @Published var isConnected: Bool = false

    /// Available models from the Ollama instance
    @Published var availableModels: [String] = []

    /// Ollama version string (e.g., "0.1.24")
    @Published var ollamaVersion: String?

    /// Whether a connection check is in progress
    @Published var isChecking: Bool = false

    /// Last error message if connection failed
    @Published var lastError: String?

    // MARK: - Static Configuration

    /// Default Ollama URL
    static let defaultURL = "http://localhost:11434"

    /// Default embedding model
    static let defaultEmbeddingModel = "nomic-embed-text"

    /// Common embedding models (for suggestions)
    static let recommendedEmbeddingModels = [
        "nomic-embed-text",      // 768 dimensions, fast, good quality
        "all-minilm",            // 384 dimensions, smaller
        "mxbai-embed-large",     // 1024 dimensions, high quality
    ]

    // MARK: - Initialization

    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? Self.defaultURL
        self.embeddingModel = UserDefaults.standard.string(forKey: Keys.embeddingModel) ?? Self.defaultEmbeddingModel
    }

    // MARK: - Connection Check

    /// Check connection to Ollama and update status
    /// Creates an OllamaService with current baseURL and queries its status
    @MainActor
    func checkConnection() async {
        isChecking = true
        lastError = nil

        let service = OllamaService(
            host: baseURL,
            embeddingModel: embeddingModel,
            llmModel: AIConfig.ollamaLLMModel
        )

        // Check if running
        isConnected = await service.isRunning()

        if isConnected {
            do {
                // Get version
                ollamaVersion = try await service.getVersion()

                // Get available models
                let models = try await service.listModels()
                availableModels = models.map { $0.name }
            } catch {
                // Connection succeeded but couldn't get details
                debugLog("OllamaSettings: Connected but couldn't fetch details: \(error)")
            }
        } else {
            lastError = "Cannot connect to Ollama at \(baseURL)"
            ollamaVersion = nil
            availableModels = []
        }

        isChecking = false
    }

    /// Reset to default URL
    func resetToDefault() {
        baseURL = Self.defaultURL
        embeddingModel = Self.defaultEmbeddingModel
    }

    /// Check if the selected embedding model is available
    var isEmbeddingModelAvailable: Bool {
        availableModels.contains { $0.hasPrefix(embeddingModel) }
    }

    /// Status text for display
    var statusText: String {
        if isChecking {
            return "Checking..."
        } else if isConnected {
            if let version = ollamaVersion {
                return "Connected (v\(version))"
            }
            return "Connected"
        } else {
            return lastError ?? "Not connected"
        }
    }
}
