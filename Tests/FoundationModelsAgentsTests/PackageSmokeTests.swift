import FoundationModelsAgents
import FoundationModelsRouterTestSupport
import MarketplaceFixtures
import Testing

/// Makes sure that the package links as the manifest declares.
///
/// The library module imports, and its namespace exists. The test target also
/// links the two test-only products: `FoundationModelsRouterTestSupport` and
/// `MarketplaceFixtures`. The library links neither of them.
@Suite("Package smoke")
struct PackageSmokeTests {
    /// The `FoundationModelsAgents` namespace is in the `FoundationModelsAgents` module.
    @Test("The namespace is in the library module")
    func namespaceIsInTheLibraryModule() {
        #expect(String(reflecting: FoundationModelsAgents.self) == "FoundationModelsAgents.FoundationModelsAgents")
    }

    /// The test target links the Router test support product.
    @Test("The test target links FoundationModelsRouterTestSupport")
    func testTargetLinksRouterTestSupport() {
        #expect(
            String(reflecting: ConcurrencyPeakObserver.self)
                == "FoundationModelsRouterTestSupport.ConcurrencyPeakObserver"
        )
    }

    /// The test target links the marketplace fixtures product.
    @Test("The test target links MarketplaceFixtures")
    func testTargetLinksMarketplaceFixtures() {
        #expect(String(reflecting: ManualClock.self) == "MarketplaceFixtures.ManualClock")
    }
}
