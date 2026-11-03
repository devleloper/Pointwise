import os

/// Diagnostics for Console.app / `log stream --predicate 'subsystem == "io.github.devleloper.Pointwise"'`.
/// Logs state changes only (permissions, devices, failures), never individual input events.
enum Log {
    static let pointer = Logger(subsystem: "io.github.devleloper.Pointwise", category: "pointer")
    static let scroll = Logger(subsystem: "io.github.devleloper.Pointwise", category: "scroll")
    static let app = Logger(subsystem: "io.github.devleloper.Pointwise", category: "app")
}
