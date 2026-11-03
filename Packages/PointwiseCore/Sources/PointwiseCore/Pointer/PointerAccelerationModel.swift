import Foundation

// Reproduces how the macOS HID pointer filter maps mouse movement to pointer movement, so
// Pointwise can draw the curve a device really gets. Pointwise never installs curves itself:
// public APIs only allow choosing the tracking value.
//
// Behaviour follows Apple's open-source IOHIDFamily (IOHIDEventSystemPlugIns/
// IOHIDAccelerationAlgorithm.cpp and IOHIDPointerScrollFilter.cpp, tag IOHIDFamily-2238.100.59,
// Apple Public Source License 2.0). The default table values are data from that project.

/// One entry of a device's `HIDAccelCurves`, decoded from 16.16 fixed point.
public struct ParametricCurve: Equatable, Sendable {
    public var index: Double
    public var gainLinear: Double
    public var gainParabolic: Double
    public var gainCubic: Double
    public var gainQuartic: Double
    public var tangentSpeedLinear: Double
    public var tangentSpeedParabolicRoot: Double

    public init(
        index: Double, gainLinear: Double, gainParabolic: Double = 0, gainCubic: Double = 0, gainQuartic: Double = 0,
        tangentSpeedLinear: Double = 0, tangentSpeedParabolicRoot: Double = 0
    ) {
        self.index = index
        self.gainLinear = gainLinear
        self.gainParabolic = gainParabolic
        self.gainCubic = gainCubic
        self.gainQuartic = gainQuartic
        self.tangentSpeedLinear = tangentSpeedLinear
        self.tangentSpeedParabolicRoot = tangentSpeedParabolicRoot
    }

    /// Reads an IORegistry dictionary; missing keys count as zero, as in macOS.
    public init(registryEntry entry: [String: Any]) {
        func value(_ key: String) -> Double {
            (entry[key] as? NSNumber).map { HIDFixed.toDouble($0.intValue) } ?? 0
        }
        self.init(
            index: value("HIDAccelIndex"),
            gainLinear: value("HIDAccelGainLinear"),
            gainParabolic: value("HIDAccelGainParabolic"),
            gainCubic: value("HIDAccelGainCubic"),
            gainQuartic: value("HIDAccelGainQuartic"),
            tangentSpeedLinear: value("HIDAccelTangentSpeedLinear"),
            tangentSpeedParabolicRoot: value("HIDAccelTangentSpeedParabolicRoot")
        )
    }

    var hasGain: Bool {
        gainLinear != 0 || gainParabolic != 0 || gainCubic != 0 || gainQuartic != 0
    }

    func interpolated(to other: ParametricCurve, ratio r: Double) -> ParametricCurve {
        func mix(_ a: Double, _ b: Double) -> Double { a + r * (b - a) }
        return ParametricCurve(
            index: mix(index, other.index),
            gainLinear: mix(gainLinear, other.gainLinear),
            gainParabolic: mix(gainParabolic, other.gainParabolic),
            gainCubic: mix(gainCubic, other.gainCubic),
            gainQuartic: mix(gainQuartic, other.gainQuartic),
            tangentSpeedLinear: mix(tangentSpeedLinear, other.tangentSpeedLinear),
            tangentSpeedParabolicRoot: mix(tangentSpeedParabolicRoot, other.tangentSpeedParabolicRoot)
        )
    }
}

/// A `HIDPointerAccelerationTable`: piecewise-linear curves for a few acceleration values.
public struct AccelerationTable: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
    }

    public struct Entry: Equatable, Sendable {
        public var acceleration: Double
        public var points: [Point]
    }

    static let defaultSignature: UInt32 = 0x3030_3240
    static let multitouchSignature: UInt32 = 0x2A42_5355

    public let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    /// Parses the binary table format; returns `nil` for anything malformed or unknown.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        var offset = 0
        func read32() -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            defer { offset += 4 }
            return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func read16() -> UInt16? {
            guard offset + 2 <= bytes.count else { return nil }
            defer { offset += 2 }
            return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }
        func fixed() -> Double? {
            read32().map { HIDFixed.toDouble(Int(Int32(bitPattern: $0))) }
        }

        guard read32() != nil, let signature = read32()?.byteSwapped,
              signature == Self.defaultSignature || signature == Self.multitouchSignature,
              let count = read16(), count > 0 else { return nil }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard let acceleration = fixed(), let pointCount = read16(), pointCount > 0 else { return nil }
            var points: [Point] = []
            for _ in 0..<pointCount {
                guard let x = fixed(), let y = fixed() else { return nil }
                points.append(Point(x: x, y: y))
            }
            entries.append(Entry(acceleration: acceleration, points: points))
        }
        self.entries = entries
    }

    /// The table macOS uses for mice that publish neither curves nor a table of their own.
    public static let macOSDefault = AccelerationTable(entries: [
        Entry(acceleration: 0, points: [Point(x: 1, y: 1)]),
        Entry(acceleration: 1, points: [
            Point(x: HIDFixed.toDouble(0x0000_713B), y: 0.375),
            Point(x: HIDFixed.toDouble(0x0004_4EC5), y: 16.5),
            Point(x: 12, y: 95),
            Point(x: HIDFixed.toDouble(0x0016_EC4F), y: 139),
            Point(x: HIDFixed.toDouble(0x001D_3B14), y: 148.5),
            Point(x: HIDFixed.toDouble(0x0022_7627), y: 150),
            Point(x: HIDFixed.toDouble(0x0024_6276), y: 150),
            Point(x: 38, y: 150),
            Point(x: 40, y: 150),
        ]),
    ])
}

