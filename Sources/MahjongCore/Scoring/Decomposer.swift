import Foundation

/// Turns a flat list of recognized tiles into a validated `Hand` (5 melds + eye).
///
/// This is the bridge between the recognizer output and the scoring engine. For v1
/// every meld is assumed concealed; per-meld concealment can be layered on later.
public enum Decomposer {

    public enum DecomposeError: Error, Equatable {
        case wrongTileCount(got: Int)
        case noValidDecomposition
    }

    /// Attempt to decompose `bodyTiles` into 5 melds + 1 eye, with `winningTile`
    /// belonging to the completed meld or eye.
    ///
    /// - Parameters:
    ///   - bodyTiles: All non-flower tiles making up the winning hand (17 + extra
    ///     per kong).
    ///   - flowers: Flower tiles. Not part of the decomposition but carried through.
    ///   - winningTile: The tile that completed the hand. Must appear in `bodyTiles`.
    ///   - winCompletesMeld: Optional override — if the completed group is known,
    ///     pass it (e.g. `.eye` or `.meld(index:)`). If nil, the first decomposition
    ///     that contains `winningTile` is used.
    ///   - isConcealed: Concealment applied to every meld + the eye.
    public static func decompose(
        bodyTiles: [Tile],
        flowers: [Tile] = [],
        winningTile: Tile,
        isConcealed: Bool = true
    ) throws -> Hand {
        // Body tile count: 15 + 2 (eye) = 17, plus 1 extra per kong (each kong is 4 tiles
        // instead of 3). So valid counts are 17...22.
        guard (17...22).contains(bodyTiles.count) else {
            throw DecomposeError.wrongTileCount(got: bodyTiles.count)
        }
        guard bodyTiles.contains(winningTile) else {
            throw DecomposeError.noValidDecomposition
        }

        let sorted = bodyTiles.sorted()

        // Distinct tiles that appear ≥2 times — eye candidates.
        var counts: [Tile: Int] = [:]
        for t in sorted { counts[t, default: 0] += 1 }
        let pairCandidates = counts.filter { $0.value >= 2 }.map(\.key).sorted()

        for pair in pairCandidates {
            var rest = sorted
            remove(&rest, value: pair, count: 2)
            guard let melds = decomposeBody(rest, isConcealed: isConcealed),
                  melds.count == 5
            else { continue }

            let eye = try Meld(kind: .pair, tiles: [pair, pair], isConcealed: isConcealed)
            let winCompletes: WinCompletion
            if let idx = melds.firstIndex(where: { $0.tiles.contains(winningTile) }) {
                winCompletes = .meld(index: idx)
            } else if pair == winningTile {
                winCompletes = .eye
            } else {
                // Winning tile isn't in any group of this decomposition — skip.
                continue
            }
            if let hand = try? Hand(
                melds: melds,
                eye: eye,
                flowers: flowers,
                winningTile: winningTile,
                winCompletes: winCompletes
            ) {
                return hand
            }
        }

        throw DecomposeError.noValidDecomposition
    }

    // MARK: - Internals

