import Foundation
import HymnCore

// Injectable boundaries let macOS regression tests exercise the actual app model
// without making paid API requests, accessing a real key, or touching user projects.
struct AppServices {
    var harmonyPlan: @Sendable (Score, String, String, String) async throws -> HarmonyPlan
    var arrange: @Sendable (Score, HarmonyPlan) async throws -> Score
    var loadAPIKey: () -> String
    var saveAPIKey: (String) throws -> Void

    static let live = AppServices(
        harmonyPlan: { score, request, key, model in
            try await AIClient(apiKey: key, model: model).harmony(score: score, request: request)
        },
        arrange: { score, plan in
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try Harmonizer.arrange(score, plan: plan)
            }
            return try await withTaskCancellationHandler(
                operation: { try await worker.value },
                onCancel: { worker.cancel() }
            )
        },
        loadAPIKey: { KeyStore.load() },
        saveAPIKey: { try KeyStore.save($0) }
    )
}

enum ArrangementProgress: Equatable {
    case requestingAI, harmonizing, saving

    var title: String {
        switch self {
        case .requestingAI: return "AI is planning the harmony…"
        case .harmonizing: return "Arranging and checking the voices…"
        case .saving: return "Saving your new draft…"
        }
    }
}
