import Testing

/// Pins how `ScriptedTranscriptText` reads the completion token of a pending
/// envelope.
@Suite("Scripted transcript text")
struct ScriptedTranscriptTextTests {
    /// A ULID of 26 Crockford base-32 characters in lowercase.
    private static let lowercaseToken = "01m3n4k7gtfg8509ck31v80mjp"

    /// Crockford base-32 is case-insensitive. Thus a lowercase completion
    /// token is a token, and the read gives it with no change.
    @Test("A lowercase completion token is extracted")
    func lowercaseCompletionTokenIsExtracted() {
        let output = #"{"status":"pending","completionToken":"\#(Self.lowercaseToken)"}"#

        #expect(ScriptedTranscriptText.completionToken(in: output) == Self.lowercaseToken)
    }
}
