import Foundation
import FoundationModels
import Operations
import Testing

@testable import FoundationModelsAgents

/// Pins the schema of the `agents` tool (plan.md §9.1).
///
/// The schema is the fused schema of the four operations. The `name` field is
/// an enum of the model-visible agent names at `make`, limited by the allowed
/// names of the context. Thus the model cannot start an agent that it cannot
/// see.
@Suite("Agents tool schema")
struct AgentsToolSchemaTests {
    // MARK: - Constants

    /// The op strings of the four operations, in tool order.
    private static let opStrings = ["list agents", "start agent", "check agent", "cancel agent"]

    /// The name of the field that holds an agent name.
    static let nameFieldName = "name"

    /// The model-visible agents of the fixture library, in catalog order.
    private static let visibleNames = ["code-reviewer", "internal-helper", "lead", "test-writer"]

    /// The fixture agent with `disable-model-invocation: true`.
    private static let modelHiddenName = "release-manager"

    // MARK: - The operations

    @Test func theToolIsNamedAgents() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        #expect(harness.tool.name == "agents")
    }

    @Test func theSchemaHoldsTheFourOperations() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let opProperty = try Self.property(named: OperationKeys.opFieldName, in: harness.tool.parameters)

        #expect(opProperty["enum"] as? [String] == Self.opStrings)
    }

    @Test func eachOperationDeclaresItsParameters() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let parameters = Dictionary(
            uniqueKeysWithValues: harness.tool.operationTool.operations.lazy.map { operation in
                (operation.opString, operation.parameters.map { "\($0.name)\($0.required ? "" : "?")" })
            })

        #expect(
            parameters == [
                "list agents": ["filter?"],
                "start agent": ["name", "prompt"],
                "check agent": ["id?"],
                "cancel agent": ["id"]
            ])
    }

    @Test func theSchemaHoldsTheOpFieldAndEachParameter() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let properties = try Self.properties(in: harness.tool.parameters)

        #expect(Set(properties.keys) == [OperationKeys.opFieldName, "filter", "name", "prompt", "id"])
    }

    // MARK: - The name enum

    @Test func theNameFieldIsAnEnumOfTheModelVisibleNames() async throws {
        let harness = try await AgentsToolHarness.make()
        defer { try? harness.delete() }

        let nameProperty = try Self.property(named: Self.nameFieldName, in: harness.tool.parameters)

        #expect(nameProperty["enum"] as? [String] == Self.visibleNames)
        #expect(harness.tool.agentNames == Self.visibleNames)
        #expect(!harness.tool.agentNames.contains(Self.modelHiddenName))
    }

    @Test func theNameFieldHoldsOnlyTheAllowedNames() async throws {
        let allowed = ["code-reviewer", "test-writer"]
        let harness = try await AgentsToolHarness.make(allowedNames: allowed + [Self.modelHiddenName])
        defer { try? harness.delete() }

        let nameProperty = try Self.property(named: Self.nameFieldName, in: harness.tool.parameters)

        #expect(nameProperty["enum"] as? [String] == allowed)
        #expect(harness.tool.agentNames == allowed)
    }

    @Test func withNoAgentTheNameFieldIsAPlainString() async throws {
        let (harness, layer) = try await AgentsToolHarness.makeEmpty()
        defer {
            try? harness.delete()
            try? layer.delete()
        }

        let nameProperty = try Self.property(named: Self.nameFieldName, in: harness.tool.parameters)

        #expect(nameProperty["enum"] == nil, "an empty enum accepts no value, thus the name stays a plain string")
        #expect(nameProperty["type"] as? String == "string")
    }

    // MARK: - Support

    /// Reads the top-level properties of `schema` from its JSON form.
    ///
    /// - Parameter schema: The fused schema of the tool.
    /// - Returns: Each property schema, by name.
    /// - Throws: An encode error, or a `#require` failure when the JSON has
    ///   no `properties` object.
    private static func properties(in schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["properties"] as? [String: Any])
    }

    /// Reads one property schema of `schema`.
    ///
    /// - Parameters:
    ///   - name: The property name.
    ///   - schema: The fused schema of the tool.
    /// - Returns: The JSON object of the property.
    /// - Throws: A `#require` failure when the schema has no such property.
    static func property(named name: String, in schema: GenerationSchema) throws -> [String: Any] {
        try #require(try properties(in: schema)[name] as? [String: Any])
    }
}
