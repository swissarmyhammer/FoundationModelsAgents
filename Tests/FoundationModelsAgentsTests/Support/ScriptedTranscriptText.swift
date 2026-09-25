import FoundationModels

/// Reads the text of the transcript parts that select a play.
enum ScriptedTranscriptText {
    /// The text of the leading `.instructions` entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is no such entry.
    static func instructions(of transcript: Transcript) -> String {
        for entry in transcript {
            if case .instructions(let instructions) = entry {
                return text(of: instructions.segments)
            }
        }
        return ""
    }

    /// The text of the first `.prompt` entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is no such entry.
    static func firstPrompt(of transcript: Transcript) -> String {
        prompts(of: transcript).first ?? ""
    }

    /// The text of each `.prompt` entry of `transcript` after the first,
    /// with a blank line between two prompts.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is one prompt or
    ///   none.
    static func laterPrompts(of transcript: Transcript) -> String {
        prompts(of: transcript)
            .dropFirst()
            .joined(separator: "\n\n")
    }

    /// The text of the last `.prompt` entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: The text, or the empty string when there is no such entry.
    static func lastPrompt(of transcript: Transcript) -> String {
        prompts(of: transcript).last ?? ""
    }

    /// The text of each `.prompt` entry of `transcript`, in transcript order.
    ///
    /// - Parameter transcript: The transcript to read.
    /// - Returns: One string for each prompt entry.
    private static func prompts(of transcript: Transcript) -> [String] {
        transcript.compactMap { entry -> String? in
            if case .prompt(let prompt) = entry {
                return text(of: prompt.segments)
            }
            return nil
        }
    }

    /// The joined text of `segments`.
    ///
    /// - Parameter segments: The segments to read.
    /// - Returns: The text of each segment, joined in order. A structured
    ///   segment gives its JSON. An attachment gives its description.
    static func text(of segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                text.content
            case .structure(let structure):
                structure.content.jsonString
            case .attachment:
                String(describing: segment)
            @unknown default:
                String(describing: segment)
            }
        }.joined()
    }
}
