import Anthropic
import Foundation

// The price table's daily refresh (spec §11 P-1, P-5, SA-3): priceTable.ts's `refreshPrices`,
// on URLSession, with the same URL, user-agent, 30 s timeout, feed rule and write: the cache's
// missing folders made 0700, the table written to `<cache>.tmp-<pid>` and renamed over the cache
// as the last step. A cache file either helper wrote is read by the other: the JSON is the same
// table, written compact here and indented by the TypeScript.

extension PriceTables {
    /// A fresh table from the feed, written to the cache as the last step; on any failure,
    /// `current` with the problem and nothing written. Never throws.
    public static func refresh(_ current: LoadedPrices, _ o: PriceOptions) async -> LoadedPrices {
        guard let cache = o.cache, !cache.isEmpty else { return current.with(problem: "no price cache is configured") }
        guard cache.hasPrefix("/") else { return current.with(problem: "the price cache path is not absolute") }
        let feed = o.feed ?? liteLLMURL
        if let refused = feedProblem(feed) { return current.with(problem: refused) }
        guard let url = URL(string: feed) else {
            return current.with(problem: "the price feed \(feed) is neither https nor a loopback http URL")
        }

        let data: RawJSON
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: fetchTimeout)
            request.setValue(userAgent, forHTTPHeaderField: "user-agent")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = fetchTimeout
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return current.with(problem: "fetching \(feed): HTTP \(status)") }
            do {
                data = try RawJSON.parse(body)
            } catch {
                return current.with(problem: "\(feed) was rejected: not JSON: \(AgentSession.describe(error))")
            }
        } catch {
            return current.with(problem: "fetching \(feed): \(error.localizedDescription)")
        }

        let fetchedAt = isoString(o.now())
        let table: PriceTable
        switch reduceLiteLLM(data, source: feed, fetchedAt: fetchedAt) {
        case .failure(let why): return current.with(problem: "\(feed) was rejected: \(why.message)")
        case .success(let reduced): table = reduced
        }
        let fetched = LoadedPrices(table: table, source: PriceSource(kind: .fetched, asOf: fetchedAt))
        if let problem = write(table, to: cache) {
            return fetched.with(problem: "the price cache could not be written: \(problem)")
        }
        return fetched
    }

    /// Writes the table to `cache` through a temporary file beside it; the reason it could not.
    static func write(_ table: PriceTable, to cache: String) -> String? {
        let temporary = "\(cache).tmp-\(getpid())"
        var bytes = table.json.serialized()
        bytes.append(0x0A)
        do {
            let folder = URL(fileURLWithPath: cache).deletingLastPathComponent()
            // Each folder this makes is 0700; one that exists keeps its mode, as mkdirSync's does.
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try bytes.write(to: URL(fileURLWithPath: temporary))
            guard rename(temporary, cache) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return nil
        } catch {
            unlink(temporary)  // nothing is left behind
            return error.localizedDescription
        }
    }
}
