import FoundationModelsExtras
import Graphiti
import GraphQL

// The schema parts of the agent mutations of the `agents` endpoint (D190):
// the enum of the writable layers, the inputs, the payload of `removeAgent`,
// and the three mutation fields. The resolvers are in
// `AgentsGraphMutations.swift`.

extension AgentsGraphAPI {
    /// The text of the description of the `layer` field of an update or a
    /// remove.
    private static let heldLayerDescription =
        "The layer, which must hold the agent. Omit it for the writable layer of the highest precedence that "
        + "holds the agent."

    // MARK: Types

    /// The `AgentWriteLayer` enum.
    ///
    /// - Returns: The enum.
    static func writeLayerEnum() -> SchemaType {
        Enum(AgentsGraphWriteLayer.self, as: "AgentWriteLayer") {
            Value(.user).description("The user layer, for all projects.")
            Value(.project).description("The project layer, for this project only.")
        }
        .description("A layer that a mutation can write. The defaults and marketplace layers are read-only.")
    }

    /// The `RemoveAgentPayload` type.
    ///
    /// - Returns: The type.
    static func removePayloadType() -> SchemaType {
        Type(RemoveAgentPayload.self) {
            Field("id", at: \.id).description("The id of the deleted agent.")
            Field("layer", at: \.layer).description("The layer that the mutation deleted the agent from.")
            Field("agent", at: \.agent)
                .description("The copy of the agent in another layer that stays, or null when no copy stays.")
        }
        .description("What removeAgent deleted.")
    }

    /// The `AddAgentInput` input.
    ///
    /// - Returns: The input.
    static func addInput() -> SchemaType {
        Input(AddAgentInput.self) {
            InputField("id", at: \.id)
                .description("The id of the new agent: the name of its folder, or default for the default agent.")
            InputField("name", at: \.name)
                .description("The name to show. Omit it for the id. Only the default agent can have a different name.")
            InputField("description", at: \.description).description("When to use the agent.")
            InputField("model", at: \.model).description("The model key. Omit it for the default model.")
            InputField("color", at: \.color).description("The color key. Omit it for no color.")
            InputField("background", at: \.background).description("The background key. Omit it for no key.")
            InputField("body", at: \.body).description("The Markdown body: the instructions. Omit it for no body.")
            InputField("layer", at: \.layer).description("The layer to write. Omit it for USER.")
        }
        .description("The fields of addAgent.")
    }

    /// The `UpdateAgentInput` input.
    ///
    /// - Returns: The input.
    static func updateInput() -> SchemaType {
        Input(UpdateAgentInput.self) {
            InputField("id", at: \.id).description("The id of the agent to change.")
            InputField("name", at: \.name).description("The new name to show. Omit it for no change.")
            InputField("description", at: \.description).description("The new description. Omit it for no change.")
            InputField("model", at: \.model).description("The new model key. Omit it for no change.")
            InputField("color", at: \.color).description("The new color key. Omit it for no change.")
            InputField("background", at: \.background).description("The new background key. Omit it for no change.")
            InputField("body", at: \.body).description("The new Markdown body. Omit it for no change.")
            InputField("layer", at: \.layer).description(heldLayerDescription)
        }
        .description(
            "The fields of updateAgent. A field that you omit does not change, and each other key of the "
                + "frontmatter stays.")
    }

    /// The `RemoveAgentInput` input.
    ///
    /// - Returns: The input.
    static func removeInput() -> SchemaType {
        Input(RemoveAgentInput.self) {
            InputField("id", at: \.id).description("The id of the agent to delete.")
            InputField("layer", at: \.layer).description(heldLayerDescription)
        }
        .description("The fields of removeAgent.")
    }

    // MARK: Mutation fields

    /// The `Mutation.addAgent` field.
    ///
    /// - Returns: The field.
    static func addAgentField() -> QueryField {
        Field("addAgent", at: AgentsGraphResolver.addAgent) {
            Argument("input", at: \.input).description("The new agent.")
        }
        .description(
            "Makes a new agent: its AGENT.md. Gives the agent that wins for the id, or AGENT_EXISTS, "
                + "INVALID_AGENT or EXTERNAL_CLIENT_READ_ONLY.")
    }

    /// The `Mutation.updateAgent` field.
    ///
    /// - Returns: The field.
    static func updateAgentField() -> QueryField {
        Field("updateAgent", at: AgentsGraphResolver.updateAgent) {
            Argument("input", at: \.input).description("The agent and its changes.")
        }
        .description(
            "Writes the given fields into the AGENT.md of an agent. Gives the agent that wins for the id, or "
                + "NOT_FOUND, AGENT_READ_ONLY, INVALID_AGENT or EXTERNAL_CLIENT_READ_ONLY.")
    }

    /// The `Mutation.removeAgent` field.
    ///
    /// - Returns: The field.
    static func removeAgentField() -> QueryField {
        Field("removeAgent", at: AgentsGraphResolver.removeAgent) {
            Argument("input", at: \.input).description("The agent to delete.")
        }
        .description(
            "Deletes an agent and all its files from one layer. A copy in another layer stays. Gives NOT_FOUND, "
                + "AGENT_READ_ONLY, INVALID_AGENT or EXTERNAL_CLIENT_READ_ONLY for an agent that cannot be deleted.")
    }
}
