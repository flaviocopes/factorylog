import Foundation

/// Turns a prompt into a sentence or two of prose.
///
/// Factory Log only ever asks a local engine to rephrase reports agents already
/// wrote, so an engine that is missing or switched off is normal rather than an
/// error: the app falls back to the factual rollup.
public protocol NarrativeEngine: Sendable {
    func isAvailable() async -> Bool
    func write(system: String, prompt: String) async throws -> String
}

/// Talks to a local Ollama server over its HTTP API.
public struct OllamaClient: NarrativeEngine {
    public struct Configuration: Sendable {
        public var host: URL
        public var model: String
        public var timeout: TimeInterval

        public init(
            host: URL = Configuration.defaultHost,
            model: String = Configuration.defaultModel,
            timeout: TimeInterval = 90
        ) {
            self.host = host
            self.model = model
            self.timeout = timeout
        }

        public static var defaultHost: URL {
            let key = "\(FactoryLogProduct.environmentPrefix)_OLLAMA_HOST"
            let environment = ProcessInfo.processInfo.environment[key]
            return environment.flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:11434")!
        }

        public static var defaultModel: String {
            let key = "\(FactoryLogProduct.environmentPrefix)_OLLAMA_MODEL"
            return ProcessInfo.processInfo.environment[key] ?? "gemma3:4b"
        }
    }

    public enum ClientError: Error, LocalizedError, Equatable {
        case unavailable
        case badStatus(Int)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                "Ollama is not reachable."
            case let .badStatus(code):
                "Ollama answered with status \(code)."
            case .emptyResponse:
                "Ollama returned an empty summary."
            }
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func isAvailable() async -> Bool {
        var request = URLRequest(url: configuration.host.appending(path: "api/tags"))
        // A missing server should be discovered in a moment, not after a stall.
        request.timeoutInterval = 2

        guard let (_, response) = try? await session.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    public func write(system: String, prompt: String) async throws -> String {
        var request = URLRequest(url: configuration.host.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(
                model: configuration.model,
                system: system,
                prompt: prompt,
                stream: false,
                options: .init(temperature: 0.2)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.unavailable
        }

        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw ClientError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let text = try JSONDecoder()
            .decode(GenerateResponse.self, from: data)
            .response
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ClientError.emptyResponse
        }
        return text
    }

    private var session: URLSession {
        URLSession(configuration: .ephemeral)
    }

    private struct GenerateRequest: Encodable {
        struct Options: Encodable {
            let temperature: Double
        }

        let model: String
        let system: String
        let prompt: String
        let stream: Bool
        let options: Options
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }
}
