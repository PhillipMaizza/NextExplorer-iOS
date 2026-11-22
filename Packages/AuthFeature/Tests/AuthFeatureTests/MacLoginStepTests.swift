#if os(macOS)
    @testable import AuthFeature
    import Testing

    @Suite("MacLoginStep")
    struct MacLoginStepTests {
        @Test("Code is listed only once the server asks for it")
        func visibleSteps() {
            #expect(MacLoginStep.visible(on: .server) == [.server, .logIn])
            #expect(MacLoginStep.visible(on: .credentials) == [.server, .logIn])
            #expect(MacLoginStep.visible(on: .secondFactor) == [.server, .logIn, .code])
        }

        @Test("Earlier steps are done, the page's own step is current, later ones upcoming")
        func states() {
            let current = MacLoginStep(page: .credentials)
            #expect(MacLoginStep.server.state(current: current) == .done)
            #expect(MacLoginStep.logIn.state(current: current) == .current)
            #expect(MacLoginStep.code.state(current: current) == .upcoming)
        }
    }
#endif