    /// Greedy, first-match backtracking decomposition. Always picks the lowest
    /// remaining tile and tries (in order) kong, pung, chow. Returns the first
    /// decomposition that consumes all tiles, or `nil` if none exist.
    private static func decomposeBody(_ tiles: [Tile], isConcealed: Bool) -> [Meld]? {
        if tiles.isEmpty { return [] }
        let sorted = tiles.sorted()
        let first = sorted[0]
        let firstCount = sorted.filter { $0 == first }.count

        // Kong (4)
        if firstCount >= 4 {
            var rest = sorted
            remove(&rest, value: first, count: 4)
            if let sub = decomposeBody(rest, isConcealed: isConcealed) {
                let kong = try! Meld(kind: .kong,
                                     tiles: [first, first, first, first],
                                     isConcealed: isConcealed)
                return [kong] + sub
            }
        }

        // Pung (3)
        if firstCount >= 3 {
            var rest = sorted
            remove(&rest, value: first, count: 3)
            if let sub = decomposeBody(rest, isConcealed: isConcealed) {
                let pung = try! Meld(kind: .pung,
                                     tiles: [first, first, first],
                                     isConcealed: isConcealed)
                return [pung] + sub
            }
        }

        // Chow
        if case .numeric(let suit, let rank) = first, rank <= 7 {
            let t2 = Tile.numeric(suit, rank + 1)
            let t3 = Tile.numeric(suit, rank + 2)
            if sorted.contains(t2), sorted.contains(t3) {
                var rest = sorted
                if let i = rest.firstIndex(of: first) { rest.remove(at: i) }
                if let i = rest.firstIndex(of: t2) { rest.remove(at: i) }
                if let i = rest.firstIndex(of: t3) { rest.remove(at: i) }
                if let sub = decomposeBody(rest, isConcealed: isConcealed) {
                    let chow = try! Meld(kind: .chow,
                                         tiles: [first, t2, t3],
                                         isConcealed: isConcealed)
                    return [chow] + sub
                }
            }
        }

        return nil
    }

    private static func remove(_ tiles: inout [Tile], value: Tile, count: Int) {
        for _ in 0..<count {
            if let idx = tiles.firstIndex(of: value) { tiles.remove(at: idx) }
        }
    }

    // MARK: - Concealed / exposed split

    /// Decompose a hand where some tiles are known exposed (called melds from the
    /// lower row of the photo) and the rest concealed (upper row, including the
    /// winning tile). The exposed tiles must partition into complete melds; the
    /// concealed tiles must complete the hand with (5 − exposedMeldsCount) melds
    /// plus the eye.
    ///
    /// The winning tile must appear in either `concealedTiles` or `exposedTiles`.
    public static func decomposeWithConcealment(
        concealedTiles: [Tile],
        exposedTiles: [Tile],
        flowers: [Tile] = [],
        winningTile: Tile
    ) throws -> Hand {
        // 1. Partition the exposed side into complete melds (no eye).
        let exposedMelds: [Meld]
        if exposedTiles.isEmpty {
            exposedMelds = []
        } else {
            guard let melds = decomposeBody(exposedTiles, isConcealed: false) else {
                throw DecomposeError.noValidDecomposition
            }
            exposedMelds = melds
        }
        let needConcealedMelds = 5 - exposedMelds.count
        guard (0...5).contains(needConcealedMelds) else {
            throw DecomposeError.wrongTileCount(got: exposedTiles.count)
        }

        // 2. Concealed tiles must form `needConcealedMelds` melds + 1 pair eye.
        //    Try each candidate eye.
        let sorted = concealedTiles.sorted()
        var counts: [Tile: Int] = [:]
        for t in sorted { counts[t, default: 0] += 1 }
        let pairCandidates = counts.filter { $0.value >= 2 }.map(\.key).sorted()

        for pair in pairCandidates {
            var rest = sorted
            remove(&rest, value: pair, count: 2)
            guard let concealedMelds = decomposeBody(rest, isConcealed: true),
                  concealedMelds.count == needConcealedMelds
            else { continue }

            // Concealed melds first, then exposed — stable order for winCompletes.
            let allMelds = concealedMelds + exposedMelds
            let eye = try Meld(kind: .pair, tiles: [pair, pair], isConcealed: true)

            let winCompletes: WinCompletion
            if let idx = allMelds.firstIndex(where: { $0.tiles.contains(winningTile) }) {
                winCompletes = .meld(index: idx)
            } else if pair == winningTile {
                winCompletes = .eye
            } else {
                continue  // pair candidate doesn't place the winning tile; try next
            }

            if let hand = try? Hand(
                melds: allMelds, eye: eye, flowers: flowers,
                winningTile: winningTile, winCompletes: winCompletes
            ) {
                return hand
            }
        }

        throw DecomposeError.noValidDecomposition
    }
}
