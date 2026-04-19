import Foundation

// MARK: - Flower family

extension Scorer {
    func flowerAwards(hand: Hand, context: WinContext) -> [TaiAward] {
        let flowers = hand.flowers
        if flowers.isEmpty {
            return [rules.award("no-flowers")]
        }
        var out: [TaiAward] = []

        // Per-flower: matching seat wind vs. not
        var correct = 0
        var wrong = 0
        for tile in flowers {
            guard case .flower(let f) = tile else { continue }
            if f.seatWind == context.seatWind { correct += 1 } else { wrong += 1 }
        }
        if correct > 0 { out.append(rules.award("correct-flower", count: correct)) }
        if wrong > 0 { out.append(rules.award("wrong-flower", count: wrong)) }

        // Set bonuses
        let seasonCount = flowers.reduce(into: 0) { acc, t in
            if case .flower(let f) = t, f.kind == .season { acc += 1 }
        }
        let plantCount = flowers.count - seasonCount

        let hasAllSeasons = seasonCount == 4
        let hasAllPlants = plantCount == 4

        if hasAllSeasons && hasAllPlants {
            out.append(rules.award("two-sets-flowers"))
        } else if hasAllSeasons || hasAllPlants {
            out.append(rules.award("one-set-flowers"))
        }

        return out
    }
}

// MARK: - Bonus / context family

extension Scorer {
    func bonusAwards(hand: Hand, context: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        let concealed = hand.isFullyConcealed
        let allBodyExposed = !hand.melds.contains(where: \.isConcealed)

        // Concealed self-draw supersedes both self-draw and concealed-hand.
        // All-claimed (全/半求人) supersedes self-draw (via the 8-tai composite) when
        // every body meld was called from a discard.
        if concealed && context.selfDrawn {
            out.append(rules.award("concealed-self-draw"))
        } else if allBodyExposed && context.selfDrawn {
            out.append(rules.award("all-claimed-self-draw"))  // 半求人 includes the self-draw
        } else if allBodyExposed && !context.selfDrawn {
            out.append(rules.award("all-claimed-discard"))    // 全求人
        } else {
            if context.selfDrawn {
                out.append(rules.award("self-draw"))
            }
            if concealed {
                out.append(rules.award("concealed-hand"))
            }
        }

        // Wait-related awards — mutually exclusive across wait types.
        switch context.waitType {
        case .pairWait:
            out.append(rules.award("pair-wait"))
        case .singleWait, .edgeWait, .closedWait:
            out.append(rules.award("single-edge-wait"))
        case .openWait:
            break  // no bonus for open two-sided wait
        }

        // Value-eye: eye is 2, 5, or 8 of any numeric suit.
        if case let .numeric(_, rank) = hand.eye.baseTile, rank == 2 || rank == 5 || rank == 8 {
            out.append(rules.award("value-eye"))
        }

        // Kong-on-kong composite supersedes win-on-kong / robbing-a-kong.
        if context.afterKongOnKong && context.robbingKong {
            out.append(rules.award("robbing-kong-on-kong"))
        } else if context.afterKongOnKong && context.selfDrawn {
            out.append(rules.award("kong-on-kong-win"))
        } else {
            if context.robbingKong {
                out.append(rules.award("robbing-a-kong"))
            }
            if context.afterKong {
                out.append(rules.award("win-on-kong"))
            }
        }

        if context.afterFlower {
            out.append(rules.award("win-on-flower"))
        }
        if context.lastTile && context.selfDrawn {
            out.append(rules.award("last-tile-self-draw"))
        }
        if context.declaredTing {
            out.append(rules.award("declared-ready"))
        }

        // Fast-win awards: seven-tiles supersedes ten-tiles.
        if let n = context.turnsBeforeWin {
            if n <= 7 {
                out.append(rules.award("win-within-seven"))
            } else if n <= 10 {
                out.append(rules.award("win-within-ten"))
            }
        }

        return out
    }
}

// MARK: - Wave 2: Chow family (identical / mixed-N / same-N)

extension Scorer {
    func chowFamilyAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []
        let chows = hand.chows
        guard chows.count >= 2 else { return out }

        // Group chows by their starting rank.
        var byStart: [Int: [Meld]] = [:]
        for c in chows {
            if case let .numeric(_, r) = c.baseTile {
                byStart[r, default: []].append(c)
            }
        }

        var counts: [String: Int] = [:]
        func emit(_ id: String) { counts[id, default: 0] += 1 }

