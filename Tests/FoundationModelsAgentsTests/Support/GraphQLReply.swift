import Foundation
import Testing

/// One GraphQL response that a test reads.
struct GraphQLReply {
    /// The JSON text of the response.
    let text: String

    /// The `data` object, or `nil` when the response has none.
    let data: [String: Any]?

    /// The `extensions.code` of each error, in order.
    let codes: [String]

    /// The `from` and `to` names of each rewrite in `extensions.rewrites`,
    /// in order.
    let rewrites: [(from: String, to: String)]

    /// Reads a response.
    ///
    /// - Parameter text: The JSON text.
    /// - Throws: A failed requirement when the text is not a JSON object.
    init(_ text: String) throws {
        self.text = text
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        data = object["data"] as? [String: Any]
        let errors = object["errors"] as? [[String: Any]] ?? []
        codes = errors.compactMap { error in (error["extensions"] as? [String: Any])?["code"] as? String }
        let rewriteList = (object["extensions"] as? [String: Any])?["rewrites"] as? [[String: Any]] ?? []
        rewrites = rewriteList.compactMap { rewrite in
            guard let from = rewrite["from"] as? String, let to = rewrite["to"] as? String else {
                return nil
            }
            return (from, to)
        }
    }

    /// The object of one field of `data`.
    ///
    /// - Parameter name: The response key of the field.
    /// - Returns: The object.
    /// - Throws: A failed requirement when the field is not an object.
    func object(_ name: String) throws -> [String: Any] {
        try #require(data?[name] as? [String: Any], "no object \(name) in \(text)")
    }

    /// The list of objects of one field of `data`.
    ///
    /// - Parameter name: The response key of the field.
    /// - Returns: The objects, in the order of the response.
    /// - Throws: A failed requirement when the field is not a list of
    ///   objects.
    func objects(_ name: String) throws -> [[String: Any]] {
        try #require(data?[name] as? [[String: Any]], "no list \(name) in \(text)")
    }

    /// Tells whether one field of `data` is JSON `null`.
    ///
    /// - Parameter name: The response key of the field.
    /// - Returns: `true` when `data` has the key and its value is `null`.
    func isNull(_ name: String) -> Bool {
        data?[name] is NSNull
    }
}
