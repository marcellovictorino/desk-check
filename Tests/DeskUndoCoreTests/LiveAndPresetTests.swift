import XCTest
@testable import DeskUndoCore

/// Intent source: piece 3 of the Desk Undo brief (SCR-705): sit and stand presets read from a desk-leg tape and
/// confirmed by the camera; live mode bands of top of screen 2 cm below eye level (green 3, yellow 6),
/// distance 62 cm (12, 20) and desk 3 cm below the elbow (3, 6); readings averaged about a second;
/// all of it per setup, with a MacBook-only seated setup having no desk-height preset.
final class LiveBandTests: XCTestCase {
    let measured = Setup(userHeightCm: 175, eyeToElbowCm: 50)

    func reading(distance: Double = 62, eyeAboveTop: Double = 2, eyeAboveDesk: Double = 53) -> PostureReading {
        PostureReading(distanceCm: distance, eyeAboveScreenTopCm: eyeAboveTop, eyeHeightAboveDeskCm: eyeAboveDesk)
    }

    func levels(_ r: PostureReading, fixed: Set<Adjustment> = []) -> [Adjustment: BandLevel] {
        Dictionary(uniqueKeysWithValues: LiveEngine.advise(r, setup: measured, fixed: fixed).map { ($0.adjustment, $0.level) })
    }

    func testOnTargetIsGreenEverywhere() {
        XCTAssertEqual(levels(reading()), [.screenDistance: .green, .screenHeight: .green, .deskHeight: .green])
    }

    func testScreenHeightBandsAreCentredTwoCmBelowEyes() {
        XCTAssertEqual(levels(reading(eyeAboveTop: 5))[.screenHeight], .green)    // 3 off
        XCTAssertEqual(levels(reading(eyeAboveTop: 5.5))[.screenHeight], .yellow)
        XCTAssertEqual(levels(reading(eyeAboveTop: 8))[.screenHeight], .yellow)   // 6 off
        XCTAssertEqual(levels(reading(eyeAboveTop: 8.5))[.screenHeight], .red)
        XCTAssertEqual(levels(reading(eyeAboveTop: -1))[.screenHeight], .green)
        XCTAssertEqual(levels(reading(eyeAboveTop: -5))[.screenHeight], .red)
    }

    func testDistanceBandsAround62() {
        XCTAssertEqual(levels(reading(distance: 50))[.screenDistance], .green)
        XCTAssertEqual(levels(reading(distance: 74))[.screenDistance], .green)
        XCTAssertEqual(levels(reading(distance: 45))[.screenDistance], .yellow)
        XCTAssertEqual(levels(reading(distance: 82))[.screenDistance], .yellow)
        XCTAssertEqual(levels(reading(distance: 83))[.screenDistance], .red)
        XCTAssertEqual(levels(reading(distance: 41))[.screenDistance], .red)
    }

    func testDeskBandsAreCentredThreeCmBelowTheElbow() {
        // Elbow is 50 cm below the eyes, so the desk is right when the eyes are 53 cm above it.
        XCTAssertEqual(levels(reading(eyeAboveDesk: 56))[.deskHeight], .green)
        XCTAssertEqual(levels(reading(eyeAboveDesk: 58))[.deskHeight], .yellow)
        XCTAssertEqual(levels(reading(eyeAboveDesk: 60))[.deskHeight], .red)
    }

    func testArrowsPointTheWayToMoveWithTheNumber() {
        let a = LiveEngine.advise(reading(distance: 80, eyeAboveTop: 10, eyeAboveDesk: 45), setup: measured, fixed: [])
        func get(_ x: Adjustment) -> LiveAdvice { a.first { $0.adjustment == x }! }
        XCTAssertEqual(get(.screenDistance).direction, .closer)
        XCTAssertEqual(get(.screenDistance).moveCm, 18)
        XCTAssertEqual(get(.screenHeight).direction, .up)       // eyes well above the screen top: raise the screen
        XCTAssertEqual(get(.screenHeight).moveCm, 8)
        XCTAssertEqual(get(.deskHeight).direction, .down)       // eyes only 45 above desk: desk too high
        XCTAssertEqual(get(.deskHeight).moveCm, 8)
        XCTAssertEqual(LiveEngine.advise(reading(distance: 45), setup: measured, fixed: []).first!.direction, .further)
    }

    func testMacBookSeatedSetupShowsOnlyDistance() {
        let laptop = SetupProfile.laptop(name: "Sofa")
        let advice = LiveEngine.advise(reading(distance: 80), setup: laptop.measurements, fixed: laptop.fixed)
        XCTAssertEqual(advice.map(\.adjustment), [.screenDistance])
    }

    func testEyeToElbowDefaultsFromHeight() {
        XCTAssertEqual(Setup(userHeightCm: 180).eyeToElbow, 54, accuracy: 0.01)
        XCTAssertEqual(Setup(userHeightCm: 180, eyeToElbowCm: 49).eyeToElbow, 49)
    }
}

