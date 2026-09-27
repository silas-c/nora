import Foundation
import Testing
@testable import NoraCore

@Suite("Accessibility design constraints")
struct DesignTests {
    @Test(arguments: TileCatalog.all)
    func tileTextMeetsAAAContrast(tile: TileSpec) {
        // White text and symbols on every tile: WCAG 1.4.6 (AAA) requires 7:1.
        #expect(WCAG.contrast(tile.color, 0xFFFFFF) >= 7.0, "\(tile.title) is \(WCAG.contrast(tile.color, 0xFFFFFF)):1")
    }

    @Test func statusColorsMeetAAContrastInBothAppearances() {
        for pair in Palette.all {
            #expect(WCAG.contrast(pair.light, Palette.lightBackground) >= 4.5)
            #expect(WCAG.contrast(pair.dark, Palette.darkBackground) >= 4.5)
        }
    }

    @Test func contrastMatchesKnownValues() {
        #expect(abs(WCAG.contrast(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(WCAG.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01)
    }

    @Test func homeGridStaysSmallEnoughToScan() {
        #expect(TileCatalog.home.count == 6)
        #expect(TileCatalog.scanRows.flatMap { $0 } == TileCatalog.all)
        #expect(Set(TileCatalog.all.map(\.intent)).count == TileCatalog.all.count)
        #expect(TileCatalog.home.first?.intent == "OPEN_SCHOOL")
    }

    @Test func repairRanksTyposAndSynonyms() {
        #expect(Repair.suggestions(for: "open canvs").first?.intent == "OPEN_SCHOOL")
        #expect(Repair.suggestions(for: "puppy pictures").first?.intent == "OPEN_DOG_PHOTOS")
        #expect(Repair.suggestions(for: "my documents").first?.intent == "OPEN_FINDER")
        #expect(Set(Repair.suggestions(for: "zoom").prefix(2).map(\.intent)) == ["ZOOM_IN", "ZOOM_OUT"])
    }

    @Test func repairFallsBackToTheAgentsOwnExamples() {
        #expect(Repair.suggestions(for: "open my messages").map(\.intent) == Vocabulary.fallbackIntents)
        #expect(Repair.suggestions(for: "").count == 3)
    }

    @Test func aliasesNormalizeLikeTheRouter() {
        let aliases = [Alias(phrase: "My school thing", intent: "OPEN_SCHOOL"), Alias(phrase: "junk", intent: "NOT_A_TILE")]
        #expect(AliasResolver.intent(for: "  please my SCHOOL   thing! ", aliases: aliases) == "OPEN_SCHOOL")
        #expect(AliasResolver.intent(for: "junk", aliases: aliases) == nil, "Aliases may only point at real tiles")
        #expect(AliasResolver.intent(for: "school", aliases: aliases) == nil)
    }

    @Test func confirmationHeadlineDropsTheRawJSON() {
        let prompt = ConfirmationRequest(id: "c", message: #"Delete everything Action: {"type":"launch_app"}"#,
                                         action: ComputerAction(type: "launch_app", app: "X"), risk: .destructive, expiresAt: .now)
        #expect(ActionDescriber.headline(prompt) == "Delete everything")
        #expect(ActionDescriber.describe(prompt.action) == "Open the app “X”")
        #expect(ActionDescriber.describe(ComputerAction(type: "keypress", key: "+", modifiers: ["CMD"])) == "Press Command + Plus")
    }
}

@Suite("Interaction cost")
struct InteractionCostTests {
    @Test func canvasBaselineFollowsTheKeystrokeLevelModel() throws {
        let manual = try #require(InteractionCost.baseline(for: "OPEN_SCHOOL"))
        #expect(manual.actions == 20)
        #expect(abs(manual.seconds - 10.74) < 0.001)
        #expect(abs(KLM.seconds(InteractionCost.tileOperators) - 2.65) < 0.001)
    }

    @Test func appLaunchesDoNotClaimSavings() throws {
        let manual = try #require(InteractionCost.baseline(for: "OPEN_FINDER"))
        #expect(manual.actions == 1)
        #expect(manual.note != nil)
    }

    @Test func tallyAccumulatesOnlyKnownTasks() {
        var tally = SessionTally()
        tally.record(intent: "OPEN_SCHOOL", noraOperators: InteractionCost.tileOperators, noraActions: 1, agentSeconds: 0.2)
        tally.record(intent: "SOMETHING_ELSE", noraOperators: InteractionCost.tileOperators, noraActions: 1, agentSeconds: 0.2)
        #expect(tally.tasks == 1)
        #expect(tally.actionsSaved == 19)
        #expect(abs(tally.secondsSaved - 8.09) < 0.001)
    }

    @Test func intentEstimatorMirrorsTheRouter() {
        #expect(IntentEstimator.intent(forText: "Please open my schoolwork in Microsoft Edge.") == "OPEN_SCHOOL")
        #expect(IntentEstimator.intent(forText: "Open Canvas on Microsoft edge") == "OPEN_SCHOOL")
        #expect(IntentEstimator.intent(forText: "open canvas and go to my courses") == "OPEN_COURSES")
        #expect(IntentEstimator.intent(forText: "Show me dog pictures!") == "OPEN_DOG_PHOTOS")
        #expect(IntentEstimator.intent(forText: "open canvas now") == nil)
    }

    @Test func evaluationCountsReformulationsBeforeSuccess() {
        var log = EvaluationLog()
        let start = Date(timeIntervalSince1970: 0)
        func request(_ outcome: Outcome) -> CompletedRequest {
            CompletedRequest(input: .text("x"), startedAt: start, finishedAt: start.addingTimeInterval(1.5), outcome: outcome, message: "")
        }
        log.record(request(.notUnderstood), modality: "text", request: "open my canvs", intent: nil, noraActions: 14)
        log.record(request(.notUnderstood), modality: "text", request: "canvas pls", intent: nil, noraActions: 11)
        let success = log.record(request(.succeeded), modality: "repair", request: "Open Canvas, with, \"quotes\"", intent: "OPEN_SCHOOL", noraActions: 1)
        #expect(success.reformulations == 2)
        #expect(success.manualActions == 20)
        let csv = log.csv()
        #expect(csv.hasPrefix("id,timestamp,modality"))
        #expect(csv.contains(#""Open Canvas, with, ""quotes""""#))
        #expect(csv.split(separator: "\n").count == 4)
    }

    @Test func speechCacheKeysDependOnVoiceAndSpeed() {
        let a = SpeechPhrases.cacheKey(text: "Ready.", voiceId: "v1", speed: 1.0)
        #expect(a.count == 64)
        #expect(a == SpeechPhrases.cacheKey(text: "Ready.", voiceId: "v1", speed: 1.0))
        #expect(a != SpeechPhrases.cacheKey(text: "Ready.", voiceId: "v2", speed: 1.0))
        #expect(a != SpeechPhrases.cacheKey(text: "Ready.", voiceId: "v1", speed: 0.9))
    }
}
