import Foundation

/// Last known value plus the failure of the most recent refresh. `fail` keeps the
/// value on purpose: the panel shows stale data with an error instead of going blank.
struct Loadable<Value> {
    private(set) var value: Value?
    private(set) var error: String?

    init(value: Value? = nil) {
        self.value = value
    }

    static func failed(_ message: String) -> Loadable {
        var loadable = Loadable()
        loadable.error = message
        return loadable
    }

    mutating func succeed(_ value: Value) {
        self.value = value
        error = nil
    }

    mutating func fail(_ message: String) {
        error = message
    }

    mutating func clearError() {
        error = nil
    }
}
