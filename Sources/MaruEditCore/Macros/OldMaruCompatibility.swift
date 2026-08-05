import Foundation

public enum OldMaruCompatibilityError: LocalizedError, Equatable {
    case unexpectedToken(line: Int, text: String)
    case missingArgument(line: Int, command: String)
    case unsupportedCommand(line: Int, command: String)
    case unsafeCommand(line: Int, command: String)
    case windowsOnlyCommand(line: Int, command: String)
    case invalidExpression(line: Int, text: String)
    public var errorDescription: String? {
        switch self {
        case .unexpectedToken(let line, let text): "Line \(line): unexpected token \(text)."
        case .missingArgument(let line, let command): "Line \(line): \(command) requires a string."
        case .unsupportedCommand(let line, let command): "Line \(line): unsupported command \(command)."
        case .unsafeCommand(let line, let command): "Line \(line): unsafe command \(command) is intentionally unavailable."
        case .windowsOnlyCommand(let line, let command): "Line \(line): Windows-only command \(command) has no macOS equivalent."
        case .invalidExpression(let line, let text): "Line \(line): invalid or unsafe expression \(text)."
        }
    }
}

public enum OldMaruCompatibility {
    public static let featureFlag = "MARUEDIT_ENABLE_OLDMARU_COMPATIBILITY"
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 defaults: UserDefaults = .standard) -> Bool {
        environment[featureFlag] == "1" || defaults.bool(forKey: "ExperimentalOldMaruMacroCompatibility")
    }

    private enum Command: Equatable {
        case selectAll, fileTop, fileEnd, delete, upper, lower
        case insert(String), message(String)
        case runCommand(String)
    }

    /// Clean-room parser for MaruEdit's documented semicolon-delimited subset.
    public static func translate(_ source: String) throws -> String {
        let encoded = try translateStatements(source).joined(separator: "\n")
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
          maru.undo.group('Experimental OldMaru macro', () => {
        """# + encoded + #"""
            maru.document.setText(text); maru.editor.setSelections(selections);
          });
        })();
        """#
    }

    private struct Token { let line: Int; let text: String }

    private static func translateStatements(_ source: String) throws -> [String] {
        var output: [String] = []
        var pendingWhileBody = false
        for token in tokenize(source) {
            let statement = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !statement.isEmpty else { continue }
            if statement == "{" {
                output.append(pendingWhileBody ? "{ maru.checkCancellation();" : "{")
                pendingWhileBody = false
                continue
            }
            if statement == "}" { output.append(statement); continue }
            if statement.lowercased() == "else" { output.append("else"); continue }
            let lower = statement.lowercased()
            if lower.hasPrefix("if ") || lower.hasPrefix("if(") {
                let raw = statement.dropFirst(2).trimmingCharacters(in: .whitespaces)
                output.append("if (\(try expression(String(raw), line: token.line)))")
                continue
            }
            if lower.hasPrefix("while ") || lower.hasPrefix("while(") {
                let raw = statement.dropFirst(5).trimmingCharacters(in: .whitespaces)
                output.append("while (\(try expression(String(raw), line: token.line)))")
                pendingWhileBody = true
                continue
            }
            if lower.hasPrefix("function ") {
                let name = statement.dropFirst(9).trimmingCharacters(in: .whitespaces)
                guard isIdentifier(name) else { throw OldMaruCompatibilityError.invalidExpression(line: token.line, text: statement) }
                output.append("function compat_\(name)()")
                continue
            }
            if lower.hasPrefix("call ") {
                let name = statement.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard isIdentifier(name) else { throw OldMaruCompatibilityError.invalidExpression(line: token.line, text: statement) }
                output.append("compat_\(name)();")
                continue
            }
            if lower == "return" { output.append("return;"); continue }
            if lower == "break" || lower == "continue" { output.append(lower + ";"); continue }
            if statement.first == "#" || statement.first == "$" {
                guard let equals = statement.firstIndex(of: "=") else {
                    throw OldMaruCompatibilityError.invalidExpression(line: token.line, text: statement)
                }
                let name = statement[..<equals].trimmingCharacters(in: .whitespaces)
                let value = statement[statement.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                guard name.count > 1, isIdentifier(name.dropFirst()) else {
                    throw OldMaruCompatibilityError.invalidExpression(line: token.line, text: statement)
                }
                output.append("\(variable(String(name))) = \(try expression(value, line: token.line));")
                continue
            }
            let command = try parse(statement, line: token.line)
            output.append(javaScript(command))
        }
        let variableRegex = try NSRegularExpression(pattern: #"[#$][A-Za-z_][A-Za-z0-9_]*"#)
        let variables = Set(tokenize(source).flatMap { token -> [String] in
            let ns = token.text as NSString
            return variableRegex.matches(in: token.text, range: NSRange(location: 0, length: ns.length))
                .map { variable(ns.substring(with: $0.range)) }
        })
        return variables.sorted().map { "let \($0);" } + output
    }

    private static func tokenize(_ source: String) -> [Token] {
        let source = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripComment(String($0)) }.joined(separator: "\n")
        var result: [Token] = [], buffer = "", line = 1, startLine = 1
        var quoted = false, escaped = false, comment = false
        func flush() { if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(Token(line: startLine, text: buffer)) }; buffer = "" }
        for character in source {
            if comment {
                if character == "\n" { comment = false; line += 1; if buffer.isEmpty { startLine = line } }
                continue
            }
            if escaped { buffer.append(character); escaped = false; continue }
            if character == "\\", quoted { buffer.append(character); escaped = true; continue }
            if character == "\"" { quoted.toggle(); buffer.append(character); continue }
            if !quoted, character == ";" { flush(); startLine = line; continue }
            if !quoted, character == "{" || character == "}" {
                flush(); result.append(Token(line: line, text: String(character))); startLine = line; continue
            }
            if character == "\n" { line += 1 }
            buffer.append(character)
        }
        flush(); return result
    }

    private static func expression(_ raw: String, line: Int) throws -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("("), value.hasSuffix(")") { value = String(value.dropFirst().dropLast()) }
        let forbidden = ["globalthis", "eval", "constructor", "prototype", "require", "import", "fetch", "process"]
        guard !value.isEmpty, !forbidden.contains(where: { value.lowercased().contains($0) }),
              value.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "_#$\"'()+-*/%<>=!&|.,[]")).contains(scalar)
              }) else { throw OldMaruCompatibilityError.invalidExpression(line: line, text: raw) }
        value = value.replacingOccurrences(of: #"#([A-Za-z_][A-Za-z0-9_]*)"#, with: "compat_num_$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\$([A-Za-z_][A-Za-z0-9_]*)"#, with: "compat_str_$1", options: .regularExpression)
        return value
    }

    private static func variable(_ name: String) -> String {
        "compat_" + (name.first == "#" ? "num" : "str") + "_" + name.dropFirst()
    }

    private static func isIdentifier<S: StringProtocol>(_ value: S) -> Bool {
        let characters = Array(value)
        guard let first = characters.first, first == "_" || first.isASCII && first.isLetter else { return false }
        return characters.dropFirst().allSatisfy { $0 == "_" || $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func parse(_ statement: String, line: Int) throws -> Command {
        let end = statement.firstIndex(where: \.isWhitespace) ?? statement.endIndex
        let name = statement[..<end].lowercased()
        let rest = statement[end...].trimmingCharacters(in: .whitespaces)
        switch name {
        case "selectall": return .selectAll
        case "gofiletop": return .fileTop
        case "gofileend": return .fileEnd
        case "delete": return .delete
        case "toupper": return .upper
        case "tolower": return .lower
        case "insert", "message":
            guard let value = parseString(rest) else { throw OldMaruCompatibilityError.missingArgument(line: line, command: name) }
            return name == "insert" ? .insert(value) : .message(value)
        case "findnext": return .runCommand("search.findNext")
        case "findprevious": return .runCommand("search.findPrevious")
        case "showoutline": return .runCommand("view.toggleSidebar")
        case "nextwindow": return .runCommand("window.next")
        case "run", "exec", "shell", "dll", "network": throw OldMaruCompatibilityError.unsafeCommand(line: line, command: name)
        case "registry", "dde", "sendmessage", "trayicon": throw OldMaruCompatibilityError.windowsOnlyCommand(line: line, command: name)
        default: throw OldMaruCompatibilityError.unsupportedCommand(line: line, command: name)
        }
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
                        throw OldMaruCompatibilityError.missingArgument(line: line, command: name)
                    }
                    commands.append(name == "insert" ? .insert(value) : .message(value))
                default: throw OldMaruCompatibilityError.unsupportedCommand(line: line, command: name)
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
        case .runCommand(let id): "maru.commands.run(\(jsString(id)));"
        }
    }
    private static func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }
}
