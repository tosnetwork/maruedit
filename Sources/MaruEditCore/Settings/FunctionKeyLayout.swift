import Foundation

/// Ordered F-key assignments shared by the command strip and its persisted configuration.
public struct FunctionKeyLayout: Codable, Equatable, Sendable {
    public var assignments: [CommandID?]

    public init(assignments: [CommandID?]) {
        self.assignments = assignments
    }

    public func normalized(maximumSlots: Int = 12, available: Set<CommandID>) -> FunctionKeyLayout {
        var values = Array(assignments.prefix(max(0, maximumSlots)))
        values = values.map { id in id.flatMap { available.contains($0) ? $0 : nil } }
        if values.count < maximumSlots {
            values.append(contentsOf: repeatElement(nil, count: maximumSlots - values.count))
        }
        return FunctionKeyLayout(assignments: values)
    }
}
