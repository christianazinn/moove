import Foundation
import Testing
@testable import MooveKit

@Suite struct ServiceConfigTests {
    @Test func prefersTheAnnouncedUploadURL() {
        let c = ServiceConfig(values: ["upload_base_url": "https://candidate-hundred-wiring-simpsons.trycloudflare.com"])
        let fallback = URL(string: "http://localhost:8787")
        #expect(c.uploadBaseURL(fallback: fallback)?.host == "candidate-hundred-wiring-simpsons.trycloudflare.com")
    }

    @Test func fallsBackWhenMissingOrInvalid() {
        let fallback = URL(string: "http://localhost:8787")
        #expect(ServiceConfig().uploadBaseURL(fallback: fallback) == fallback)
        #expect(ServiceConfig(values: ["upload_base_url": ""]).uploadBaseURL(fallback: fallback) == fallback)
        #expect(ServiceConfig(values: ["upload_base_url": "ftp://x"]).uploadBaseURL(fallback: fallback) == fallback)
        #expect(ServiceConfig(values: ["upload_base_url": "not a url"]).uploadBaseURL(fallback: fallback) == fallback)
    }

    @Test func parsesWorkerStatus() {
        let c = ServiceConfig(values: ["worker_version": "878eead", "worker_started_at": "2026-10-24T09:00:57.123Z"])
        #expect(c.workerVersion == "878eead")
        #expect(c.workerStartedAt != nil)
        #expect(ServiceConfig(values: ["worker_started_at": "2026-10-24T09:00:57Z"]).workerStartedAt != nil)
        #expect(ServiceConfig(values: ["worker_version": ""]).workerVersion == nil)
    }
}
