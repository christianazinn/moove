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

    @Test func refusesOriginsThatCouldLeakUploads() {
        let fallback = URL(string: "http://localhost:8787")
        for bad in ["https://moove.app@evil.example", "https://u:p@evil.example", "https://evil.example?x=1",
                    "https://evil.example/#f", "http://203.0.113.5:8787", "http://evil.example", "http://192.169.1.2"] {
            #expect(ServiceConfig(values: ["upload_base_url": bad]).uploadBaseURL(fallback: fallback) == fallback, "\(bad)")
        }
        for good in ["https://x.trycloudflare.com", "http://localhost:8787", "http://192.168.1.20:8787",
                     "http://10.0.0.5:8787", "http://172.20.1.1:8787", "http://aiden-mbp.local:8787", "http://127.0.0.1:8787"] {
            #expect(ServiceConfig(values: ["upload_base_url": good]).uploadBaseURL?.absoluteString == good)
        }
    }

    @Test func parsesWorkerStatus() {
        let c = ServiceConfig(values: ["worker_version": "878eead", "worker_started_at": "2026-10-24T09:00:57.123Z"])
        #expect(c.workerVersion == "878eead")
        #expect(c.workerStartedAt != nil)
        #expect(ServiceConfig(values: ["worker_started_at": "2026-10-24T09:00:57Z"]).workerStartedAt != nil)
        #expect(ServiceConfig(values: ["worker_version": ""]).workerVersion == nil)
    }
}
