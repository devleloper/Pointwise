extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    /// NaN and infinities become `fallback`, so corrupted preferences cannot poison the math.
    func finite(or fallback: Double) -> Double {
        isFinite ? self : fallback
    }
}

extension KeyedDecodingContainer {
    /// The decoded value, or `nil` when the key is missing or holds an incompatible value.
    func value<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
