import Foundation

/// What the UTC calendar month has cost, for Settings ▸ Assistant (road map
/// 13 P4, spec §11 P-4, P-7): the month an instant falls in, its title, the
/// fold of `spend.jsonl` over it, the off-main read, and the sentences the
/// pane shows.
///
/// **The month is UTC's.** The ledger's `time` is written in UTC
/// (`AssistantSpend.ledgerLine`) and P-6's budget month is UTC, so the app
/// and the proofs count one month; the title says "(UTC)". `zone` is the one
/// spelling of that zone in this file.
///
/// **The fold only sums.** It adds the dollars the helper computed and
/// counts what it could not: a line without a price is `unpriced`, never
/// $0 (P-2), and a line that is not a JSON object with a readable `time` is
/// `unreadable`. Lines of another `service` are skipped. No pricing
/// arithmetic is done here (road map 13 §2).
///
/// **The read is off main.** `read` folds on `queue`, one serial queue, and
/// answers on main; the pane shows only its latest read's answer.
enum AssistantSpendMonth {
    static let queue = DispatchQueue(label: "com.kgalligan.framejob.spend-month")
    static let zone = TimeZone.gmt
    static let note =
        "Frame Job's own estimate at LiteLLM prices, from its spend ledger. The Anthropic "
        + "Console shows what your account was billed."

    /// One month's lines, folded.
    struct Summary: Equatable {
        var dollars = 0.0
        var priced = 0
        var unpriced = 0
        var unreadable = 0
    }

    /// What the pane has to say: no ledger kept, a read under way, a
    /// month's summary, or a read that failed (its reason).
    enum Reading: Equatable {
        case noLedger, reading
        case summary(Summary)
        case failed(String)
    }

    /// The gregorian calendar month holding `instant`, in `zone`.
    static func month(containing instant: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateInterval(of: .month, for: instant)
            ?? DateInterval(start: instant, duration: 0)
    }

    /// "September 2026 (UTC)".
    static func title(_ month: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month.start) + " (UTC)"
    }

    /// The ledger's lines in `month`, folded. Pure.
    static func fold(_ data: Data, month: DateInterval) -> Summary {
        var summary = Summary()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                let entry = object as? [String: Any],
                let time = entry["time"] as? String,
                let instant = AssistantSpend.instant(time)
            else {
                summary.unreadable += 1
                continue
            }
            guard entry["service"] as? String == "anthropic" else { continue }
            guard month.start <= instant && instant < month.end else { continue }
            if let dollars = AssistantSpend.number(entry["dollars"])?.doubleValue,
                dollars.isFinite, dollars >= 0
            {
                summary.priced += 1
                summary.dollars += dollars
            } else {
                summary.unpriced += 1
            }
        }
        return summary
    }

    /// Reads and folds `ledger` on `queue`; `completion` runs on main.
    static func read(
        ledger: URL, month: DateInterval, completion: @escaping (Reading) -> Void
    ) {
        queue.async {
            let reading: Reading
            do {
                reading = .summary(fold(try Data(contentsOf: ledger), month: month))
            } catch {
                reading = .failed(error.localizedDescription)
            }
            DispatchQueue.main.async { completion(reading) }
        }
    }

    /// `$%.2f`, or `under $0.01` for a positive amount that would round to 0.
    static func amount(_ dollars: Double) -> String {
        if dollars > 0 && dollars < 0.005 { return "under $0.01" }
        return String(format: "$%.2f", dollars)
    }

    /// What Settings says for `reading` over `month`.
    static func sentence(_ reading: Reading, month: DateInterval) -> String {
        switch reading {
        case .noLedger:
            return "This launch keeps no spend ledger."
        case .reading:
            return "Reading the spend ledger…"
        case .failed(let reason):
            let bare = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            return "The spend ledger could not be read: \(bare)."
        case .summary(let summary):
            let title = title(month)
            let count = summary.priced + summary.unpriced
            let responses = "\(count) " + (count == 1 ? "response" : "responses")
            var text: String
            if count == 0 {
                text = "Nothing recorded in \(title)."
            } else if summary.unpriced == 0 {
                text = "\(title): \(amount(summary.dollars)) over \(responses)."
            } else if summary.priced == 0 {
                text = "\(title): \(responses); none could be priced."
            } else {
                text =
                    "\(title): \(responses); \(summary.unpriced) could not be priced, the rest "
                    + "came to \(amount(summary.dollars))."
            }
            if summary.unreadable > 0 {
                let lines = summary.unreadable == 1 ? "line" : "lines"
                text += " \(summary.unreadable) ledger \(lines) could not be read."
            }
            return text
        }
    }
}
