import Foundation
import Testing
@testable import MooveKit

private actor Log {
    var urls: [URL] = []
    var sleeps: [Duration] = []
    func add(_ u: URL) { urls.append(u) }
    func slept(_ d: Duration) { sleeps.append(d) }
}

@Suite struct UploadRetryTests {
    let a = URL(string: "https://old-tunnel.example")!
    let b = URL(string: "https://new-tunnel.example")!

    @Test func whichFailuresRetry() {
        for code in [429, 408, 500, 502, 503, 504] {
            #expect(UploadRetryPolicy.isTransient(.status(code, retryAfter: nil)), "\(code)")
        }
        for code in [400, 401, 403, 404, 413, 507] {
            #expect(!UploadRetryPolicy.isTransient(.status(code, retryAfter: nil)), "\(code)")
        }
        #expect(UploadRetryPolicy.isTransient(.network("timed out")))
        #expect(UploadRetryPolicy.isTransient(.noServer))
        #expect(!UploadRetryPolicy.isTransient(.badResponse))
    }

    @Test func backsOffExponentiallyAndHonorsRetryAfter() {
        let p = UploadRetryPolicy(maxAttempts: 6, baseDelay: .seconds(1), maxDelay: .seconds(15))
        #expect([1, 2, 3, 4, 5].map { p.delay(after: $0) } == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)])
        #expect(p.delay(after: 1, retryAfter: 5) == .seconds(5))
        #expect(p.delay(after: 1, retryAfter: 600) == .seconds(15))
    }

    @Test func retriesTransientFailuresAndRereadsTheURL() async throws {
        let log = Log()
        let calls = Counter()
        let url: String = try await UploadRetry.run(
            policy: UploadRetryPolicy(maxAttempts: 4),
            baseURL: { await calls.value < 2 ? a : b },
            sleep: { await log.slept($0) },
            attempt: { u in
                await log.add(u)
                let n = await calls.next()
                if n == 1 { throw UploadFailure.status(429, retryAfter: nil) }
                if n == 2 { throw URLError(.networkConnectionLost) }
                return "https://cdn/photo.jpg"
            })
        #expect(url == "https://cdn/photo.jpg")
        #expect(await log.urls == [a, a, b])  // the restarted tunnel's URL is used on the third try
        #expect(await log.sleeps == [.seconds(1), .seconds(2)])
    }

    @Test func otherClientErrorsFailFast() async {
        let calls = Counter()
        await #expect(throws: UploadFailure.status(413, retryAfter: nil)) {
            let _: String = try await UploadRetry.run(baseURL: { a }, sleep: { _ in }, attempt: { _ in
                _ = await calls.next()
                throw UploadFailure.status(413, retryAfter: nil)
            })
        }
        #expect(await calls.value == 1)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let calls = Counter()
        await #expect(throws: UploadFailure.status(503, retryAfter: nil)) {
            let _: String = try await UploadRetry.run(policy: UploadRetryPolicy(maxAttempts: 3), baseURL: { a }, sleep: { _ in }, attempt: { _ in
                _ = await calls.next()
                throw UploadFailure.status(503, retryAfter: nil)
            })
        }
        #expect(await calls.value == 3)
    }

    @Test func waitsForAnAnnouncedServer() async throws {
        let calls = Counter()
        let url: String = try await UploadRetry.run(
            baseURL: { await calls.next() < 2 ? nil : a }, sleep: { _ in }, attempt: { _ in "ok" })
        #expect(url == "ok")
    }
}

private actor Counter {
    var value = 0
    func next() -> Int { value += 1; return value }
}