/// How macOS accelerates a particular mouse.
public enum PointerAccelerationModel: Equatable, Sendable {
    case parametric([ParametricCurve])
    case table(AccelerationTable)

    /// Same precedence as macOS: the device's curves, else its table, else the default table.
    public init(curves: [ParametricCurve], table: AccelerationTable?) {
        if curves.contains(where: \.hasGain) {
            self = .parametric(curves)
        } else {
            self = .table(table ?? .macOSDefault)
        }
    }

    /// The transfer function for a tracking value; negative values mean "no acceleration".
    /// `resolution` is the device's `HIDPointerResolution` in counts per inch (400 when unknown).
    /// `linearScaling` is macOS's own "Pointer acceleration" switch being off
    /// (`HIDUseLinearScalingMouseAcceleration`): the tracking value then multiplies movement directly.
    public func transfer(acceleration: Double, resolution: Double = PointerTransfer.defaultResolution, linearScaling: Bool = false) -> PointerTransfer {
        let resolution = resolution > 0 && resolution.isFinite ? resolution : PointerTransfer.defaultResolution
        guard acceleration >= 0, acceleration.isFinite else { return PointerTransfer(kind: .raw) }
        if linearScaling {
            // Zero would stop the pointer, so macOS uses a small minimum instead.
            return PointerTransfer(kind: .linear(acceleration > 0 ? acceleration : PointerTransfer.linearMinimum))
        }
        switch self {
        case .parametric(let curves):
            guard let curve = Self.select(curves, acceleration) else { return PointerTransfer(kind: .raw) }
            return PointerTransfer(kind: .parametric(ParametricSegments(curve: curve, deviceScale: resolution / PointerTransfer.frameRate)))
        case .table(let table):
            return PointerTransfer(kind: .table(Self.segments(table, acceleration, deviceScale: resolution / PointerTransfer.frameRate)))
        }
    }

    // MARK: Parametric

    private static func select(_ curves: [ParametricCurve], _ acceleration: Double) -> ParametricCurve? {
        // macOS records the position in the unfiltered list but indexes the filtered one;
        // kept for fidelity, it only matters when a curve has no gain at all.
        var valid: [ParametricCurve] = []
        var current = 0
        for (position, curve) in curves.enumerated() where curve.hasGain {
            valid.append(curve)
            if acceleration >= curve.index { current = position }
        }
        guard !valid.isEmpty else { return nil }
        current = min(current, valid.count - 1)
        let low = valid[current]
        // Above the last curve macOS clamps; there is no extrapolation.
        guard low.index < acceleration, current + 1 < valid.count else { return low }
        let high = valid[current + 1]
        return low.interpolated(to: high, ratio: (acceleration - low.index) / (high.index - low.index))
    }

    // MARK: Table

    private static func segments(_ table: AccelerationTable, _ acceleration: Double, deviceScale: Double) -> [TableSegment] {
        guard var high = table.entries.first else { return [] }
        var low = high
        for entry in table.entries {
            low = high
            high = entry
            if acceleration <= entry.acceleration {
                if acceleration == entry.acceleration { low = high }
                break
            }
        }

        var points: [AccelerationTable.Point] = []
        if low == high || acceleration > high.acceleration {
            // Above the last entry macOS scales its curve linearly.
            let scale = (acceleration + 1) / (high.acceleration + 1)
            points = high.points.map { .init(x: $0.x, y: $0.y * scale) }
        } else {
            let ratio = (acceleration - low.acceleration) / (high.acceleration - low.acceleration)
            points = interpolate(low.points, toward: high.points, ratio: ratio)
                + interpolate(high.points, toward: low.points, ratio: ratio)
        }
        // macOS keeps the points in a set ordered by x; the first point for an x wins.
        var seen = Set<Double>()
        points = points.filter { seen.insert($0.x).inserted }.sorted { $0.x < $1.x }

        var segments: [TableSegment] = []
        var previous = AccelerationTable.Point(x: 0, y: 0)
        for point in points {
            let next = AccelerationTable.Point(x: point.x * deviceScale, y: point.y * PointerTransfer.cursorScale)
            guard next.x != previous.x else { continue }
            let slope = (next.y - previous.y) / (next.x - previous.x)
            segments.append(TableSegment(slope: slope, intercept: next.y - slope * next.x, end: next.x))
            previous = next
        }
        return segments
    }

