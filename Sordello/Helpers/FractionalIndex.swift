//
//  FractionalIndex.swift
//  Sordello
//
//  Created by Jonas Barsten on 08/12/2025.
//

import Foundation

/// Lexicographic fractional indexing for ordering items.
/// Allows inserting between items without reindexing others.
/// Based on the approach used by Figma.
///
/// Uses only lowercase letters (a-z) for indices to ensure consistent
/// lexicographic ordering across all locales.
/// nonisolated: Pure algorithms with no mutable state, safe for background threads
nonisolated enum FractionalIndex {
    /// Smallest valid index
    static let first = "a"
    static let chars = K.lexIndex.chars
    static let base = K.lexIndex.base

    /// Generate initial indices for n items, well-spaced
    static func generateInitialIndices(count: Int) -> [String] {
        guard count > 0 else { return [] }

        // Local constants for background thread safety
//        let chars: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
//        let base = 26

        // For small counts, use single characters spaced evenly
        if count <= 26 {
            let step = max(1, 26 / count)
            return (0..<count).map { i in
                let charIndex = min(i * step, 25)
                return String(chars[charIndex])
            }
        }

        // For larger counts, use two-character indices (26^2 = 676 positions)
        // For very large counts, use three characters (26^3 = 17,576 positions)
        let useThreeChars = count > 676
        var indices: [String] = []
        for i in 0..<count {
            let fraction = Double(i) / Double(count)

            if useThreeChars {
                let value = Int(fraction * Double(base * base * base))
                let first = value / (base * base)
                let second = (value / base) % base
                let third = value % base
                indices.append(String(chars[first]) + String(chars[second]) + String(chars[third]))
            } else {
                let value = Int(fraction * Double(base * base))
                let first = value / base
                let second = value % base
                indices.append(String(chars[first]) + String(chars[second]))
            }
        }
        return indices
    }

    /// Generate an index between two existing indices
    /// - Parameters:
    ///   - before: The index that should sort before the new one (nil for start)
    ///   - after: The index that should sort after the new one (nil for end)
    /// - Returns: A new index that sorts between before and after
    static func between(_ before: String?, _ after: String?) -> String {
        // Local constants for background thread safety
//        let chars: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
//        let base = 26

        let a = before ?? ""
        let b = after ?? "zz"  // max

        // Calculate lexicographic midpoint
        let maxLen = max(a.count, b.count, 1)
        let paddedA = a.padding(toLength: maxLen, withPad: "a", startingAt: 0)
        let paddedB = b.padding(toLength: maxLen, withPad: "a", startingAt: 0)

        // Convert to numeric values
        var aVals = paddedA.compactMap { chars.firstIndex(of: $0) }
        var bVals = paddedB.compactMap { chars.firstIndex(of: $0) }

        // Ensure equal length
        while aVals.count < bVals.count { aVals.append(0) }
        while bVals.count < aVals.count { bVals.append(0) }

        // Calculate midpoint from right to left
        var carry = 0
        var result: [Int] = []

        for i in (0..<aVals.count).reversed() {
            let sum = aVals[i] + bVals[i] + carry
            result.insert(sum % base, at: 0)
            carry = sum / base
        }

        if carry > 0 {
            result.insert(carry, at: 0)
        }

        // Divide by 2
        var remainder = 0
        var divided: [Int] = []
        for val in result {
            let current = remainder * base + val
            divided.append(current / 2)
            remainder = current % 2
        }

        // If there's a remainder, we need more precision
        if remainder > 0 {
            divided.append(base / 2)
        }

        // Convert back to string, trimming leading zeros
        var resultStr = ""
        var foundNonZero = false
        for val in divided {
            if val > 0 || foundNonZero || divided.count == 1 {
                foundNonZero = true
                resultStr.append(chars[val])
            }
        }

        // Ensure result is actually between a and b
        if resultStr <= a {
            resultStr = a + String(chars[base / 2])
        }
        if resultStr >= b {
            resultStr = a + String(chars[base / 2])
        }

        return resultStr.isEmpty ? String(chars[base / 2]) : resultStr
    }
}
