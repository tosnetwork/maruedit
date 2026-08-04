import Foundation

public enum ExternalCommandInput: String, Codable, CaseIterable, Sendable {
    case none
    case currentDocument
    case selection
}

public enum ExternalCommandOutput: String, Codable, CaseIterable, Sendable {
    case newDocument
    case replaceSelection
    case outputPane
    case clipboard
}

public enum ExternalWorkingDirectory: String, Codable, CaseIterable, Sendable {
    case none
    case currentDocumentDirectory
    case explicit
}

public struct ExternalCommandConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: ExternalWorkingDirectory
    public var workingDirectoryPath: String?
    public var inheritedEnvironment: [String]
    public var environment: [String: String]
    public var input: ExternalCommandInput
    public var output: ExternalCommandOutput
    public var shellMode: Bool
    public var shellCommand: String?

    public init(
        id: String, name: String, executable: String, arguments: [String] = [],
        workingDirectory: ExternalWorkingDirectory = .none,
        workingDirectoryPath: String? = nil,
        inheritedEnvironment: [String] = [], environment: [String: String] = [:],
        input: ExternalCommandInput = .none, output: ExternalCommandOutput = .outputPane,
        shellMode: Bool = false, shellCommand: String? = nil,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.executable = executable; self.arguments = arguments
        self.workingDirectory = workingDirectory; self.workingDirectoryPath = workingDirectoryPath
        self.inheritedEnvironment = inheritedEnvironment; self.environment = environment
        self.input = input; self.output = output; self.shellMode = shellMode
        self.shellCommand = shellCommand
    }

    public var commandID: CommandID { CommandID("external.user." + id) }
    public var riskDescription: String? {
        shellMode ? "Shell mode interprets command text and is higher risk." : nil
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ExternalCommandConfigurationError.unsupportedSchema(schemaVersion)
        }
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw ExternalCommandConfigurationError.invalidID(id)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExternalCommandConfigurationError.emptyName
        }
        if shellMode {
            guard shellCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ExternalCommandConfigurationError.missingShellCommand
            }
        } else {
            if !executable.hasPrefix("/") {
                throw ExternalCommandConfigurationError.executableMustBeAbsolute
            }
            if ["sh", "bash", "zsh", "fish", "csh", "tcsh", "dash", "ksh"]
                .contains(URL(fileURLWithPath: executable).lastPathComponent) {
                throw ExternalCommandConfigurationError.shellExecutableRequiresShellMode
            }
        }
        if workingDirectory == .explicit,
           workingDirectoryPath?.hasPrefix("/") != true {
            throw ExternalCommandConfigurationError.workingDirectoryMustBeAbsolute
        }
        func isValidEnvironmentName(_ value: String) -> Bool {
            guard let first = value.utf8.first,
                  first == 95 || (65...90).contains(first) || (97...122).contains(first) else {
                return false
            }
            return value.utf8.dropFirst().allSatisfy {
                $0 == 95 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }
        }
        guard inheritedEnvironment.allSatisfy(isValidEnvironmentName),
              environment.keys.allSatisfy(isValidEnvironmentName) else {
            throw ExternalCommandConfigurationError.invalidEnvironmentName
        }
    }

    public func resolvedEnvironment(from parent: [String: String]) -> [String: String] {
        var result = environment
        for name in Set(inheritedEnvironment) where result[name] == nil {
            if let value = parent[name] { result[name] = value }
        }
        return result
    }
}

public enum ExternalCommandConfigurationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidID(String)
    case emptyName
    case executableMustBeAbsolute
    case shellExecutableRequiresShellMode
    case missingShellCommand
    case workingDirectoryMustBeAbsolute
    case invalidEnvironmentName

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let value): "Unsupported external-command schema \(value)."
        case .invalidID(let value): "Invalid external-command ID: \(value)."
        case .emptyName: "External command name is empty."
        case .executableMustBeAbsolute: "Executable paths must be absolute."
        case .shellExecutableRequiresShellMode: "Shell executables require visibly marked shell mode."
        case .missingShellCommand: "Shell mode requires command text."
        case .workingDirectoryMustBeAbsolute: "Explicit working directories must be absolute."
        case .invalidEnvironmentName: "Environment names must be portable identifiers."
        }
    }
}

public enum ExternalCommandConfigurationStore {
    public static func encode(_ configurations: [ExternalCommandConfiguration]) throws -> Data {
        for configuration in configurations { try configuration.validate() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configurations)
    }
    public static func decode(_ data: Data) throws -> [ExternalCommandConfiguration] {
        let values = try JSONDecoder().decode([ExternalCommandConfiguration].self, from: data)
        for value in values { try value.validate() }
        guard Set(values.map(\.id)).count == values.count else {
            throw ExternalCommandConfigurationError.invalidID("duplicate")
        }
        return values
    }
}
