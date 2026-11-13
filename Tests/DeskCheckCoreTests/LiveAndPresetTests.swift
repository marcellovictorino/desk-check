import Foundation
import Testing
@testable import DeskCheckCore

/// Intent source: piece 3 of the Desk Check brief (SCR-705): sit and stand presets read from a desk-leg tape and
/// confirmed by the camera; live mode bands of top of screen 2 cm below eye level (green 3, yellow 6),
/// distance 62 cm (12, 20) and desk 3 cm below the elbow (3, 6); readings averaged about a second;
/// all of it per setup, with a MacBook-only seated setup having no desk-height preset.
@Suite struct LiveBandTests {
    let measured = Setup(userHeightCm: 175, eyeToElbowCm: 50)

    func reading(distance: Double = 62, eyeAboveTop: Double = 2, eyeAboveDesk: Double = 53) -> PostureReading {
        PostureReading(distanceCm: distance, eyeAboveScreenTopCm: eyeAboveTop, eyeHeightAboveDeskCm: eyeAboveDesk)
    }

    func levels(_ r: PostureReading, fixed: Set<Adjustment> = []) -> [Adjustment: BandLevel] {
        Dictionary(uniqueKeysWithValues: LiveEngine.advise(r, setup: measured, fixed: fixed).map { ($0.adjustment, $0.level) })
    }

    @Test func onTargetIsGreenEverywhere() {
        #expect(levels(reading()) == [.screenDistance: .green, .screenHeight: .green, .deskHeight: .green])
    }

    @Test func screenHeightBandsAreCentredTwoCmBelowEyes() {
        #expect(levels(reading(eyeAboveTop: 5))[.screenHeight] == .green)    // 3 off
        #expect(levels(reading(eyeAboveTop: 5.5))[.screenHeight] == .yellow)
        #expect(levels(reading(eyeAboveTop: 8))[.screenHeight] == .yellow)   // 6 off
        #expect(levels(reading(eyeAboveTop: 8.5))[.screenHeight] == .red)
        #expect(levels(reading(eyeAboveTop: -1))[.screenHeight] == .green)
        #expect(levels(reading(eyeAboveTop: -5))[.screenHeight] == .red)
    }

    @Test func distanceBandsAround62() {
        #expect(levels(reading(distance: 50))[.screenDistance] == .green)
        #expect(levels(reading(distance: 74))[.screenDistance] == .green)
        #expect(levels(reading(distance: 45))[.screenDistance] == .yellow)
        #expect(levels(reading(distance: 82))[.screenDistance] == .yellow)
        #expect(levels(reading(distance: 83))[.screenDistance] == .red)
        #expect(levels(reading(distance: 41))[.screenDistance] == .red)
    }

    @Test func deskBandsAreCentredThreeCmBelowTheElbow() {
        // Elbow is 50 cm below the eyes, so the desk is right when the eyes are 53 cm above it.
        #expect(levels(reading(eyeAboveDesk: 56))[.deskHeight] == .green)
        #expect(levels(reading(eyeAboveDesk: 58))[.deskHeight] == .yellow)
        #expect(levels(reading(eyeAboveDesk: 60))[.deskHeight] == .red)
    }

    @Test func arrowsPointTheWayToMoveWithTheNumber() {
        let a = LiveEngine.advise(reading(distance: 80, eyeAboveTop: 10, eyeAboveDesk: 45), setup: measured, fixed: [])
        func get(_ x: Adjustment) -> LiveAdvice { a.first { $0.adjustment == x }! }
        #expect(get(.screenDistance).direction == .closer)
        #expect(get(.screenDistance).moveCm == 18)
        #expect(get(.screenHeight).direction == .up)       // eyes well above the screen top: raise the screen
        #expect(get(.screenHeight).moveCm == 8)
        #expect(get(.deskHeight).direction == .down)       // eyes only 45 above desk: desk too high
        #expect(get(.deskHeight).moveCm == 8)
        #expect(LiveEngine.advise(reading(distance: 45), setup: measured, fixed: []).first!.direction == .further)
    }

    @Test func macBookSeatedSetupShowsOnlyDistance() {
        let laptop = SetupProfile.laptop(name: "Sofa")
        let advice = LiveEngine.advise(reading(distance: 80), setup: laptop.measurements, fixed: laptop.fixed)
        #expect(advice.map(\.adjustment) == [.screenDistance])
    }

    @Test func eyeToElbowDefaultsFromHeight() {
        #expect(abs((Setup(userHeightCm: 180).eyeToElbow) - 54) <= 0.01)
        #expect(Setup(userHeightCm: 180, eyeToElbowCm: 49).eyeToElbow == 49)
    }
}

