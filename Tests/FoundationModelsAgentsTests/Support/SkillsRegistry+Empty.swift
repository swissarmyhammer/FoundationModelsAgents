import FoundationModelsSkills

extension SkillsRegistry {
    /// Makes a skills registry with no layers.
    ///
    /// Each test that needs no skill uses this one helper. Thus each empty
    /// skills registry of the test target has the same setup.
    ///
    /// - Returns: A registry that holds no skill.
    static func makeEmpty() -> SkillsRegistry {
        SkillsRegistry(roots: [], mode: .open)
    }
}
