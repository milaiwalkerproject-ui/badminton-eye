// MARK: - WidgetSharedDataTests.swift
//
// Unit tests for WidgetSharedData model (WidgetSharedKeys, LiveMatchWidgetData,
// WinRateWidgetData) — verifies constants, Codable round-trips, and Equatable
// conformance used by the WidgetKit extension and the main app.
//
// Uses Swift's modern `Testing` framework (Xcode 16, iOS 17+).

import Testing
import Foundation
@testable import BadmintonEye

// MARK: - WidgetSharedKeys

@Suite("WidgetSharedKeys")
struct WidgetSharedKeysTests {

    @Test("appGroupID has correct bundle prefix")
    func appGroupIDPrefix() {
        #expect(WidgetSharedKeys.appGroupID == "group.com.badmintoneye.app")
    }

    @Test("liveMatch key is stable")
    func liveMatchKey() {
        #expect(WidgetSharedKeys.liveMatch == "widget.liveMatch")
    }

    @Test("winRate key is stable")
    func winRateKey() {
        #expect(WidgetSharedKeys.winRate == "widget.winRate")
    }
}

// MARK: - LiveMatchWidgetData

@Suite("LiveMatchWidgetData")
struct LiveMatchWidgetDataTests {

    private func makeSample(
        teamAName: String  = "Eagles",
        teamBName: String  = "Hawks",
        scoreA: Int        = 15,
        scoreB: Int        = 12,
        gamesWonA: Int     = 1,
        gamesWonB: Int     = 0,
        gameNumber: Int    = 2,
        serverSide: String = "sideA",
        isActive: Bool     = true,
        updatedAt: Date    = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> LiveMatchWidgetData {
        LiveMatchWidgetData(
            teamAName: teamAName, teamBName: teamBName,
            scoreA: scoreA, scoreB: scoreB,
            gamesWonA: gamesWonA, gamesWonB: gamesWonB,
            gameNumber: gameNumber, serverSide: serverSide,
            isActive: isActive, updatedAt: updatedAt
        )
    }

    @Test("stores all fields correctly")
    func fieldStorage() {
        let d = makeSample()
        #expect(d.teamAName  == "Eagles")
        #expect(d.teamBName  == "Hawks")
        #expect(d.scoreA     == 15)
        #expect(d.scoreB     == 12)
        #expect(d.gamesWonA  == 1)
        #expect(d.gamesWonB  == 0)
        #expect(d.gameNumber == 2)
        #expect(d.serverSide == "sideA")
        #expect(d.isActive   == true)
    }

    @Test("Equatable: equal instances compare equal")
    func equatableEqual() {
        let a = makeSample()
        let b = makeSample()
        #expect(a == b)
    }

    @Test("Equatable: different score makes instances unequal")
    func equatableNotEqual() {
        let a = makeSample(scoreA: 15)
        let b = makeSample(scoreA: 16)
        #expect(a != b)
    }

    @Test("Codable: round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = makeSample()
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(LiveMatchWidgetData.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("Codable: serverSide 'sideB' survives round-trip")
    func codableSideBRoundTrip() throws {
        let original = makeSample(serverSide: "sideB")
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(LiveMatchWidgetData.self, from: encoded)
        #expect(decoded.serverSide == "sideB")
    }

    @Test("Codable: inactive match survives round-trip")
    func codableInactiveRoundTrip() throws {
        let original = makeSample(isActive: false)
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(LiveMatchWidgetData.self, from: encoded)
        #expect(decoded.isActive == false)
    }

    @Test("Codable: game 3 (deciding) round-trip")
    func codableDecidingGame() throws {
        let original = makeSample(gamesWonA: 1, gamesWonB: 1, gameNumber: 3)
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(LiveMatchWidgetData.self, from: encoded)
        #expect(decoded.gameNumber == 3)
        #expect(decoded.gamesWonA  == 1)
        #expect(decoded.gamesWonB  == 1)
    }
}

// MARK: - WinRateWidgetData

@Suite("WinRateWidgetData")
struct WinRateWidgetDataTests {

    private func makeSample(
        playerName: String    = "Alice",
        totalMatches: Int     = 20,
        wins: Int             = 15,
        losses: Int           = 5,
        winRate: Double       = 75.0,
        currentStreak: Int    = 3,
        updatedAt: Date       = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> WinRateWidgetData {
        WinRateWidgetData(
            playerName: playerName, totalMatches: totalMatches,
            wins: wins, losses: losses,
            winRate: winRate, currentStreak: currentStreak,
            updatedAt: updatedAt
        )
    }

    @Test("stores all fields correctly")
    func fieldStorage() {
        let d = makeSample()
        #expect(d.playerName    == "Alice")
        #expect(d.totalMatches  == 20)
        #expect(d.wins          == 15)
        #expect(d.losses        == 5)
        #expect(d.winRate       == 75.0)
        #expect(d.currentStreak == 3)
    }

    @Test("Equatable: equal instances compare equal")
    func equatableEqual() {
        let a = makeSample()
        let b = makeSample()
        #expect(a == b)
    }

    @Test("Equatable: different player name makes instances unequal")
    func equatableNotEqual() {
        let a = makeSample(playerName: "Alice")
        let b = makeSample(playerName: "Bob")
        #expect(a != b)
    }

    @Test("Codable: round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = makeSample()
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(WinRateWidgetData.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("Codable: winRate = 0.0 (no wins) round-trip")
    func codableZeroWinRate() throws {
        let original = makeSample(wins: 0, losses: 10, winRate: 0.0, currentStreak: 0)
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(WinRateWidgetData.self, from: encoded)
        #expect(decoded.winRate == 0.0)
        #expect(decoded.currentStreak == 0)
    }

    @Test("Codable: winRate = 100.0 (all wins) round-trip")
    func codablePerfectWinRate() throws {
        let original = makeSample(wins: 10, losses: 0, winRate: 100.0, currentStreak: 10)
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(WinRateWidgetData.self, from: encoded)
        #expect(decoded.winRate == 100.0)
        #expect(decoded.wins    == 10)
        #expect(decoded.losses  == 0)
    }

    @Test("totalMatches consistency: wins + losses == totalMatches")
    func matchConsistency() {
        let d = makeSample(totalMatches: 20, wins: 15, losses: 5)
        #expect(d.wins + d.losses == d.totalMatches)
    }
}