        for (_, group) in byStart {
            let n = group.count
            let suitCounts = Dictionary(grouping: group, by: { $0.numericSuit! })
                .mapValues { $0.count }
            let maxIdentical = suitCounts.values.max() ?? 0
            let distinctSuits = suitCounts.count

            switch n {
            case 5:
                emit("five-same-chows")
            case 4:
                if maxIdentical == 4 { emit("four-identical-chows") }
                else { emit("four-same-chows") }
            case 3:
                if maxIdentical == 3 {
                    emit("three-identical-chows")
                } else if distinctSuits == 3 && maxIdentical == 1 {
                    emit("mixed-triple-chow")
                } else if maxIdentical == 2 {
                    emit("identical-chow")  // 2 same + 1 loose: pick the identical pair
                }
            case 2:
                if maxIdentical == 2 {
                    emit("identical-chow")
                } else {
                    emit("mixed-double-chow")
                }
            default:
                break
            }
        }

        for (id, n) in counts {
            out.append(rules.award(id, count: n))
        }
        return out
    }
}

// MARK: - Wave 2: Pung brackets (two/small-three/big-three brothers)

extension Scorer {
    func pungBracketAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []
        // Pungs + kongs count together. Only numeric pungs participate (honors are
        // covered by the dragon/wind family).
        let numericTriplets = (hand.pungs + hand.kongs).filter { $0.numericSuit != nil }
        guard numericTriplets.count >= 2 else { return out }

        var byRank: [Int: [Meld]] = [:]
        for p in numericTriplets {
            if case let .numeric(_, r) = p.baseTile {
                byRank[r, default: []].append(p)
            }
        }

        let eyeRank: Int? = {
            if case let .numeric(_, r) = hand.eye.baseTile { return r }
            return nil
        }()
        let eyeSuit: Suit? = hand.eye.numericSuit

        var counts: [String: Int] = [:]
        func emit(_ id: String) { counts[id, default: 0] += 1 }

        for (rank, group) in byRank {
            let n = group.count
            let distinctSuits = Set(group.compactMap(\.numericSuit)).count

            if n >= 3 && distinctSuits == 3 {
                emit("big-three-brothers")
            } else if n == 2 && distinctSuits == 2 {
                // small-three-brothers: pungs in 2 suits + eye pair of same rank in the 3rd suit
                let groupSuits = Set(group.compactMap(\.numericSuit))
                if rank == eyeRank, let es = eyeSuit, !groupSuits.contains(es) {
                    emit("small-three-brothers")
                } else {
                    emit("two-brothers")
                }
            }
        }

        for (id, n) in counts {
            out.append(rules.award(id, count: n))
        }
        return out
    }
}

// MARK: - Wave 2: Straight patterns (123 / 456 / 789 sequences)

extension Scorer {
    func straightAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []
        let chows = hand.chows
        guard chows.count >= 3 else { return out }

        // Pure straight: 123/456/789 all in one suit.
        for suit in Suit.allCases {
            let inSuit = chows.filter { $0.numericSuit == suit }
            guard inSuit.count >= 3 else { continue }
            let starts = Set(inSuit.compactMap { (m) -> Int? in
                if case let .numeric(_, r) = m.baseTile { return r }
                return nil
            })
            if starts.contains(1) && starts.contains(4) && starts.contains(7) {
                let threeChows = inSuit.filter {
                    if case let .numeric(_, r) = $0.baseTile {
                        return r == 1 || r == 4 || r == 7
                    }
                    return false
                }
                let allConcealed = threeChows.allSatisfy(\.isConcealed)
                out.append(rules.award(
                    allConcealed ? "concealed-pure-straight" : "exposed-pure-straight"
                ))
                return out  // at most one straight award per hand
            }
        }

        // Mixed straight: chows at startRanks 1, 4, 7 across any suits.
        var atStart: [Int: [Meld]] = [:]
        for c in chows {
            if case let .numeric(_, r) = c.baseTile {
                atStart[r, default: []].append(c)
            }
        }
        if let c1 = atStart[1]?.first, let c4 = atStart[4]?.first, let c7 = atStart[7]?.first {
            let allConcealed = c1.isConcealed && c4.isConcealed && c7.isConcealed
            out.append(rules.award(
                allConcealed ? "concealed-mixed-straight" : "exposed-mixed-straight"
            ))
        }

        return out
    }
}

// MARK: - Wave 2: Outside hands (全帶么 / 全帶混么)

extension Scorer {
    func outsideHandAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        let body = hand.allBodyTiles
        let allTerminals = body.allSatisfy { $0.isTerminal }
        let allTerminalsOrHonors = body.allSatisfy { $0.isTerminal || $0.isHonor }
        // all-terminals / all-terminals-honors subsume the outside-hand awards.
        if allTerminals || allTerminalsOrHonors { return out }

