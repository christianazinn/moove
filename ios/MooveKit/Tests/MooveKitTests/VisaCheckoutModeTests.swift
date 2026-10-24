import Foundation
import Testing
@testable import MooveKit

/// #191: the worker's service_config `visa_checkout` labels purchase approvals before payment.
@Suite struct VisaCheckoutModeTests {
    private func approval(_ kind: ApprovalKind) -> Approval {
        Approval(id: 1, owner: "me", kind: kind, refId: 1, amountCents: 42_999, summary: "Buy sofa", requestedAt: .now)
    }

    @Test func parsesTheAnnouncedMode() {
        #expect(ServiceConfig(values: ["visa_checkout": "simulated"]).visaCheckout == .simulated)
        #expect(ServiceConfig(values: ["visa_checkout": "sandbox"]).visaCheckout == .sandbox)
        #expect(ServiceConfig(values: ["visa_checkout": "sandbox+fallback"]).visaCheckout == .sandboxFallback)
        #expect(ServiceConfig(values: ["visa_checkout": " simulated "]).visaCheckout == .simulated)
    }

    @Test func missingOrUnknownIsNil() {
        #expect(ServiceConfig().visaCheckout == nil)
        #expect(ServiceConfig(values: ["visa_checkout": ""]).visaCheckout == nil)
        #expect(ServiceConfig(values: ["visa_checkout": "live"]).visaCheckout == nil)
    }

    @Test func purchaseTagFollowsTheMode() {
        let buy = approval(.purchase)
        #expect(buy.purchaseRailTag(.simulated) == .simulated)
        #expect(buy.purchaseRailTag(.sandbox) == .sandbox)
        // Could end up either way, so nothing before payment; the payment row says which after.
        #expect(buy.purchaseRailTag(.sandboxFallback) == nil)
        // An old worker or module that doesn't announce it: nothing extra, as before.
        #expect(buy.purchaseRailTag(nil) == nil)
        #expect(PurchaseRailTag.simulated.text == "SIMULATED")
        #expect(PurchaseRailTag.sandbox.text == "VISA SANDBOX")
        #expect(PurchaseRailTag.simulated.spoken.lowercased().contains("simulated"))
    }

    @Test func listingApprovalsNeverGetAPurchaseTag() {
        for mode in [VisaCheckoutMode?.none] + VisaCheckoutMode.allCases.map(Optional.some) {
            #expect(approval(.listing).purchaseRailTag(mode) == nil)
        }
    }

    @Test func offlineDemoReportsSimulatedSoTheSofaShowsThePill() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        var it = backend.snapshots().makeAsyncIterator()
        let snap = await it.next()!
        #expect(snap.serviceConfig.visaCheckout == .simulated)
        let sofa = try #require(snap.approvals.first { $0.kind == .purchase && $0.amountCents == 42_999 && $0.status == .pending })
        #expect(sofa.purchaseRailTag(snap.serviceConfig.visaCheckout) == .simulated)
    }
}
