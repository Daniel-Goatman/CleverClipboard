import Foundation

@main struct TypeSafeKeyTests {
    static func main() {
        var callback: ((Result<Void, Error>) -> Void)?
        var calls = 0, saves: [String] = []
        let model = TypeSafeKeyModel(verify: { key, completion in
            precondition(key == "synthetic-test-key-not-real")
            calls += 1; callback = completion; return nil
        }, save: { saves.append($0) })
        model.key = "short"; model.submit()
        precondition(calls == 0 && model.error != nil && saves.isEmpty)
        model.key = " synthetic-test-key-not-real \n"; model.submit(); model.submit()
        precondition(model.verifying && calls == 1 && saves.isEmpty)
        callback?(.failure(ClipboardError.message("TypeSafe rejected the API key. Update it from the menu.")))
        precondition(!model.verifying && model.error!.contains("rejected") && saves.isEmpty)
        model.submit()
        callback?(.failure(ClipboardError.message("Could not reach TypeSafe. Check your connection and try again.")))
        precondition(model.error!.contains("internet") && saves.isEmpty)
        model.submit(); let stale = callback; model.reset()
        stale?(.success(()))
        precondition(saves.isEmpty && !model.saved && model.key.isEmpty)
        model.key = "synthetic-test-key-not-real"; model.submit(); callback?(.success(()))
        precondition(model.saved && model.key.isEmpty && saves.count == 1)
        model.submit(); precondition(saves.count == 1)
        let failedSave = TypeSafeKeyModel(verify: { _, completion in completion(.success(())); return nil },
            save: { _ in throw ClipboardError.message("macOS could not save the TypeSafe key in Keychain.") })
        failedSave.key = "synthetic-test-key-not-real"; failedSave.submit()
        precondition(!failedSave.saved && failedSave.error!.contains("could not save"))
        print("PASS: secure key-entry state; format, rejected key, connection failure, cancellation, verify-before-save, retry and Keychain error")
    }
}
