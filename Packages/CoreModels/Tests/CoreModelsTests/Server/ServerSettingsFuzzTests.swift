@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct ServerSettingsFuzzTests {
    private static let digitHeavy: [Character] = Array("0123456789..,,  e-+")

    private static func numeric(using rng: inout SplitMix64, maxLength: Int) -> String {
        let length = Int(rng.next() % UInt64(maxLength + 1))
        return String((0 ..< length).map { _ in digitHeavy[Int(rng.next() % UInt64(digitHeavy.count))] })
    }

    @Test("monkey test: any size cap text never crashes, and an accepted cap is a positive byte count")
    func sizeCapFuzzing() {
        var rng = SplitMix64(seed: 0xCA9_5129)
        for index in 0 ..< 6000 {
            let text = index.isMultiple(of: 2)
                ? Self.numeric(using: &rng, maxLength: 30)
                : FuzzStrings.random(using: &rng, maxLength: 30)
            let parsed = TrashSettings.maxBytes(fromGiBText: text)
            guard let parsed else { continue }
            if let bytes = parsed {
                #expect(bytes > 0)
            } else {
                #expect(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @Test("monkey test: adding a path never breaks the list's invariants")
    func excludedPathFuzzing() {
        var rng = SplitMix64(seed: 0xE0C1_0DED)
        var current = ExcludedPaths(paths: ["a", "b/c"], environmentPaths: ["env"])
        for index in 0 ..< 4000 {
            if index.isMultiple(of: 50) {
                current = ExcludedPaths(paths: ["a", "b/c"], environmentPaths: ["env"])
            }
            let raw = FuzzStrings.random(using: &rng, maxLength: 24)
            let result = current.adding(raw)
            #expect(Set(current.paths).isSubset(of: Set(result)))
            #expect(result.count == Set(result).count)
            #expect(!result.contains(""))
            #expect(result.allSatisfy { !$0.hasPrefix("/") })
            #expect(!result.contains("env"))
            #expect(result == result.sorted { $0.localizedCompare($1) == .orderedAscending })
            current = ExcludedPaths(paths: result, environmentPaths: current.environmentPaths)
        }
    }

    @Test("monkey test: a path is valid exactly when it is empty or absolute")
    func ffmpegPathFuzzing() {
        var rng = SplitMix64(seed: 0xFF3E_6001)
        for _ in 0 ..< 4000 {
            let ffmpeg = FuzzStrings.random(using: &rng, maxLength: 16)
            let ffprobe = FuzzStrings.random(using: &rng, maxLength: 16)
            let expected = [ffmpeg, ffprobe].allSatisfy { $0.isEmpty || $0.hasPrefix("/") }
            #expect(FFmpegSettings(ffmpegPath: ffmpeg, ffprobePath: ffprobe).isValid == expected)
        }
    }

    @Test("monkey test: the used share of any volume stays between nothing and a hundred")
    func usedShareFuzzing() {
        var rng = SplitMix64(seed: 0x05ED_5A1E)
        for _ in 0 ..< 4000 {
            let used = Int(rng.next() >> 2)
            let versions = Int(rng.next() >> 2)
            let budget = rng.next().isMultiple(of: 5) ? nil : Int(rng.next() >> 2)
            let zone = TrashZone(id: "z", name: "z", usedBytes: used, versionBytes: versions, budgetBytes: budget)
            #expect((0 ... 100).contains(zone.usedPercent))
            #expect((0 ... 1).contains(zone.usedFraction))
        }
    }

    @Test("monkey test: any timestamp text reads as a date or as nothing")
    func timestampFuzzing() {
        var rng = SplitMix64(seed: 0x71AE_0001)
        for _ in 0 ..< 4000 {
            _ = ServerTimestamp.date(from: FuzzStrings.random(using: &rng, maxLength: 40))
        }
        #expect(ServerTimestamp.date(from: "2026-11-11T07:00:00Z") != nil)
    }
}