final class RollingAverageTests: XCTestCase {
    func r(_ d: Double) -> PostureReading { PostureReading(distanceCm: d, eyeAboveScreenTopCm: 0, eyeHeightAboveDeskCm: 0) }

    func testAveragesAboutOneSecondAndDropsOlderFrames() {
        var avg = RollingAverage(window: 1.0, minimumCount: 3)
        for (i, d) in [100.0, 60, 62, 61].enumerated() { avg.add(r(d), at: 5.0 + Double(i) * 0.35) }
        // The 100 cm frame at t=5.0 is more than a second older than t=6.05.
        XCTAssertEqual(avg.average?.distanceCm ?? 0, 61, accuracy: 0.01)
    }

    func testShowsNothingUntilEnoughFrames() {
        var avg = RollingAverage()
        avg.add(r(60), at: 0); avg.add(r(60), at: 0.1)
        XCTAssertNil(avg.average)
        avg.add(r(60), at: 0.2)
        XCTAssertNotNil(avg.average)
        avg.reset()
        XCTAssertNil(avg.average)
    }

    func testSmoothsFrameJitterAcrossABandEdge() {
        var avg = RollingAverage()
        // Frames flicker either side of 74 cm, the edge of green; the averaged number sits in the middle.
        for (i, d) in [73.0, 75, 73, 75, 73, 75].enumerated() { avg.add(r(d), at: Double(i) * 0.15) }
        XCTAssertEqual(avg.average?.distanceCm ?? 0, 74, accuracy: 0.5)
    }
}

final class PresetTests: XCTestCase {
    func testPresetsAreStoredPerSetupAndSurviveASave() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var desk = c.profile(named: "Standing desk")
        desk.presets[.sit] = DeskPreset(deskHeightCm: 72, distanceCm: 60, eyeAboveScreenTopCm: -1.5)
        desk.presets[.stand] = DeskPreset(deskHeightCm: 112)
        c.save(desk)
        XCTAssertTrue(c.addSetup(.laptop(name: "Sofa")))
        var reread = DeskConfig(text: c.document.text)
        XCTAssertEqual(reread.profile(named: "Standing desk").presets[.sit],
                       DeskPreset(deskHeightCm: 72, distanceCm: 60, eyeAboveScreenTopCm: -1.5))
        XCTAssertEqual(reread.profile(named: "Standing desk").presets[.stand]?.deskHeightCm, 112)
        XCTAssertTrue(reread.profile(named: "Sofa").presets.isEmpty, "another setup keeps its own presets")
        reread.save(reread.profile(named: "Standing desk"))
        XCTAssertEqual(reread.profile(named: "Standing desk").presets[.sit]?.eyeAboveScreenTopCm, -1.5)
    }

    func testSeatedOnlySetupCannotKeepAStandingPreset() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = SetupProfile.laptop(name: "Sofa")
        p.presets[.sit] = DeskPreset(deskHeightCm: 74)
        p.presets[.stand] = DeskPreset(deskHeightCm: 110)
        XCTAssertTrue(c.addSetup(p))
        let back = c.profile(named: "Sofa")
        XCTAssertNotNil(back.presets[.sit])
        XCTAssertNil(back.presets[.stand])
        XCTAssertFalse(back.supportsStandingPreset)
    }

    func testRemovingAPresetFromTheProfileRemovesItsKeys() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.profile(named: "Standing desk")
        p.presets[.stand] = DeskPreset(deskHeightCm: 112, distanceCm: 55, eyeAboveScreenTopCm: 3)
        c.save(p)
        p.presets[.stand] = nil
        c.save(p)
        XCTAssertFalse(c.document.text.contains("stand_desk_height_cm = "))
        XCTAssertFalse(c.document.text.contains("stand_distance_cm = "))
    }

    func testCameraConfirmsTheDeskIsBackAtTheSavedHeight() {
        let saved = DeskPreset(deskHeightCm: 112, distanceCm: 58, eyeAboveScreenTopCm: 4)
        func read(_ d: Double, _ h: Double) -> PostureReading { PostureReading(distanceCm: d, eyeAboveScreenTopCm: h, eyeHeightAboveDeskCm: 0) }
        XCTAssertEqual(saved.confirm(read(59.5, 5.5)), .confirmed)
        // The desk was left 6 cm too low: the eyes read 6 cm lower against the screen.
        guard case .differs(let why) = saved.confirm(read(58, -2)) else { return XCTFail("should not confirm") }
        XCTAssertTrue(why.contains("6 cm lower"), why)
        guard case .differs(let far) = saved.confirm(read(66, 4)) else { return XCTFail("should not confirm") }
        XCTAssertTrue(far.contains("8 cm further"), far)
        XCTAssertEqual(DeskPreset(deskHeightCm: 72).confirm(read(60, 2)), .notRemembered)
    }
}
