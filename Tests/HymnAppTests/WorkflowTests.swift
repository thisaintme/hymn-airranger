import XCTest
import Foundation
import HymnCore
@testable import HymnAIrranger

// A deliberately non-cooperative fake service: releasing a cancelled request
// lets us prove that its late result cannot overwrite a newer operation.
private actor Gate<Value: Sendable> {
    private(set) var isWaiting = false
    private var value: Value?
    private var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value {
        isWaiting = true
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: Value) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

final class WorkflowTests: XCTestCase {
    @MainActor private func fixture(services: AppServices? = nil) throws -> (AppModel, UserDefaults, URL) {
        let name = "HymnAIrrangerTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(true, forKey: "cloudEnabled")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var isolated = services ?? AppServices.live
        isolated.loadAPIKey = { "test-key-not-a-real-credential" }
        if services == nil {
            isolated.harmonyPlan = { _, _, _, _ in HarmonyPlan(summary: "Test arrangement") }
            isolated.saveAPIKey = { _ in }
        }
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        return (AppModel(folder: folder, defaults: defaults, services: isolated), defaults, folder)
    }

    @MainActor private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The expected app state was not reached")
        throw HymnError.invalid("Test state timeout")
    }

    @MainActor func testAIArrangementShowsProgressThenUnlocksAndSavesDraft() async throws {
        let gate = Gate<HarmonyPlan>()
        var services = AppServices.live
        services.harmonyPlan = { _, _, _, _ in await gate.wait() }
        let (model, _, folder) = try fixture(services: services)
        let before = model.project
        model.project.approvedID = before.currentID
        model.propose("Create a traditional arrangement", usingAI: true)
        let task = try XCTUnwrap(model.operation)
        XCTAssertTrue(model.busy)
        XCTAssertEqual(model.arrangementProgress, .requestingAI)
        XCTAssertEqual(model.score, before.current.score)
        // Re-entrant button/menu events must not launch another request.
        model.propose("Do not launch this duplicate", usingAI: true)
        await gate.release(HarmonyPlan(summary: "Gentle test harmony"))
        await task.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertNil(model.operation)
        XCTAssertEqual(model.project.revisions.count, before.revisions.count + 1)
        XCTAssertEqual(model.project.current.request, "Create a traditional arrangement")
        XCTAssertEqual(model.project.current.parentID, before.currentID)
        XCTAssertEqual(model.previousArrangementID, before.currentID)
        XCTAssertEqual(model.score.tune, before.current.score.tune)
        XCTAssertEqual(model.project.approvedID, before.currentID)
        XCTAssertFalse(model.isApproved, "A generated draft is never automatically approved")
        let saved = try Project.load(Data(contentsOf: folder.appendingPathComponent(model.project.id.uuidString + ".hymn")))
        XCTAssertEqual(saved, model.project)
        // A normal follow-up edit works immediately, without Keep/Discard.
        model.updateChoir(model.score.profile)
        XCTAssertEqual(model.project.revisions.count, before.revisions.count + 2)
        XCTAssertNil(model.previousArrangementID)
    }

    @MainActor func testLocalDraftUnlocksAndRestorePreservesNewerVersion() async throws {
        let (model, _, _) = try fixture()
        let original = model.project.current
        model.propose("First local draft", usingAI: false)
        await model.operation?.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        let generatedID = model.project.currentID
        XCTAssertNotEqual(original.id, generatedID)
        model.restorePreviousArrangement()
        XCTAssertEqual(model.project.current, original)
        XCTAssertTrue(model.project.revisions.contains { $0.id == generatedID })
        model.propose("Continue from restored version", usingAI: false)
        await model.operation?.value
        XCTAssertEqual(model.project.current.parentID, original.id)
        XCTAssertTrue(model.project.revisions.contains { $0.id == generatedID })
    }

    @MainActor func testNetworkFailureUnlocksWithoutChangingScore() async throws {
        var services = AppServices.live
        services.harmonyPlan = { _, _, _, _ in throw URLError(.timedOut) }
        let (model, _, _) = try fixture(services: services)
        let original = model.project
        model.propose("Test timeout", usingAI: true)
        await model.operation?.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertNil(model.operation)
        XCTAssertEqual(model.project, original)
        XCTAssertFalse(model.errorMessage.isEmpty)
        model.propose("Retry locally", usingAI: false)
        await model.operation?.value
        XCTAssertEqual(model.project.revisions.count, original.revisions.count + 1)
    }

    @MainActor func testHarmonyStageAndWorkerFailureUnlock() async throws {
        let gate = Gate<Bool>()
        var services = AppServices.live
        services.arrange = { _, _ in
            _ = await gate.wait()
            throw HymnError.invalid("No harmony fits these test ranges")
        }
        let (model, _, _) = try fixture(services: services)
        let original = model.project
        model.propose("Test worker", usingAI: false)
        let task = try XCTUnwrap(model.operation)
        XCTAssertEqual(model.arrangementProgress, .harmonizing)
        await gate.release(true)
        await task.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertEqual(model.project, original)
        XCTAssertTrue(model.errorMessage.contains("test ranges"))
    }

    @MainActor func testCancellationUnlocksAndLateResultCannotClearNewRequest() async throws {
        let oldGate = Gate<HarmonyPlan>(), newGate = Gate<HarmonyPlan>()
        var services = AppServices.live
        services.harmonyPlan = { _, request, _, _ in
            if request == "old" { return await oldGate.wait() }
            return await newGate.wait()
        }
        let (model, _, _) = try fixture(services: services)
        let original = model.project
        model.propose("old", usingAI: true)
        let oldTask = try XCTUnwrap(model.operation)
        try await eventually { await oldGate.isWaiting }
        model.cancelOperation()
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertNil(model.operation)
        model.propose("new", usingAI: true)
        let newTask = try XCTUnwrap(model.operation)
        try await eventually { await newGate.isWaiting }
        await oldGate.release(HarmonyPlan(summary: "Stale response"))
        await oldTask.value
        XCTAssertTrue(model.busy, "The old task must not unlock the new request")
        XCTAssertEqual(model.arrangementProgress, .requestingAI)
        XCTAssertEqual(model.project, original)
        await newGate.release(HarmonyPlan(summary: "Fresh response"))
        await newTask.value
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.project.revisions.count, original.revisions.count + 1)
        XCTAssertEqual(model.project.current.request, "new")
        XCTAssertTrue(model.errorMessage.isEmpty)
    }

    @MainActor func testCancellingDuringHarmonyIgnoresLateWorker() async throws {
        let gate = Gate<Bool>()
        var services = AppServices.live
        services.arrange = { score, _ in
            _ = await gate.wait()
            return score
        }
        let (model, _, _) = try fixture(services: services)
        let original = model.project
        model.propose("Cancel worker", usingAI: false)
        let task = try XCTUnwrap(model.operation)
        XCTAssertEqual(model.arrangementProgress, .harmonizing)
        try await eventually { await gate.isWaiting }
        model.cancelOperation()
        XCTAssertFalse(model.busy)
        await gate.release(true)
        await task.value
        XCTAssertEqual(model.project, original)
        XCTAssertNil(model.arrangementProgress)
    }

    @MainActor func testProjectChangedDuringRequestIsNotOverwritten() async throws {
        let gate = Gate<HarmonyPlan>()
        var services = AppServices.live
        services.harmonyPlan = { _, _, _, _ in await gate.wait() }
        let (model, _, _) = try fixture(services: services)
        model.propose("Old project", usingAI: true)
        let task = try XCTUnwrap(model.operation)
        let replacement = try Demo.project()
        model.project = replacement
        await gate.release(HarmonyPlan())
        await task.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertEqual(model.project, replacement)
        XCTAssertFalse(model.errorMessage.isEmpty)
    }

    @MainActor func testInvalidArrangementDoesNotReplaceLockedMelody() async throws {
        var services = AppServices.live
        services.arrange = { score, _ in
            var invalid = score
            invalid.tune.melody[0].pitch = 0
            return invalid
        }
        let (model, _, _) = try fixture(services: services)
        let original = model.project
        model.propose("Invalid test response", usingAI: false)
        await model.operation?.value
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.arrangementProgress)
        XCTAssertEqual(model.project, original)
        XCTAssertTrue(model.errorMessage.contains("locked melody"))
    }

    @MainActor func testSettingsSaveClosesOnlyAfterSuccessDespiteUnrelatedError() async throws {
        var savedKey = ""
        var services = AppServices.live
        services.saveAPIKey = { savedKey = $0 }
        let (model, defaults, _) = try fixture(services: services)
        model.errorMessage = "An unrelated earlier import failed"
        let form = SettingsForm(model: model)
        form.apiKey = "  example-test-key  "
        form.modelID = "  example-model  "
        form.cloudEnabled = true
        var closes = 0
        XCTAssertTrue(form.save { closes += 1 })
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(savedKey, "example-test-key")
        XCTAssertEqual(model.modelID, "example-model")
        XCTAssertEqual(defaults.string(forKey: "apiModel"), "example-model")
        XCTAssertTrue(form.errorMessage.isEmpty)
    }

    @MainActor func testSettingsFailureKeepsWindowOpenAndPreviousSettings() async throws {
        var services = AppServices.live
        services.saveAPIKey = { _ in throw HymnError.invalid("Test Keychain failure") }
        let (model, defaults, _) = try fixture(services: services)
        let originalModel = model.modelID, originalCloud = model.cloudEnabled
        let form = SettingsForm(model: model)
        form.modelID = "another-model"
        form.cloudEnabled = false
        var closed = false
        XCTAssertFalse(form.save { closed = true })
        XCTAssertFalse(closed)
        XCTAssertEqual(model.modelID, originalModel)
        XCTAssertEqual(model.cloudEnabled, originalCloud)
        XCTAssertNil(defaults.string(forKey: "apiModel"))
        XCTAssertTrue(defaults.bool(forKey: "cloudEnabled"))
        XCTAssertTrue(form.errorMessage.contains("Keychain"))
    }

    @MainActor func testSettingsValidationKeepsWindowOpenUntilCorrected() async throws {
        let (model, _, _) = try fixture()
        let form = SettingsForm(model: model)
        form.apiKey = "   "
        form.cloudEnabled = true
        var closes = 0
        XCTAssertFalse(form.save { closes += 1 })
        XCTAssertEqual(closes, 0)
        XCTAssertFalse(form.errorMessage.isEmpty)
        form.apiKey = "test-key"
        XCTAssertTrue(form.save { closes += 1 })
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(form.errorMessage.isEmpty)
    }

    @MainActor func testUnsavedSettingsDoNotChangeActiveConfiguration() async throws {
        let (model, _, _) = try fixture()
        let originalModel = model.modelID, originalCloud = model.cloudEnabled
        let form = SettingsForm(model: model)
        form.modelID = "not-saved"
        form.cloudEnabled.toggle()
        XCTAssertEqual(model.modelID, originalModel)
        XCTAssertEqual(model.cloudEnabled, originalCloud)
        form.reload() // Reopening after Cancel restores the saved values.
        XCTAssertEqual(form.modelID, originalModel)
        XCTAssertEqual(form.cloudEnabled, originalCloud)
    }
}
