#if os(macOS)
    import Localization

    enum MacLoginStep: Int, CaseIterable, Hashable {
        case server = 1
        case logIn
        case code

        init(page: LoginFormFeature.Page) {
            switch page {
            case .server: self = .server
            case .credentials: self = .logIn
            case .secondFactor: self = .code
            }
        }

        static func visible(on page: LoginFormFeature.Page) -> [Self] {
            page == .secondFactor ? allCases : [.server, .logIn]
        }

        var title: String {
            switch self {
            case .server: L10n.Login.stepServer
            case .logIn: L10n.Login.stepLogIn
            case .code: L10n.Login.stepCode
            }
        }

        func state(current: Self) -> MacLoginStepState {
            if rawValue < current.rawValue {
                return .done
            }
            return self == current ? .current : .upcoming
        }
    }

    enum MacLoginStepState: Equatable {
        case done
        case current
        case upcoming
    }
#endif
