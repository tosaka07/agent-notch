import Testing

@testable import AgentNotch

@Suite("Onboarding flow")
struct OnboardingFlowTests {
    @Test("Only the explanatory pages are counted by the progress ticks")
    func onlyTourStepsAreCounted() {
        #expect(
            OnboardingStep.tour == [.welcome, .sessions, .permissions, .questions, .usage, .connect]
        )

        for (index, step) in OnboardingStep.tour.enumerated() {
            #expect(step.tourIndex == index)
        }

        // A decision or an outcome must not advertise a position in a sequence: "6 of 8" beside
        // the consent button reads as something that can be paged past.
        for step in [OnboardingStep.consent, .installing, .ready, .blocked] {
            #expect(step.tourIndex == nil)
        }
    }

    @Test("Every step is either part of the tour or a decision, with none forgotten")
    func everyStepIsAccountedFor() {
        let decisions: Set<OnboardingStep> = [.consent, .installing, .ready, .blocked]
        #expect(Set(OnboardingStep.allCases) == Set(OnboardingStep.tour).union(decisions))
    }
}

@Suite("Onboarding localization")
struct OnboardingLocalizationTests {
    @Test("The pages added by the onboarding flow are translated")
    func onboardingStringsAreTranslated() {
        #expect(
            L("Agent Notch needs agent hooks", language: .japanese)
                == "Agent Notch の利用には hook が必要です"
        )
        #expect(L("What it does", language: .japanese) == "すること")
        #expect(L("What it does not do", language: .japanese) == "しないこと")
        #expect(L("Connected", language: .japanese) == "接続しました")
        #expect(L("Get Started", language: .japanese) == "はじめる")
        #expect(
            L("Stopped because hooks are not installed", language: .japanese)
                == "hook がないため停止しています"
        )
        #expect(L("Step \(2) of \(5)", language: .japanese) == "ステップ 2 / 5")
    }
}
