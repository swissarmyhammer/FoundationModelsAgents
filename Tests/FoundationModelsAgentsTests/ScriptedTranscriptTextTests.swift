import Testing

/// Pins how `ScriptedTranscriptText` reads the completion token of a pending
/// envelope.
@Suite("Scripted transcript text")
struct ScriptedTranscriptTextTests {
    /// A ULID of 26 Crockford base-32 characters in lowercase.
    private static let lowercaseToken = "01m3n4k7gtfg8509ck31v80mjp"

    /// The same ULID in uppercase.
    private static let uppercaseToken = "01M3N4K7GTFG8509CK31V80MJP"

    /// Crockford base-32 is case-insensitive. Thus a completion token in
    /// lowercase and a completion token in uppercase are both tokens, and the
    /// read gives each one with no change of case.
    @Test(
        "A completion token is extracted in each spelling",
        arguments: [lowercaseToken, uppercaseToken]
    )
    func completionTokenIsExtracted(token: String) {
        let output = #"{"status":"pending","completionToken":"\#(token)"}"#

        #expect(ScriptedTranscriptText.completionToken(in: output) == token)
    }
}