@Suite struct RollingAverageTests {
    func r(_ d: Double) -> PostureReading { PostureReading(distanceCm: d, eyeAboveScreenTopCm: 0, eyeHeightAboveDeskCm: 0) }

    @Test func averagesAboutOneSecondAndDropsOlderFrames() {
        var avg = RollingAverage(window: 1.0, minimumCount: 3)
        for (i, d) in [100.0, 60, 62, 61].enumerated() { avg.add(r(d), at: 5.0 + Double(i) * 0.35) }
        // The 100 cm frame at t=5.0 is more than a second older than t=6.05.
        #expect(abs((avg.average?.distanceCm ?? 0) - 61) <= 0.01)
    }

    @Test func showsNothingUntilEnoughFrames() {
        var avg = RollingAverage()
        avg.add(r(60), at: 0); avg.add(r(60), at: 0.1)
        #expect(avg.average == nil)
        avg.add(r(60), at: 0.2)
        #expect(avg.average != nil)
        avg.reset()
        #expect(avg.average == nil)
    }

    @Test func smoothsFrameJitterAcrossABandEdge() {
        var avg = RollingAverage()
        // Frames flicker either side of 74 cm, the edge of green; the averaged number sits in the middle.
        for (i, d) in [73.0, 75, 73, 75, 73, 75].enumerated() { avg.add(r(d), at: Double(i) * 0.15) }
        #expect(abs((avg.average?.distanceCm ?? 0) - 74) <= 0.5)
    }
}

@Suite struct PresetTests {
    @Test func presetsAreStoredPerSetupAndSurviveASave() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var desk = c.profile(named: "Standing desk")
        desk.presets[.sit] = DeskPreset(deskHeightCm: 72, distanceCm: 60, eyeAboveScreenTopCm: -1.5)
        desk.presets[.stand] = DeskPreset(deskHeightCm: 112)
        c.save(desk)
        let added = c.addSetup(.laptop(name: "Sofa"))
        #expect(added)
        var reread = DeskConfig(text: c.document.text)
        #expect(reread.profile(named: "Standing desk").presets[.sit] == DeskPreset(deskHeightCm: 72, distanceCm: 60, eyeAboveScreenTopCm: -1.5))
        #expect(reread.profile(named: "Standing desk").presets[.stand]?.deskHeightCm == 112)
        #expect(reread.profile(named: "Sofa").presets.isEmpty, "another setup keeps its own presets")
        reread.save(reread.profile(named: "Standing desk"))
        #expect(reread.profile(named: "Standing desk").presets[.sit]?.eyeAboveScreenTopCm == -1.5)
    }

    @Test func seatedOnlySetupCannotKeepAStandingPreset() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = SetupProfile.laptop(name: "Sofa")
        p.presets[.sit] = DeskPreset(deskHeightCm: 74)
        p.presets[.stand] = DeskPreset(deskHeightCm: 110)
        let added = c.addSetup(p)
        #expect(added)
        let back = c.profile(named: "Sofa")
        #expect(back.presets[.sit] != nil)
        #expect(back.presets[.stand] == nil)
        #expect(!(back.supportsStandingPreset))
    }

    @Test func removingAPresetFromTheProfileRemovesItsKeys() {
        var c = DeskConfig(text: DeskConfig.starterContents)
        var p = c.profile(named: "Standing desk")
        p.presets[.stand] = DeskPreset(deskHeightCm: 112, distanceCm: 55, eyeAboveScreenTopCm: 3)
        c.save(p)
        p.presets[.stand] = nil
        c.save(p)
        #expect(!(c.document.text.contains("stand_desk_height_cm = ")))
        #expect(!(c.document.text.contains("stand_distance_cm = ")))
    }

    @Test func cameraConfirmsTheDeskIsBackAtTheSavedHeight() {
        let saved = DeskPreset(deskHeightCm: 112, distanceCm: 58, eyeAboveScreenTopCm: 4)
        func read(_ d: Double, _ h: Double) -> PostureReading { PostureReading(distanceCm: d, eyeAboveScreenTopCm: h, eyeHeightAboveDeskCm: 0) }
        #expect(saved.confirm(read(59.5, 5.5)) == .confirmed)
        // The desk was left 6 cm too low: the eyes read 6 cm lower against the screen.
        guard case .differs(let why) = saved.confirm(read(58, -2)) else { Issue.record("should not confirm"); return }
        #expect(why.contains("6 cm lower"), Comment(rawValue: why))
        guard case .differs(let far) = saved.confirm(read(66, 4)) else { Issue.record("should not confirm"); return }
        #expect(far.contains("8 cm further"), Comment(rawValue: far))
        #expect(DeskPreset(deskHeightCm: 72).confirm(read(60, 2)) == .notRemembered)
    }
}

