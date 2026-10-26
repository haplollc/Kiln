//
//  KERandom.swift
//  Kiln engine 2
//
//  The random numbers interpreted code sees. Unseeded it is the system's
//  generator; seeded (Kiln.randomSeed) it is SplitMix64, which native Swift
//  can use too, so a shuffled deck comes out the same in both.
//

/// SplitMix64 when seeded, the system generator otherwise.
public struct KilnRandom: RandomNumberGenerator {
    private var state: UInt64
    private let seeded: Bool

    public init(seed: UInt64?) {
        state = seed ?? 0
        seeded = seed != nil
    }

    public mutating func next() -> UInt64 {
        guard seeded else {
            var system = SystemRandomNumberGenerator()
            return system.next()
        }
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
