import Foundation

public enum HidemaruCompatibilityError: LocalizedError, Equatable {
    case unexpectedToken(line: Int, text: String)
    case missingArgument(line: Int, command: String)
    case unsupportedCommand(line: Int, command: String)
    public var errorDescription: String? {
        switch self {
        case .unexpectedToken(let line, let text): "Line \(line): unexpected token \(text)."
        case .missingArgument(let line, let command): "Line \(line): \(command) requires a string."
        case .unsupportedCommand(let line, let command): "Line \(line): unsupported command \(command)."
        }
    }
}

public enum HidemaruCompatibility {
    public static let featureFlag = "MARUEDIT_ENABLE_HIDEMARU_COMPATIBILITY"
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 defaults: UserDefaults = .standard) -> Bool {
        environment[featureFlag] == "1" || defaults.bool(forKey: "ExperimentalHidemaruMacroCompatibility")
    }

    private enum Command: Equatable {
        case selectAll, fileTop, fileEnd, delete, upper, lower
        case insert(String), message(String)
    }

    /// Clean-room parser for MaruEdit's documented semicolon-delimited subset.
    public static func translate(_ source: String) throws -> String {
        let commands = try parse(source)
        let encoded = commands.map(javaScript).joined(separator: "\n")
        return #"""
        (() => {
          let text = maru.document.getText();
          let selections = maru.editor.getSelections();
          const replace = (transform, keepSelected = false) => {
            const ordered = selections.map((r, i) => ({...r, i})).sort((a,b) => b.location-a.location);
            for (const r of ordered) {
              const value = transform(text.slice(r.location, r.location + r.length));
              text = text.slice(0, r.location) + value + text.slice(r.location + r.length);
              const delta = value.length - r.length;
              for (let i = 0; i < selections.length; i++) {
                if (i !== r.i && selections[i].location > r.location) selections[i].location += delta;
              }
              selections[r.i] = keepSelected
                ? {location: r.location, length: value.length}
                : {location: r.location + value.length, length: 0};
            }
          };
          maru.undo.group('Experimental Hidemaru macro', () => {
        """# + encoded + #"""
            maru.document.setText(text); maru.editor.setSelections(selections);
          });
        })();
        """#
    }

    private static func parse(_ source: String) throws -> [Command] {
        var commands: [Command] = []
        for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = offset + 1
            let withoutComment = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !withoutComment.isEmpty else { continue }
            for rawStatement in splitStatements(withoutComment) {
                let statement = rawStatement.trimmingCharacters(in: .whitespaces)
                guard !statement.isEmpty else { continue }
                let end = statement.firstIndex(where: \.isWhitespace) ?? statement.endIndex
                let name = statement[..<end].lowercased()
                let rest = statement[end...].trimmingCharacters(in: .whitespaces)
                switch name {
                case "selectall": commands.append(.selectAll)
                case "gofiletop": commands.append(.fileTop)
                case "gofileend": commands.append(.fileEnd)
                case "delete": commands.append(.delete)
                case "toupper": commands.append(.upper)
                case "tolower": commands.append(.lower)
                case "insert", "message":
                    guard let value = parseString(rest) else {
                        throw HidemaruCompatibilityError.missingArgument(line: line, command: name)
                    }
                    commands.append(name == "insert" ? .insert(value) : .message(value))
                default: throw HidemaruCompatibilityError.unsupportedCommand(line: line, command: name)
                }
            }
        }
        return commands
    }

    private static func stripComment(_ line: String) -> String {
        var quoted = false, escaped = false
        for index in line.indices {
            let c = line[index]
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { quoted.toggle(); continue }
            if !quoted, c == "/", line.index(after: index) < line.endIndex,
               line[line.index(after: index)] == "/" { return String(line[..<index]) }
        }
        return line
    }

    private static func splitStatements(_ line: String) -> [String] {
        var values: [String] = [], start = line.startIndex, quoted = false, escaped = false
        for index in line.indices {
            let c = line[index]
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { quoted.toggle() }
            else if c == ";", !quoted { values.append(String(line[start..<index])); start = line.index(after: index) }
        }
        if start < line.endIndex { values.append(String(line[start...])) }
        return values
    }

    private static func parseString(_ raw: String) -> String? {
        guard raw.first == "\"", raw.last == "\"", raw.count >= 2 else { return nil }
        var value = "", escaped = false
        for c in raw.dropFirst().dropLast() {
            if escaped {
                switch c { case "n": value.append("\n"); case "t": value.append("\t"); default: value.append(c) }
                escaped = false
            } else if c == "\\" { escaped = true } else { value.append(c) }
        }
        if escaped { value.append("\\") }
        return value
    }

    private static func javaScript(_ command: Command) -> String {
        switch command {
        case .selectAll: "selections.splice(0, selections.length, {location:0,length:text.length});"
        case .fileTop: "selections.splice(0, selections.length, {location:0,length:0});"
        case .fileEnd: "selections.splice(0, selections.length, {location:text.length,length:0});"
        case .delete: "replace(() => '');"
        case .upper: "replace(value => maru.text.uppercase(value), true);"
        case .lower: "replace(value => maru.text.lowercase(value), true);"
        case .insert(let value): "replace(() => \(jsString(value)));"
        case .message(let value): "maru.ui.message(\(jsString(value)));"
        }
    }
    private static func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }
}
