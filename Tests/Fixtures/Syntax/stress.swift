// M7 syntax stress fixture: long tokens, nested-looking comments, Unicode,
// interpolation, and many matches are repeated by the test harness.
struct 日本語Renderer<Value> {
    let values: [Value]
    func render(_ transform: (Value) async throws -> String) async rethrows -> String {
        var output = "prefix 👍 e\u{301}"
        for value in values {
            output += try await transform(value)
        }
        return output
    }
}

/* A multiline comment containing misleading tokens:
   let class func "string" // nested-looking opener /* and terminator */
let pathologicalCandidate = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!"
