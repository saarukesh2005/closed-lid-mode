import Foundation

/// A minimal test harness, so tests run with only the Command Line Tools
/// installed. See the comment in Package.swift for why this is not XCTest.
enum T {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\(name)")
        body()
    }

    static func expect(_ condition: Bool,
                       _ what: String,
                       file: StaticString = #file,
                       line: UInt = #line) {
        checks += 1
        if condition {
            print("  ok    \(what)")
        } else {
            let location = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
            print("  FAIL  \(what)   [\(location)]")
            failures.append("\(currentSuite) / \(what)  [\(location)]")
        }
    }

    static func equal<V: Equatable>(_ actual: V,
                                    _ expected: V,
                                    _ what: String,
                                    file: StaticString = #file,
                                    line: UInt = #line) {
        checks += 1
        if actual == expected {
            print("  ok    \(what)")
        } else {
            let location = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
            print("  FAIL  \(what)")
            print("          expected: \(expected)")
            print("          actual:   \(actual)   [\(location)]")
            failures.append("\(currentSuite) / \(what)  [\(location)]")
        }
    }

    static func report() -> Never {
        print("\n" + String(repeating: "-", count: 56))
        if failures.isEmpty {
            print("\(checks) checks passed")
            exit(0)
        }
        print("\(failures.count) of \(checks) checks FAILED:")
        for f in failures { print("  - \(f)") }
        exit(1)
    }
}
