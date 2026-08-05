import Foundation

public struct DelimitedTableCell: Equatable, Sendable {
    public let value: String
    public let range: NSRange
}

public struct DelimitedTableModel: Equatable, Sendable {
    public let delimiter: Character
    public let rows: [[DelimitedTableCell]]
    public let columnWidths: [Int]

    public init(text: String, delimiter: Character? = nil) {
        let chosen = delimiter ?? (text.firstIndex(of: "\t") != nil ? "\t" : ",")
        self.delimiter = chosen
        var parsed: [[DelimitedTableCell]] = [], row: [DelimitedTableCell] = []
        var field = "", fieldStart = 0, offset = 0, quoted = false
        let ns = text as NSString
        while offset < ns.length {
            let scalar = ns.character(at: offset)
            if scalar == 34 {
                if quoted, offset + 1 < ns.length, ns.character(at: offset + 1) == 34 {
                    field.append("\""); offset += 2; continue
                }
                quoted.toggle(); offset += 1; continue
            }
            let character = Character(UnicodeScalar(scalar) ?? " ")
            if !quoted, character == chosen || character == "\n" || character == "\r" {
                row.append(.init(value: field, range: NSRange(location: fieldStart, length: offset - fieldStart)))
                field = ""
                if character == chosen { offset += 1; fieldStart = offset; continue }
                if character == "\r", offset + 1 < ns.length, ns.character(at: offset + 1) == 10 { offset += 1 }
                parsed.append(row); row = []; offset += 1; fieldStart = offset; continue
            }
            field.append(character); offset += 1
        }
        if fieldStart < ns.length || !field.isEmpty || !row.isEmpty {
            row.append(.init(value: field, range: NSRange(location: fieldStart, length: ns.length - fieldStart)))
            parsed.append(row)
        }
        rows = parsed
        let columns = parsed.map(\.count).max() ?? 0
        columnWidths = (0..<columns).map { column in
            min(80, parsed.compactMap { $0.indices.contains(column) ? $0[column].value.count : nil }.max() ?? 0)
        }
    }
}