    /// Moves each point of `curve` toward the line of `other` at the same x. Like macOS this is
    /// not a symmetric lerp: it starts from the lower of the two values.
    private static func interpolate(_ curve: [AccelerationTable.Point], toward other: [AccelerationTable.Point], ratio: Double) -> [AccelerationTable.Point] {
        guard !other.isEmpty else { return [] }
        var index = 0
        var start = AccelerationTable.Point(x: 0, y: 0)
        var end = other[0]
        return curve.map { point in
            while point.x > end.x, index < other.count - 1 {
                start = end
                index += 1
                end = other[index]
            }
            let slope = (end.y - start.y) / (end.x - start.x)
            let line = point.x * slope + (end.y - slope * end.x)
            return .init(x: point.x, y: min(point.y, line) + abs(point.y - line) * ratio)
        }
    }
}

struct TableSegment: Equatable, Sendable {
    let slope: Double
    let intercept: Double
    let end: Double
}

struct ParametricSegments: Equatable, Sendable {
    let curve: ParametricCurve
    let deviceScale: Double
    private var linearEnd = Double.greatestFiniteMagnitude
    private var rootEnd = Double.greatestFiniteMagnitude
    private var linearSlope = 0.0
    private var linearIntercept = 0.0
    private var rootSlope = 0.0
    private var rootIntercept = 0.0
    private var hasLinearSegment = false

    init(curve: ParametricCurve, deviceScale: Double) {
        self.curve = curve
        self.deviceScale = deviceScale
        let linear = curve.tangentSpeedLinear
        let root = curve.tangentSpeedParabolicRoot
        if linear != 0 {
            linearSlope = derivative(linear)
            linearIntercept = polynomial(linear) - linearSlope * linear
            linearEnd = linear
            hasLinearSegment = true
            if root != 0 {
                let y = linearSlope * root + linearIntercept
                rootSlope = 2 * y * linearSlope
                rootIntercept = y * y - rootSlope * root
                rootEnd = root
            }
        } else if root != 0 {
            rootSlope = derivative(root)
            rootIntercept = pow(polynomial(root), 2) - rootSlope * root
            linearEnd = root
        }
    }

    /// `GL·x + (GP·x)² + (GC·x)³ + (GQ·x)⁴`; the gains are applied inside the powers.
    private func polynomial(_ x: Double) -> Double {
        curve.gainLinear * x + pow(curve.gainParabolic * x, 2) + pow(curve.gainCubic * x, 3) + pow(curve.gainQuartic * x, 4)
    }

    private func derivative(_ x: Double) -> Double {
        curve.gainLinear + 2 * x * pow(curve.gainParabolic, 2) + 3 * x * x * pow(curve.gainCubic, 3) + 4 * pow(x, 3) * pow(curve.gainQuartic, 4)
    }

    func output(_ counts: Double) -> Double {
        let x = counts / deviceScale
        let y: Double
        if x <= linearEnd {
            y = polynomial(x)
        } else if x <= rootEnd, hasLinearSegment {
            y = linearSlope * x + linearIntercept
        } else {
            y = (rootSlope * x + rootIntercept).squareRoot()
        }
        return y * PointerTransfer.cursorScale
    }
}

/// Pointer movement for a given mouse movement, both per HID report.
public struct PointerTransfer: Equatable, Sendable {
    /// Counts per inch macOS assumes when a device does not report its resolution.
    public static let defaultResolution = 400.0
    static let frameRate = 67.0
    static let cursorScale = 96.0 / 67.0
    /// `HIDPointerAccelerationMinimum` as published on this generation of macOS (6553 / 65536).
    static let linearMinimum = 0.1

    enum Kind: Equatable, Sendable {
        /// Acceleration off: one count moves one point.
        case raw
        /// macOS linear scaling: counts times a factor.
        case linear(Double)
        case parametric(ParametricSegments)
        case table([TableSegment])
    }

    let kind: Kind

    /// Points the pointer moves for `counts` of mouse movement along one axis.
    public func output(forCounts counts: Double) -> Double {
        guard counts > 0, counts.isFinite else { return 0 }
        switch kind {
        case .raw:
            return counts
        case .linear(let factor):
            return counts * factor
        case .parametric(let segments):
            return segments.output(counts)
        case .table(let segments):
            guard var segment = segments.first else { return counts }
            for candidate in segments {
                segment = candidate
                if counts <= candidate.end { break }
            }
            return segment.slope * counts + segment.intercept
        }
    }

    /// Pointer points per mouse count at `counts`: the slope a user feels as speed.
    public func gain(atCounts counts: Double) -> Double {
        counts > 0 ? output(forCounts: counts) / counts : 0
    }
}
