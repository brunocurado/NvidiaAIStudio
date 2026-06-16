enum OfficeAgentState: Equatable {
    case idle
    case working
    case speaking
    case debating
    case waiting(for: String)

    static func == (lhs: OfficeAgentState, rhs: OfficeAgentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.working, .working), (.speaking, .speaking), (.debating, .debating):
            return true
        case (.waiting(let a), .waiting(let b)):
            return a == b
        default:
            return false
        }
    }
}
