//
//  SetAdvisorTests.swift
//  AtlasTests
//
//  Unit tests for SetAdvisor smart features logic.
//

import Testing
@testable import Atlas
import Foundation

struct SetAdvisorTests {

    // MARK: - Auto-detect Tag Tests

    @Test func suggestTag_noSetsLogged_returnsWarmup() async throws {
        let result = SetAdvisor.suggestTag(
            enteredWeightKg: 50,
            thisSessionSets: [],
            historicalWorkingSets: [],
            lastUsedTag: nil
        )
        #expect(result == "W")
    }

    @Test func suggestTag_lightWeight_returnsWarmup() async throws {
        // Historical median is 100kg, entered weight is 60kg (60% of median)
        let historical = [
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        ]
        let thisSets = [
            SetAdvisor.SetData(weightKg: 60, reps: 12, tag: "W", createdAt: Date())
        ]

        let result = SetAdvisor.suggestTag(
            enteredWeightKg: 60,
            thisSessionSets: thisSets,
            historicalWorkingSets: historical,
            lastUsedTag: "W"
        )
        #expect(result == "W")
    }

    @Test func suggestTag_heavyWeight_returnsWorking() async throws {
        // Historical median is 100kg, entered weight is 95kg (95% of median)
        let historical = [
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        ]
        let thisSets = [
            SetAdvisor.SetData(weightKg: 60, reps: 12, tag: "W", createdAt: Date())
        ]

        let result = SetAdvisor.suggestTag(
            enteredWeightKg: 95,
            thisSessionSets: thisSets,
            historicalWorkingSets: historical,
            lastUsedTag: "W"
        )
        #expect(result == "S")
    }