        let eachGroupHasOutsideTile = hand.meldsIncludingEye.allSatisfy { m in
            m.tiles.contains { $0.isTerminal || $0.isHonor }
        }
        guard eachGroupHasOutsideTile else { return out }

        let hasHonors = body.contains(where: \.isHonor)
        if hasHonors {
            out.append(rules.award("outside-hand-mixed"))
        } else {
            out.append(rules.award("outside-hand-pure"))
        }
        return out
    }
}

// MARK: - Wave 2: Structural (五門齊 / 老少 / 缺一門)

extension Scorer {
    func structuralAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []
        let body = hand.allBodyTiles

        // all-five-types: has tiles from all three numeric suits + winds + dragons
        var types: Set<String> = []
        for t in body {
            switch t {
            case .numeric(let s, _): types.insert(s.rawValue)
            case .wind: types.insert("W")
            case .dragon: types.insert("D")
            case .flower: break
            }
        }
        if types == Set(["m", "p", "s", "W", "D"]) {
            out.append(rules.award("all-five-types"))
        }

        // old-young: per suit, both a 123-chow and a 789-chow present
        let chows = hand.chows
        var oldYoungCount = 0
        for suit in Suit.allCases {
            let starts = Set(chows.compactMap { (m) -> Int? in
                guard m.numericSuit == suit,
                      case let .numeric(_, r) = m.baseTile else { return nil }
                return r
            })
            if starts.contains(1) && starts.contains(7) {
                oldYoungCount += 1
            }
        }
        if oldYoungCount > 0 {
            out.append(rules.award("old-young", count: oldYoungCount))
        }

        // one-suit-missing: exactly 2 numeric suits present (excluded by full-flush /
        // half-flush which need 1 or 0, and by all-five-types which needs 3).
        let numericSuits = Set(body.compactMap { (t: Tile) -> Suit? in
            if case let .numeric(s, _) = t { return s }
            return nil
        })
        if numericSuits.count == 2 {
            out.append(rules.award("one-suit-missing"))
        }

        return out
    }
}

// MARK: - Set family (kongs, concealed-pungs, all-pungs)

extension Scorer {
    func setAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        let concealedKongs = hand.kongs.filter(\.isConcealed).count
        let exposedKongs = hand.kongs.count - concealedKongs
        if concealedKongs > 0 {
            out.append(rules.award("concealed-kong", count: concealedKongs))
        }
        if exposedKongs > 0 {
            out.append(rules.award("exposed-kong", count: exposedKongs))
        }

        // X-concealed-pungs awards: kongs count as "pung-like" for this rule family.
        // When all 5 body melds are concealed pungs/kongs, the 80-tai five-concealed-pungs
        // rule applies instead (awarded in specialAwards); suppress the 4-award then.
        let concealedTripletCount = hand.melds.filter {
            ($0.kind == .pung || $0.kind == .kong) && $0.isConcealed
        }.count
        if concealedTripletCount < 5 {
            switch concealedTripletCount {
            case 4: out.append(rules.award("four-concealed-pungs"))
            case 3: out.append(rules.award("three-concealed-pungs"))
            case 2: out.append(rules.award("two-concealed-pungs"))
            default: break
            }
        }

        // All-pungs: every body meld is a pung or kong (no chows).
        // Note: four-concealed-pungs + all-pungs can co-occur under this variant;
        // both are listed separately in Rules.json.
        if hand.chows.isEmpty {
            out.append(rules.award("all-pungs"))
        }

        return out
    }
}

// MARK: - Suit family

extension Scorer {
    func suitAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        let body = hand.allBodyTiles
        let hasHonors = body.contains(where: \.isHonor)
        let numericSuits = Set(body.compactMap { (t: Tile) -> Suit? in
            if case let .numeric(s, _) = t { return s }
            return nil
        })
        let oneNumericSuit = numericSuits.count == 1
        let noNumericTiles = numericSuits.isEmpty  // all-honors (字一色) case
        let allChows = hand.chows.count == 5 && hand.eye.numericSuit != nil
        let hasFlowers = !hand.flowers.isEmpty

        // Flush flavor (one can fire).
        // - full-flush supersedes no-honors / no-honors-no-flowers (it implies both).
        // - half-flush (applied also to all-honors hands since 字一色 isn't in the table).
        // - Otherwise award the no-honors family, or the great-pure-ping composite.
        var allChowsAwarded = false
        if oneNumericSuit && !hasHonors {
            out.append(rules.award("full-flush"))
        } else if (oneNumericSuit && hasHonors) || noNumericTiles {
            out.append(rules.award("half-flush"))
        } else if !hasHonors {
            if allChows && !hasFlowers {
                out.append(rules.award("great-pure-ping"))
                allChowsAwarded = true  // composite already includes 平胡
            } else {
                out.append(rules.award("no-honors"))
                if !hasFlowers {
                    out.append(rules.award("no-honors-no-flowers"))
                }
            }
        }

