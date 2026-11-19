import Foundation

/// The five ways to ask an AI: three API providers (the user's own key) and two subscription CLIs
/// (Claude Code, Codex) the user is already signed in to.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude, openai, grok, openrouter, local
    case claudeCli = "claude-cli"
    case codexCli = "codex-cli"

    public var id: String { rawValue }

    public var isCLI: Bool { self == .claudeCli || self == .codexCli }

    public var name: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .grok: return "Grok"
        case .openrouter: return "OpenRouter"
        case .local: return "Local server"
        case .claudeCli: return "Claude (my subscription)"
        case .codexCli: return "ChatGPT (my subscription)"
        }
    }

    /// Short tab label.
    public var tab: String {
        switch self {
        case .claude, .claudeCli: return "Claude"
        case .openai, .codexCli: return "ChatGPT"
        case .grok: return "Grok"
        case .openrouter: return "OpenRouter"
        case .local: return "Local"
        }
    }

    public var vendor: String {
        switch self {
        case .claude, .claudeCli: return "Anthropic"
        case .openai, .codexCli: return "OpenAI"
        case .grok: return "xAI"
        case .openrouter: return "OpenRouter"
        case .local: return "your own computer"
        }
    }

    /// The API provider whose colour and icon a subscription shares.
    public var base: ProviderID {
        switch self {
        case .claudeCli: return .claude
        case .codexCli: return .openai
        default: return self
        }
    }

    public var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-5-5"
        case .openai: return "gpt-5"
        case .grok: return "grok-4"
        case .local: return "default" // "default" = whichever model the server has loaded
        case .openrouter: return "openrouter/auto" // OpenRouter picks a model per request; type any model id to choose one
        case .claudeCli, .codexCli: return "default"
        }
    }

    public var knownModels: [String] {
        switch self {
        case .claude: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        case .openai: return ["gpt-5", "gpt-5-mini"]
        case .grok: return ["grok-4", "grok-4-fast"]
        case .openrouter: return ["openrouter/auto"]
        case .local: return ["default"]
        case .claudeCli: return ["default", "opus", "sonnet", "haiku"]
        case .codexCli: return ["default"]
        }
    }

    /// Where to create an API key.
    public var keyPage: URL? {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .grok: return URL(string: "https://console.x.ai")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        default: return nil
        }
    }
}

/// Result of one question or test. Never thrown: failures come back with a plain sentence in `error`.
public struct AgentAnswer: Sendable {
    public var ok: Bool
    public var model: String
    public var text: String
    public var error: String?

    public static func failure(_ error: String, model: String = "", text: String = "") -> AgentAnswer {
        AgentAnswer(ok: false, model: model, text: text, error: error)
    }
}

/// What the UI needs to know about one provider.
public struct ProviderInfo: Identifiable, Sendable {
    public var id: ProviderID
    /// API key saved, or (for a subscription) the CLI is installed and not known to be signed out.
    public var hasKey: Bool
    public var model: String
    public var models: [String]
    public var cli: CLIStatus?
}

public struct CLIStatus: Sendable {
    public var installed = false
    /// Signed in for sure, and not with an API key: only then it is first in the UI and picked by Auto.
    public var ready = false
    public var version: String?
    public var loggedIn: Bool?
    public var path: String?
    public var authMethod: String?
    public var product = ""
    public var installCommand = ""
    public var loginCommand = ""
    public var error: String?
    public var note: String?
}
