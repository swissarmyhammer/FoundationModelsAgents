import Synchronization

/// The elements that a closure of a test got, in call order.
///
/// A class, because the closure and the test hold the same record. A `Mutex`
/// guards the elements, thus the `Sendable` conformance is compiler-checked.
final class CallRecord<Element: Sendable>: Sendable {
    /// The elements.
    private let elements = Mutex<[Element]>([])

    /// The elements so far, in call order.
    var all: [Element] {
        elements.withLock { $0 }
    }

    /// Adds one element.
    ///
    /// - Parameter element: The element.
    func add(_ element: Element) {
        elements.withLock { $0.append(element) }
    }
}
