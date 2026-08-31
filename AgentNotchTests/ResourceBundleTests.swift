import Foundation
import Testing

@testable import AgentNotchCore

/// Guards the lookup that `Bundle.module` cannot perform.
///
/// The generated accessor resolves to the build directory of the machine that compiled the
/// binary, so a broken lookup passes every check on that machine and traps on the first launch
/// anywhere else. These tests assert the bundle is found and that a string actually resolves
/// out of it, which is what the fallback to `Bundle.main` would silently fail to do.
@Suite("Resource bundle lookup")
struct ResourceBundleTests {
    @Test("Core's resource bundle is found rather than falling back to the main bundle")
    func coreBundleResolves() {
        #expect(ResourceBundle.locate("AgentNotch_AgentNotchCore") != nil)
        #expect(ResourceBundle.core != Bundle.main)
    }

    @Test("A bundle that does not exist reports absence instead of trapping")
    func missingBundleIsNil() {
        #expect(ResourceBundle.locate("AgentNotch_NoSuchBundle") == nil)
    }

    @Test("Core strings resolve out of the located bundle")
    func coreStringsResolve() {
        // A key that carries a translation: were the bundle wrong, the lookup would hand back
        // the key itself and the two languages would agree.
        let english = AppLocalization.localized("By project", language: .english)
        let japanese = AppLocalization.localized("By project", language: .japanese)
        #expect(english != japanese)
    }
}
