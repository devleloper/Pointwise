import Foundation
import Testing
@testable import PointwiseCore

// Expected values come from an independent Python model of IOHIDFamily-2238.100.59 that
// reproduced the live `hidutil` segment dumps of the same devices on macOS 27.2.

/// `HIDAccelCurves` of an EPOMAKER TH80 keyboard's pointer interface, read from IORegistry.
private let th80Curves: [ParametricCurve] = [
    [0, 65536, 0, 0, 524288, 0],
    [8192, 60293, 26214, 5243, 537395, 1245184],
    [32768, 60948, 36045, 6554, 543949, 1179648],
    [45056, 61604, 46531, 7864, 550502, 1114112],
    [57344, 62259, 57672, 9830, 557056, 1048576],
    [65536, 62915, 69468, 11796, 563610, 983040],
    [98304, 63570, 81920, 14418, 570163, 917504],
    [131072, 64225, 95027, 17695, 576717, 851968],
    [163840, 64881, 108790, 21627, 583270, 786432],
    [196608, 65536, 123208, 26214, 589824, 786432],
].map { values in
    ParametricCurve(registryEntry: [
        "HIDAccelIndex": values[0], "HIDAccelGainLinear": values[1], "HIDAccelGainParabolic": values[2],
        "HIDAccelGainCubic": values[3], "HIDAccelTangentSpeedLinear": values[4], "HIDAccelTangentSpeedParabolicRoot": values[5],
    ])
}

/// `defaultAccelTable` from IOHIDPointerScrollFilter.cpp.
private let defaultTableBytes: [UInt8] = [
    0x00, 0x00, 0x80, 0x00, 0x40, 0x32, 0x30, 0x30, 0x00, 0x02, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
    0x00, 0x01, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x71, 0x3B, 0x00, 0x00,
    0x60, 0x00, 0x00, 0x04, 0x4E, 0xC5, 0x00, 0x10, 0x80, 0x00, 0x00, 0x0C,
    0x00, 0x00, 0x00, 0x5F, 0x00, 0x00, 0x00, 0x16, 0xEC, 0x4F, 0x00, 0x8B,
    0x00, 0x00, 0x00, 0x1D, 0x3B, 0x14, 0x00, 0x94, 0x80, 0x00, 0x00, 0x22,
    0x76, 0x27, 0x00, 0x96, 0x00, 0x00, 0x00, 0x24, 0x62, 0x76, 0x00, 0x96,
    0x00, 0x00, 0x00, 0x26, 0x00, 0x00, 0x00, 0x96, 0x00, 0x00, 0x00, 0x28,
    0x00, 0x00, 0x00, 0x96, 0x00, 0x00,
]

private let speeds: [Double] = [1, 5, 20, 60, 100, 250]

private func expectOutputs(_ transfer: PointerTransfer, _ expected: [Double], tolerance: Double = 1e-5) {
    for (speed, value) in zip(speeds, expected) {
        #expect(abs(transfer.output(forCounts: speed) - value) < tolerance, "at \(speed) counts")
    }
}

struct AccelerationTableTests {
    @Test func defaultTableMatchesTheBytesInIOHIDFamily() {
        #expect(AccelerationTable(data: Data(defaultTableBytes)) == .macOSDefault)
    }

    @Test func rejectsMalformedTables() {
        #expect(AccelerationTable(data: Data()) == nil)
        #expect(AccelerationTable(data: Data(defaultTableBytes.prefix(40))) == nil)
        var wrongSignature = defaultTableBytes
        wrongSignature[4] = 0
        #expect(AccelerationTable(data: Data(wrongSignature)) == nil)
    }
}

struct PointerAccelerationModelTests {
    @Test func precedenceFollowsMacOS() {
        #expect(PointerAccelerationModel(curves: th80Curves, table: nil) == .parametric(th80Curves))
        #expect(PointerAccelerationModel(curves: [], table: nil) == .table(.macOSDefault))
        let gainless = ParametricCurve(index: 0, gainLinear: 0)
        #expect(PointerAccelerationModel(curves: [gainless], table: nil) == .table(.macOSDefault))
    }

    @Test func zeroIsLinearAtDefaultResolution() {
        for model in [PointerAccelerationModel.parametric(th80Curves), .table(.macOSDefault)] {
            let transfer = model.transfer(acceleration: 0)
            for speed in speeds {
                #expect(abs(transfer.gain(atCounts: speed) - 0.24) < 1e-9)
            }
        }
    }

