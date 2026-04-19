import Foundation

/// Infers the wait type from the structural position of the winning tile in its
/// completed meld. Used to auto-fill the wait-type picker after decomposition.
public enum WaitInference {

    /// Derive the wait type for `hand`:
    /// - Eye completion → 單釣 (`.singleWait`)
    /// - Pung / kong completion → 對碰 (`.pairWait`)
    /// - Middle of a chow (123 completed by 2; 456 by 5; etc.) → 嵌張 (`.closedWait`)
    /// - Rank 3 completing 123, or rank 7 completing 789 → 邊張 (`.edgeWait`)
    /// - Any other chow end → 兩面 (`.openWait`)
    public static func infer(for hand: Hand) -> WaitType {
        switch hand.winCompletes {
        case .eye:
            return .singleWait
        case .meld(let i):
            let meld = hand.melds[i]
            return inferForCompletedMeld(meld: meld, winningTile: hand.winningTile)
        }
    }

    private static func inferForCompletedMeld(meld: Meld, winningTile: Tile) -> WaitType {
        switch meld.kind {
        case .pair:
            // A body meld shouldn't be a pair; treat as single-wait for safety.
            return .singleWait
        case .pung, .kong:
            return .pairWait
        case .chow:
            guard case let .numeric(_, startRank) = meld.baseTile,
                  let position = meld.tiles.firstIndex(of: winningTile)
            else {
                return .openWait
            }
            // position is 0, 1, or 2 since chows have 3 sorted tiles.
            if position == 1 { return .closedWait }
            if startRank == 1 && position == 2 { return .edgeWait }   // completed 123 by 3
            if startRank == 7 && position == 0 { return .edgeWait }   // completed 789 by 7
            return .openWait
        }
    }
}
