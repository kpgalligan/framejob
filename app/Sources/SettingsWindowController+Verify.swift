import AppKit

/// Settings' Verify button and its bookkeeping: which key and region a check
/// ran against, the transcriber it holds while it runs, and whether its
/// answer still describes what the window shows. A pure move out of
/// `SettingsWindowController.swift` (#58); the stored `verifying` stays there,
/// because an extension cannot store.
extension SettingsWindowController {
    struct VerificationInput: Equatable {
        let credential: String
        let region: AssemblyAIConfiguration.Region
        let base: URL
    }

    struct Verification {
        let id: UUID
        let input: VerificationInput
        let transcriber: CloudTranscriber
    }

    func effectiveCredential(storedCredential: String?) -> String? {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let storedCredential { return storedCredential }
        guard let value = environment[AssemblyAIConfiguration.environmentKey] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func verificationInput(credential: String) throws -> VerificationInput {
        VerificationInput(
            credential: credential,
            region: AssemblyAIConfiguration.region(defaults: defaults),
            base: try AssemblyAIConfiguration.baseURL(defaults: defaults))
    }

    func updateVerifyButton(credential: String?) {
        guard let credential else {
            verifyButton?.isEnabled = false
            return
        }
        if let verifying,
            (try? verificationInput(credential: credential)) == verifying.input
        {
            verifyButton?.isEnabled = false
        } else {
            verifyButton?.isEnabled = true
        }
    }

    /// The cheapest authenticated call there is, against whatever key would
    /// be used for a real run: what is in the FIELD when somebody has typed
    /// one and not saved it yet, and the resolved credential otherwise.
    @objc func verifyClicked(_ sender: Any?) {
        verifying = nil
        guard let credential = effectiveCredential(storedCredential: store().read()) else {
            updateVerifyButton(credential: nil)
            say("No API key is set.", problem: false)
            return
        }
        let input: VerificationInput
        do {
            input = try verificationInput(credential: credential)
        } catch {
            updateVerifyButton(credential: credential)
            say(error.localizedDescription, problem: true)
            return
        }
        say("Checking…", problem: false)
        verifyButton.isEnabled = false
        // The cache directory and the media list are what a RUN needs and a
        // verify never touches; the temporary folder is the honest "nowhere".
        let transcriber = CloudTranscriber(
            client: AssemblyAIClient(base: input.base, credential: input.credential),
            cacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            media: [:])
        let id = UUID()
        verifying = Verification(id: id, input: input, transcriber: transcriber)
        transcriber.verify { [weak self] answer in
            self?.completeVerification(answer, id: id, input: input)
        }
    }

    private func completeVerification(
        _ answer: Result<Void, AssemblyAIClient.ClientError>,
        id: UUID, input: VerificationInput
    ) {
        guard verifying?.id == id else { return }
        verifying = nil
        let credential = effectiveCredential(storedCredential: store().read())
        updateVerifyButton(credential: credential)
        guard let credential,
            (try? verificationInput(credential: credential)) == input
        else {
            say("Settings changed since this check began. Verify again.", problem: false)
            return
        }
        switch answer {
        case .success:
            say("Key accepted", problem: false)
        case .failure(let error):
            say(error.localizedDescription, problem: true)
        }
    }
}