    @Test func negativeMeansRawCounts() {
        let transfer = PointerAccelerationModel.parametric(th80Curves).transfer(acceleration: -1)
        #expect(transfer.output(forCounts: 37) == 37)
        #expect(transfer.output(forCounts: 0) == 0)
    }

    @Test func linearScalingMultipliesByTheTrackingValue() {
        for model in [PointerAccelerationModel.parametric(th80Curves), .table(.macOSDefault)] {
            #expect(model.transfer(acceleration: 1.5, linearScaling: true).output(forCounts: 10) == 15)
            #expect(abs(model.transfer(acceleration: 0, linearScaling: true).output(forCounts: 10) - 1) < 1e-12)
            // Turning acceleration off in Pointwise still means raw counts.
            #expect(model.transfer(acceleration: -1, linearScaling: true).output(forCounts: 10) == 10)
        }
    }

    @Test func parametricGainsMatchReference() {
        let model = PointerAccelerationModel.parametric(th80Curves)
        let gains: [(Double, [Double])] = [
            (0.6875, [0.33, 0.64, 1.45, 1.81, 1.61]),
            (3, [0.96, 3.25, 10.18, 12.68, 10.14]),
        ]
        for (acceleration, expected) in gains {
            let transfer = model.transfer(acceleration: acceleration)
            for (speed, gain) in zip(speeds.dropFirst(), expected) {
                #expect(abs(transfer.gain(atCounts: speed) - gain) < 0.005, "a=\(acceleration) v=\(speed)")
            }
        }
    }

    @Test func parametricInterpolatesBetweenCurves() {
        let model = PointerAccelerationModel.parametric(th80Curves)
        expectOutputs(model.transfer(acceleration: 0.3), [0.230804, 1.332198, 8.028832, 45.203081, 90.452504, 206.932125])
        expectOutputs(model.transfer(acceleration: 1.5), [0.295684, 2.743276, 30.354602, 250.736588, 530.758541, 1102.104444])
    }

    @Test func parametricClampsAboveLastCurve() {
        let model = PointerAccelerationModel.parametric(th80Curves)
        #expect(model.transfer(acceleration: 5) == model.transfer(acceleration: 3))
    }

    @Test func tableMatchesReference() {
        let model = PointerAccelerationModel.table(.macOSDefault)
        expectOutputs(model.transfer(acceleration: 0.3), [0.214435, 1.698608, 8.735218, 42.361897, 65.860498, 106.477612])
        expectOutputs(model.transfer(acceleration: 0.6875), [0.228587, 2.378939, 13.818209, 78.479348, 119.930307, 166.511194])
        expectOutputs(model.transfer(acceleration: 2), [0.305218, 4.349240, 26.876092, 161.409486, 245.302488, 322.388060])
    }

    @Test func tableScalesAboveLastEntry() {
        let transfer = PointerAccelerationModel.table(.macOSDefault).transfer(acceleration: 5)
        for (speed, gain) in zip(speeds.dropFirst(), [1.74, 2.69, 5.38, 4.91, 2.58]) {
            #expect(abs(transfer.gain(atCounts: speed) - gain) < 0.005)
        }
        // Saturates at 150 · 96/67 · (5 + 1) / 2 points per report.
        #expect(abs(transfer.output(forCounts: 1000) - 644.776) < 0.01)
    }

    @Test func resolutionShiftsTheCurve() {
        let model = PointerAccelerationModel.parametric(th80Curves)
        let at400 = model.transfer(acceleration: 1, resolution: 400)
        let at1600 = model.transfer(acceleration: 1, resolution: 1600)
        // The same hand movement produces four times the counts at four times the resolution,
        // and macOS normalizes by resolution, so the pointer moves the same distance.
        #expect(abs(at1600.output(forCounts: 80) - at400.output(forCounts: 20)) < 1e-9)
        #expect(at1600.gain(atCounts: 40) < at400.gain(atCounts: 40))
        #expect(model.transfer(acceleration: 1, resolution: 0) == model.transfer(acceleration: 1))
    }

    @Test func outputIsMonotonic() {
        for model in [PointerAccelerationModel.parametric(th80Curves), .table(.macOSDefault)] {
            for acceleration in stride(from: 0.0, through: 3, by: 0.25) {
                let transfer = model.transfer(acceleration: acceleration)
                var previous = 0.0
                for counts in stride(from: 0.5, through: 300, by: 0.5) {
                    let value = transfer.output(forCounts: counts)
                    #expect(value >= previous - 1e-9, "a=\(acceleration) at \(counts)")
                    previous = value
                }
            }
        }
    }
}