        // all-chows (平胡) stacks with the flush patterns; it's only already counted
        // when the great-pure-ping composite fired above.
        if allChows && !allChowsAwarded {
            out.append(rules.award("all-chows"))
        }

        return out
    }
}

// MARK: - Dragon / wind family

extension Scorer {
    func dragonWindAwards(hand: Hand, context: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        // Per-pung dragon/wind classification.
        var dragonPungs: [Dragon] = []
        var dragonPairIs: Dragon?
        var windPungsSeat = 0
        var windPungsOther = 0
        var windKinds: Set<Wind> = []
        var windPairIs: Wind?

        for m in hand.melds where m.kind == .pung || m.kind == .kong {
            if case let .dragon(d) = m.baseTile {
                dragonPungs.append(d)
            } else if case let .wind(w) = m.baseTile {
                windKinds.insert(w)
                // In Taiwan rules, either the seat wind or the round wind qualifies as "正風".
                if w == context.seatWind || w == context.roundWind {
                    windPungsSeat += 1
                } else {
                    windPungsOther += 1
                }
            }
        }
        if case let .dragon(d) = hand.eye.baseTile { dragonPairIs = d }
        if case let .wind(w) = hand.eye.baseTile { windPairIs = w }

        // Dragon composites supersede individual dragon pungs.
        let dragonSet = Set(dragonPungs)
        if dragonSet.count == 3 {
            out.append(rules.award("big-three-dragons"))
        } else if dragonSet.count == 2 && dragonPairIs != nil
                    && !dragonSet.contains(dragonPairIs!) {
            out.append(rules.award("little-three-dragons"))
        } else if !dragonPungs.isEmpty {
            out.append(rules.award("pung-dragon", count: dragonPungs.count))
        }

        // Wind composites supersede individual wind pungs.
        let windPungCount = windPungsSeat + windPungsOther
        if windKinds.count == 4 {
            out.append(rules.award("big-four-winds"))
        } else if windKinds.count == 3 && windPairIs != nil && !windKinds.contains(windPairIs!) {
            out.append(rules.award("little-four-winds"))
        } else if windKinds.count == 3 {
            out.append(rules.award("big-three-winds"))
        } else if windKinds.count == 2 && windPairIs != nil && !windKinds.contains(windPairIs!) {
            out.append(rules.award("little-three-winds"))
        } else if windPungCount > 0 {
            if windPungsSeat > 0 {
                out.append(rules.award("pung-seat-wind", count: windPungsSeat))
            }
            if windPungsOther > 0 {
                out.append(rules.award("pung-other-wind", count: windPungsOther))
            }
        }

        return out
    }
}

// MARK: - Terminal / honor family

extension Scorer {
    func terminalAwards(hand: Hand, context _: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        let body = hand.allBodyTiles
        let allTerminalsOrHonors = body.allSatisfy { $0.isTerminal || $0.isHonor }
        let allTerminals = body.allSatisfy { $0.isTerminal }
        let allSimples = body.allSatisfy { $0.isSimple }

        if allTerminals {
            out.append(rules.award("all-terminals"))
        } else if allTerminalsOrHonors {
            out.append(rules.award("all-terminals-honors"))
        } else if allSimples {
            out.append(rules.award("all-simples"))
        }

        return out
    }
}

// MARK: - Special hands

extension Scorer {
    func specialAwards(hand: Hand, context: WinContext) -> [TaiAward] {
        var out: [TaiAward] = []

        // five-concealed-pungs (80): every body meld is a concealed pung/kong.
        // This subsumes the 4-concealed-pung award from setAwards; we'll drop that
        // one in the Scorer's post-processing — except we don't have a post-pass yet.
        // For now we keep both since the source table lists them separately and
        // coverage of this rare hand is important to flag.
        if hand.melds.allSatisfy({ ($0.kind == .pung || $0.kind == .kong) && $0.isConcealed }) {
            out.append(rules.award("five-concealed-pungs"))
        }

        // Heavenly / earthly / human hands (context flags).
        if context.heavenlyHand { out.append(rules.award("heavenly-hand")) }
        if context.earthlyHand { out.append(rules.award("earthly-hand")) }
        if context.humanHand { out.append(rules.award("human-hand")) }

        return out
    }
}