/// Intent source: the captain's report that Stop needed two clicks (DESK-22). A Stop that arrives while the camera is
/// off must not turn it on, and a reading or camera callback from a stopped session must not act on the next one.
@Suite struct LiveRunTests {
    @Test func stopWhenIdleDoesNothingAndNeverStarts() {
        var run = LiveRun()
        let stopped = run.stop()
        #expect(!(stopped))
        #expect(!(run.isRunning))
    }

    @Test func secondQuickStopIsANoOp() {
        var run = LiveRun()
        let started = run.start()
        #expect(started != nil)
        let stopped = run.stop()
        #expect(stopped)
        let stopped2 = run.stop()
        #expect(!(stopped2), "the second click of a double click must find nothing to stop")
        #expect(!(run.isRunning))
    }

    @Test func startWhileRunningIsRefused() {
        var run = LiveRun()
        let started = run.start()
        #expect(started != nil)
        let started2 = run.start()
        #expect(started2 == nil)
    }

    @Test func lateCallbackFromStoppedSessionIsRejectedAfterRestart() {
        var run = LiveRun()
        let first = run.start()!
        #expect(run.isCurrent(first))
        run.stop()
        #expect(!(run.isCurrent(first)))
        let second = run.start()!
        #expect(!(run.isCurrent(first)), "a permission answer for the old session must not open the camera again")
        #expect(run.isCurrent(second))
    }
}

/// Intent source: Stop moved 130 pt when the bands came and went (DESK-22). The area reserved for the bands depends on
/// the setup's adjustable rows, never on how many bands are showing, so the controls around it stay put.
@Suite struct LiveLayoutTests {
    @Test func reservedHeightFitsExactlyTheSetupsRows() {
        let one = LiveLayout.bandAreaHeight(rows: 1)
        let three = LiveLayout.bandAreaHeight(rows: 3)
        #expect(one == LiveLayout.rowHeight)
        #expect(three == 3 * LiveLayout.rowHeight + 2 * LiveLayout.rowSpacing)
    }

    @Test func reservedHeightNeverCollapsesOrGrowsPastThreeRows() {
        #expect(LiveLayout.bandAreaHeight(rows: 0) == LiveLayout.bandAreaHeight(rows: 1))
        #expect(LiveLayout.bandAreaHeight(rows: 9) == LiveLayout.bandAreaHeight(rows: 3))
    }
}

/// Intent source: DESK-71 option B. A Check pressed within about 10 s of Live reuses Live's steady reading;
/// anything older, or from another setup, webcam or tape measurement, must not stand in for the current desk.
@Suite struct LiveReuseTests {
    let setup = Setup(userHeightCm: 175, eyeToElbowCm: 50)
    let reading = PostureReading(distanceCm: 60, eyeAboveScreenTopCm: 2, eyeHeightAboveDeskCm: 53)

    func snapshot(at time: Double = 100) -> LiveSnapshot {
        LiveSnapshot(reading: reading, time: time, setupName: "Home", cameraName: "C920", measurements: setup)
    }

    @Test func freshMatchingReadingIsUsed() {
        #expect(snapshot().ageIfUsable(now: 103, setupName: "Home", cameraName: "C920", measurements: setup) == 3)
        #expect(snapshot().ageIfUsable(now: 110, setupName: "Home", cameraName: "C920", measurements: setup) == 10)
    }

    @Test func olderReadingIsNotUsed() {
        #expect(snapshot().ageIfUsable(now: 110.5, setupName: "Home", cameraName: "C920", measurements: setup) == nil)
    }

    @Test func otherSetupCameraOrMeasurementsAreNotUsed() {
        #expect(snapshot().ageIfUsable(now: 101, setupName: "Office", cameraName: "C920", measurements: setup) == nil)
        #expect(snapshot().ageIfUsable(now: 101, setupName: "Home", cameraName: "Built-in", measurements: setup) == nil)
        var moved = setup; moved.userHeightCm = 180
        #expect(snapshot().ageIfUsable(now: 101, setupName: "Home", cameraName: "C920", measurements: moved) == nil)
    }

    @Test func aClockBeforeTheReadingIsNotUsed() {
        #expect(snapshot(at: 100).ageIfUsable(now: 99, setupName: "Home", cameraName: "C920", measurements: setup) == nil)
    }

    @Test func messageSaysWhenTheReadingCameFromLive() {
        #expect(CheckOutcome.checked(passed: true, setupName: "Home", cameraName: "C920", reusedSecondsAgo: 4)
            == "Desk check passed for Home with C920. Used the Live reading from 4 s ago. The camera is off.")
        #expect(CheckOutcome.checked(passed: false, setupName: "Home", cameraName: "C920")
            == "Checked for Home with C920. The camera is off.")
    }
}
