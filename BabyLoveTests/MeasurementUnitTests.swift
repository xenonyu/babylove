import XCTest
@testable import BabyLove

final class MeasurementUnitTests: XCTestCase {

    // MARK: - Labels

    func testMetricLabels() {
        let u = MeasurementUnit.metric
        XCTAssertEqual(u.weightLabel, "kg")
        XCTAssertEqual(u.heightLabel, "cm")
        XCTAssertEqual(u.volumeLabel, "ml")
    }

    func testImperialLabels() {
        let u = MeasurementUnit.imperial
        XCTAssertEqual(u.weightLabel, "lbs")
        XCTAssertEqual(u.heightLabel, "in")
        XCTAssertEqual(u.volumeLabel, "oz")
    }

    // MARK: - Weight Conversion

    func testMetricWeightIsPassthrough() {
        XCTAssertEqual(MeasurementUnit.metric.weightFromKG(5.5), 5.5, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.metric.weightToKG(5.5), 5.5, accuracy: 0.0001)
    }

    func testKGtoLbs() {
        XCTAssertEqual(MeasurementUnit.imperial.weightFromKG(1.0), 2.20462, accuracy: 0.001)
    }

    func testLbsToKG() {
        XCTAssertEqual(MeasurementUnit.imperial.weightToKG(2.20462), 1.0, accuracy: 0.001)
    }

    func testWeightRoundTrip() {
        for u in MeasurementUnit.allCases {
            let original = 5.432
            let roundTripped = u.weightFromKG(u.weightToKG(original))
            XCTAssertEqual(roundTripped, original, accuracy: 0.0001, "Round-trip failed for \(u)")
        }
    }

    // MARK: - Length Conversion

    func testCMtoInches() {
        XCTAssertEqual(MeasurementUnit.imperial.lengthFromCM(2.54), 1.0, accuracy: 0.001)
    }

    func testInchesToCM() {
        XCTAssertEqual(MeasurementUnit.imperial.lengthToCM(1.0), 2.54, accuracy: 0.001)
    }

    func testLengthRoundTrip() {
        for u in MeasurementUnit.allCases {
            let original = 60.5
            let roundTripped = u.lengthFromCM(u.lengthToCM(original))
            XCTAssertEqual(roundTripped, original, accuracy: 0.0001, "Round-trip failed for \(u)")
        }
    }

    // MARK: - Volume Conversion

    func testMLtoOz() {
        XCTAssertEqual(MeasurementUnit.imperial.volumeFromML(29.5735), 1.0, accuracy: 0.001)
    }

    func testOzToML() {
        XCTAssertEqual(MeasurementUnit.imperial.volumeToML(1.0), 29.5735, accuracy: 0.001)
    }

    func testVolumeRoundTrip() {
        for u in MeasurementUnit.allCases {
            let original = 120.0
            let roundTripped = u.volumeFromML(u.volumeToML(original))
            XCTAssertEqual(roundTripped, original, accuracy: 0.0001, "Round-trip failed for \(u)")
        }
    }
}
