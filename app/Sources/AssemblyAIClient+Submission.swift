import Foundation

extension AssemblyAIClient {
    /// One paid submit. A lost or unreadable reply is resolved only from the
    /// newest account page, by the exact URL returned for this upload.
    func submit(_ request: TranscriptRequest) throws -> String {
        var post = self.request("POST", path: "/v2/transcript")
        post.setValue("application/json", forHTTPHeaderField: "content-type")
        post.httpBody = try JSONEncoder().encode(request)
        let reply = send(post)
        if let failure = classify(reply) {
            switch failure {
            case .noNetwork, .timedOut, .server, .malformed:
                return try recoverSubmission(audioURL: request.audioURL)
            default:
                throw failure
            }
        }
        if let response = try? JSONDecoder().decode(TranscriptResponse.self, from: reply.data),
            Self.isPlainIdentifier(response.id)
        {
            return response.id
        }
        return try recoverSubmission(audioURL: request.audioURL)
    }

    private struct SubmissionList: Decodable {
        let transcripts: [SubmissionListItem]
    }

    private struct SubmissionListItem: Decodable {
        let id: String
        let audioURL: String

        private enum CodingKeys: String, CodingKey {
            case id
            case audioURL = "audio_url"
        }
    }

    /// A look either establishes one safe id, asks for another bounded look,
    /// or refuses. No row is retained and no unrelated id is requested.
    private func recoverSubmission(audioURL: URL) throws -> String {
        for look in 0..<max(1, tuning.submitRecoveryAttempts) {
            if look > 0 { sleep(tuning.submitRecoveryDelay, cancel: nil) }
            var get = request("GET", path: "/v2/transcript", query: "limit=200")
            get.timeoutInterval = tuning.submitRecoveryTimeout
            let reply = send(get)
            if let failure = classify(reply) {
                if case .keyRefused(let code) = failure {
                    throw ClientError.submissionUnresolved(authenticationStatus: code)
                }
                if failure.isRetriable || failure == .malformed("the request answered nothing at all") {
                    continue
                }
                throw ClientError.submissionUnresolved(authenticationStatus: nil)
            }
            guard let page = try? JSONDecoder().decode(SubmissionList.self, from: reply.data) else {
                continue
            }
            let matching = page.transcripts.filter { $0.audioURL == audioURL.absoluteString }
            if matching.contains(where: { !Self.isPlainIdentifier($0.id) }) {
                throw ClientError.submissionUnresolved(authenticationStatus: nil)
            }
            let ids = Set(matching.map(\.id))
            if ids.count == 1, let id = ids.first { return id }
            if ids.count > 1 {
                throw ClientError.submissionUnresolved(authenticationStatus: nil)
            }
        }
        throw ClientError.submissionUnresolved(authenticationStatus: nil)
    }
}