    @Test func suggestTag_weightDrop_returnsDrop() async throws {
        // After a 100kg working set, entering 75kg (75% of last working)
        let thisSets = [
            SetAdvisor.SetData(weightKg: 60, reps: 12, tag: "W", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        ]

        let result = SetAdvisor.suggestTag(
            enteredWeightKg: 75,
            thisSessionSets: thisSets,
            historicalWorkingSets: [],
            lastUsedTag: "S"
        )
        #expect(result == "DS")
    }

    // MARK: - PR Detection Tests

    @Test func checkPRStatus_noPreviousData_isPR() async throws {
        let (isPR, isClose) = SetAdvisor.checkPRStatus(
            weightKg: 100,
            reps: 8,
            historicalBestWeightAt5Plus: nil,
            historicalBestVolume: nil
        )
        #expect(isPR == true)
        #expect(isClose == false)
    }

    @Test func checkPRStatus_exceedsWeight_isPR() async throws {
        let (isPR, _) = SetAdvisor.checkPRStatus(
            weightKg: 105,
            reps: 6,
            historicalBestWeightAt5Plus: 100,
            historicalBestVolume: 800
        )
        #expect(isPR == true)
    }

    @Test func checkPRStatus_exceedsVolume_isPR() async throws {
        let (isPR, _) = SetAdvisor.checkPRStatus(
            weightKg: 90,
            reps: 10, // 90 * 10 = 900 > 800
            historicalBestWeightAt5Plus: 100,
            historicalBestVolume: 800
        )
        #expect(isPR == true)
    }

    @Test func checkPRStatus_closeToPR() async throws {
        let (isPR, isClose) = SetAdvisor.checkPRStatus(
            weightKg: 99, // 99% of 100
            reps: 6,
            historicalBestWeightAt5Plus: 100,
            historicalBestVolume: 1000
        )
        #expect(isPR == false)
        #expect(isClose == true)
    }

    // MARK: - Fatigue Detection Tests

    @Test func detectFatigue_notEnoughSets_noFatigue() async throws {
        let sets = [
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        ]
        let (isFatigued, _) = SetAdvisor.detectFatigue(thisSessionSets: sets, targetRepRangeLower: 6)
        #expect(isFatigued == false)
    }

    @Test func detectFatigue_repsDroppingSignificantly_detectsFatigue() async throws {
        let sets = [
            SetAdvisor.SetData(weightKg: 100, reps: 10, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 7, tag: "S", createdAt: Date()) // 3 rep drop
        ]
        let (isFatigued, message) = SetAdvisor.detectFatigue(thisSessionSets: sets, targetRepRangeLower: 6)
        #expect(isFatigued == true)
        #expect(message != nil)
    }

    @Test func detectFatigue_belowTargetRange_detectsFatigue() async throws {
        let sets = [
            SetAdvisor.SetData(weightKg: 100, reps: 5, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 4, tag: "S", createdAt: Date())
        ]
        let (isFatigued, _) = SetAdvisor.detectFatigue(thisSessionSets: sets, targetRepRangeLower: 6)
        #expect(isFatigued == true)
    }

    // MARK: - Auto Progression Tests

    @Test func suggestProgression_noData_returnsNil() async throws {
        let result = SetAdvisor.suggestProgression(
            lastSessionBestWorkingSet: nil,
            targetRepRangeUpper: 10,
            isMetricUnit: true
        )
        #expect(result == nil)
    }

    @Test func suggestProgression_belowRepRange_suggestsOneMoreRep() async throws {
        let lastBest = SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        let result = SetAdvisor.suggestProgression(
            lastSessionBestWorkingSet: lastBest,
            targetRepRangeUpper: 10,
            isMetricUnit: true
        )
        #expect(result?.reps == 9)
        #expect(result?.weightKg == 100)
        #expect(result?.reason == "+1 rep")
    }

    @Test func suggestProgression_atTopOfRange_suggestsWeightIncrease() async throws {
        let lastBest = SetAdvisor.SetData(weightKg: 100, reps: 10, tag: "S", createdAt: Date())
        let result = SetAdvisor.suggestProgression(
            lastSessionBestWorkingSet: lastBest,
            targetRepRangeUpper: 10,
            isMetricUnit: true
        )
        #expect(result?.weightKg ?? 0 > 100)
        #expect(result?.reason == "+1.25 kg")
    }

    // MARK: - Target Remaining Tests

    @Test func calculateTargetRemaining_parsesCorrectly() async throws {
        let plan = "Warmup: light × 8–12 reps\nWorking: 3–4 sets × 6–10 reps"
        let result = SetAdvisor.calculateTargetRemaining(planText: plan, workingSetsLogged: 1)
        #expect(result.workingSetsRemaining == 2)
        #expect(result.repRangeLower == 6)
        #expect(result.repRangeUpper == 10)
    }

    @Test func calculateTargetRemaining_targetComplete() async throws {
        let plan = "Working: 3 sets × 6–10 reps"
        let result = SetAdvisor.calculateTargetRemaining(planText: plan, workingSetsLogged: 3)
        #expect(result.workingSetsRemaining == 0)
    }

    // MARK: - Set Notes Tests

    @Test func generateSetNote_topSet_returnsTopSet() async throws {
        let sets = [
            SetAdvisor.SetData(weightKg: 80, reps: 10, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date())
        ]
        let note = SetAdvisor.generateSetNote(
            set: sets[1],
            setIndex: 1,
            allSessionSets: sets,
            historicalBestWeightAt5Plus: 90,
            historicalBestVolume: 700
        )
        // 100 * 8 = 800 > 700, so it's a PR
        #expect(note?.isPR == true || note?.text == "Top set")
    }

    @Test func generateSetNote_backoffSet_returnsBackoff() async throws {
        let sets = [
            SetAdvisor.SetData(weightKg: 100, reps: 8, tag: "S", createdAt: Date()),
            SetAdvisor.SetData(weightKg: 80, reps: 10, tag: "S", createdAt: Date())
        ]
        let note = SetAdvisor.generateSetNote(
            set: sets[1],
            setIndex: 1,
            allSessionSets: sets,
            historicalBestWeightAt5Plus: 120,
            historicalBestVolume: 1200
        )
        #expect(note?.text == "Back-off")
    }
}
