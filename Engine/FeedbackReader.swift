import Foundation

struct FeedbackContext {
    /// The runner's easy-to-threshold pace in their own unit, used to turn "10 seconds slower" into a percentage.
    var basePaceSec: Double
    var miles: Bool
}

/// Reads the note a runner writes after a run and turns it into a small, bounded signal.
/// Ported from the cycling planner's note reader. Same rules:
///   dev  extra effort gap in RPE points (-1 to +1.5, steps of 0.5) added to the RPE gap
///   off  the note blames something outside the plan (sleep, illness, heat, weather, food, stress, kit):
///        the harder-than-planned part counts at half weight
///   cut  how much slower than planned the runner had to go, when they said so
enum FeedbackReader {

    static let causes: [String: String] = [
        "sleep": "a poor night or a long shift",
        "illness": "feeling unwell",
        "heat": "heat or humidity",
        "weather": "wind, rain or ice",
        "fuel": "not enough food",
        "stress": "stress or alcohol",
        "kit": "a kit, watch or treadmill problem"
    ]
    private static let causeOrder = ["sleep", "illness", "heat", "weather", "fuel", "stress", "kit"]

    // MARK: patterns (ICU regular expressions, applied to lower-case text)

    private static let causePatterns: [String: String] = [
        "sleep": #"\b(?:(?:poor|bad|terrible|rough|broken|little|short|no|lack of|not enough|rubbish|disturbed|interrupted|awful)\s+(?:night'?s?\s+)?sleep|(?:slept|sleeping)\s+(?:badly|poorly|terribly|little|rubbish|awfully)|didn'?t sleep|barely slept|sleep[- ]deprived|up (?:all night|half the night|with the (?:baby|kids?|toddler|newborn))|after (?:a |my |the )?(?:night|late|long|double) shift|night shift|worked (?:a )?(?:nights?|late))\b"#,
        "illness": #"\b(?:ill|sick|unwell|flu|covid|virus|stomach bug|sore throat|headache|migraine|fever|snotty|congested|under the weather|coming down with|(?:a|got a|had a) cold)\b"#,
        "heat": #"\b(?:too hot|boiling|sweltering|overheat(?:ed|ing)?|humid|humidity|stuffy|roasting|baking)\b"#,
        "weather": #"\b(?:headwind|strong wind|windy|gale|storm|icy|ice|snow|sleet|pouring|torrential|freezing|slippery)\b"#,
        "fuel": #"\b(?:didn'?t eat|hadn'?t eaten|skipped (?:breakfast|lunch|dinner|my meal|food)|no (?:breakfast|food|carbs)|under-?fuel(?:led)?|bonk(?:ed|ing)?|hit the wall|ran out of (?:energy|fuel|steam)|hungry|empty tank|forgot to eat|not enough (?:food|carbs|fuel))\b"#,
        "stress": #"\b(?:stress(?:ed|ful)?|anxious|hungover|hangover|drinks? last night|beers?|wine|alcohol)\b"#,
        "kit": #"\b(?:blister(?:s|ed)?|chaf(?:e|ed|ing)|(?:wrong|new|worn|tight|heavy) shoes|watch (?:died|froze|glitch\w*|lost)|gps (?:issue|problem|glitch|drop\w*|was off|wasn'?t working)|treadmill (?:issue|problem|glitch|stopped|was off|belt)|dropouts?|disconnect(?:ed|ion)|calibrat\w*)\b"#
    ]

    private static let failPattern = #"\b(?:(?:couldn'?t|could not|unable to|didn'?t|did not|failed to|wasn'?t able to)\s+(?:quite\s+)?(?:finish|complete|get through|make|manage|hit|reach|keep|hold(?!\s+back))|bail(?:ed)?|abandon(?:ed)?|stopped (?:early|short)|cut (?:it|the (?:session|run)) short|packed (?:it )?in|gave up|blew up|blown up|bonk(?:ed|ing)?|hit the wall|ran out of (?:energy|fuel|steam)|fell off the pace|faded|fading|died|cracked|fell apart|had to walk|walked|(?:skipped|missed|dropped|binned|ditched) (?:the )?(?:last|final|remaining) (?:\w+ )?(?:reps?|intervals?|sets?|efforts?|blocks?))\b"#

    private static let easePattern = #"\b(?:had to (?:knock|drop|ease|back|cut|reduce|lower|take|dial|slow)|(?:knocked|dropped|eased|backed|dialled|dialed|slowed) (?:it |the \w+ |pace |intensity |the target )?(?:down|off|back))\b"#

    private static let hardPattern = #"\b(?:brutal|grim|horrible|awful|terrible|dreadful|ground out|hung on|hanging on|struggl\w+|suffer\w*|really hard|very hard|so hard|hard going|hard work|harder than (?:it should|expected|usual|normal|last|planned)|(?:legs?|body)\s+(?:felt\s+|were\s+|was\s+|feel\s+|are\s+)?(?:a\s+bit\s+|a\s+little\s+|bit\s+|really\s+|very\s+|so\s+|quite\s+|pretty\s+)?(?:heavy|dead|flat|tired|empty|cooked|fried|shot|knackered|wrecked|sluggish|lethargic|sore|stiff|drained|weak)|(?:felt|feel|feeling)\s+(?:a\s+bit\s+|a\s+little\s+|bit\s+|really\s+|very\s+|so\s+|quite\s+|pretty\s+)?(?:heavy|dead|tired|empty|cooked|fried|shot|knackered|wrecked|sluggish|lethargic|sore|stiff|drained|weak|rough|rubbish)|(?:heavy|dead|tired) legs|no (?:power|snap|pop|legs|sparkle)|off (?:day|form)|(?:wasn'?t|was not|isn'?t|not|never)\s+(?:very\s+|that\s+|at all\s+)?easy|(?:not|wasn'?t|weren'?t|didn'?t feel|did not feel)\s+(?:great|good|right|feeling it|there))\b"#

    private static let easyPattern = #"\b(?:too easy|felt easy|felt (?:great|good|strong|fresh|smooth|comfortable|brilliant|fantastic|amazing|flying)|(?:legs|body) (?:felt |were |was )?(?:great|good|strong|fresh|flying|brilliant)|more in the tank|plenty (?:left|in the tank)|(?:could|should) (?:have |of )?(?:done|gone|held|pushed|managed|run) (?:more|harder|faster|higher|longer)|had (?:more|loads|plenty) (?:left|to give)|cruised|bumped (?:it )?up|raised (?:it|the|pace|intensity)|upped (?:it|the|pace|intensity)|stronger than (?:expected|usual|last)|easier than (?:expected|usual|last|planned))\b"#

    private static let veryEasyPattern = #"\b(?:way too easy|far too easy|much too easy|ridiculously easy|piece of cake|barely broke a sweat)\b"#

    // MARK: helpers

    private static func has(_ pattern: String, _ s: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func allMatches(_ pattern: String, in s: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }

    private static func clock(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> Double? {
        guard let a = group(m, i, in: s), let b = group(m, i + 1, in: s), let mm = Double(a), let ss = Double(b), ss < 60 else { return nil }
        return mm * 60 + ss
    }

    /// True when the words just before a match negate it ("wasn't too easy").
    private static func negated(_ t: String, before index: String.Index) -> Bool {
        let start = t.index(index, offsetBy: -26, limitedBy: t.startIndex) ?? t.startIndex
        return has(#"\b(?:not|never|no|\w+n't)\s+(?:\w+\s+){0,2}$"#, String(t[start..<index]))
    }

    private static func paceOK(_ a: Double, _ b: Double) -> Bool {
        a >= 150 && a <= 1200 && b >= 150 && b <= 1200 && b > a && (b - a) / b <= 0.5
    }

    private struct Cut { var pct: Double; var from: Double?; var to: Double? }

    /// "from 4:10 to 4:20/km", "4:20 instead of 4:10", "had to drop to 4:30", "slowed by 10 seconds", "eased off by 5%"
    private static func findCut(_ t: String, _ ctx: FeedbackContext) -> Cut? {
        let unit = #"(?:/\s*\w+|per\s*\w+)?"#
        let pace = #"(\d{1,2}):(\d{2})"#

        let re1 = #"(?:from|was|were|target(?:ed)?|planned|prescribed|aiming for|should(?:'ve| have) been)\s*(?:at\s*)?"# + pace + #"\s*"# + unit + #"\s*(?:down\s+|back\s+)?(?:to|at|->|→)\s*"# + pace
        for m in allMatches(re1, in: t) {
            if let a = clock(m, 1, in: t), let b = clock(m, 3, in: t), paceOK(a, b) { return Cut(pct: (b - a) / b, from: a, to: b) }
        }
        let re2 = pace + #"\s*"# + unit + #"\s*(?:instead of|rather than|not|vs\.?|versus)\s*"# + pace
        for m in allMatches(re2, in: t) {
            if let b = clock(m, 1, in: t), let a = clock(m, 3, in: t), paceOK(a, b) { return Cut(pct: (b - a) / b, from: a, to: b) }
        }
        let re5 = pace + #"\s*"# + unit + #"\s*(?:but\s+|and\s+|then\s+)?(?:only\s+|just\s+)?(?:managed|held|did|ran|got|hit|dropped (?:down )?to|fell (?:back )?to|slowed to|went down to|came down to|slipped to|eased to|backed off to|ended up (?:at|on)|settled (?:at|on|for))\s*"# + pace
        for m in allMatches(re5, in: t) {
            if let a = clock(m, 1, in: t), let b = clock(m, 3, in: t), paceOK(a, b) { return Cut(pct: (b - a) / b, from: a, to: b) }
        }
        let re4 = #"(?:dropped|slowed|eased|backed off|knocked|cut|reduced|took|lost|shaved)\s+(?:it |the \w+ |pace |my pace |the target |intensity )?(?:down |off |back )?(?:by\s+)?(\d{1,3})\s*(s\b|secs?|seconds?|%|percent)"#
        for m in allMatches(re4, in: t) {
            guard let nText = group(m, 1, in: t), let n = Double(nText), let u = group(m, 2, in: t) else { continue }
            if u == "%" || u == "percent" {
                if n >= 1 && n <= 50 { return Cut(pct: n / 100, from: nil, to: nil) }
            } else if ctx.basePaceSec > 0, n >= 3, n / ctx.basePaceSec <= 0.5 {
                return Cut(pct: n / (ctx.basePaceSec + n), from: nil, to: nil)
            }
        }
        return nil
    }

    // MARK: reading

    static func read(_ text: String, context ctx: FeedbackContext) -> FeedbackRead {
        let raw = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        let t = " " + raw.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) + " "

        let cut = findCut(t, ctx)
        let ease = has(easePattern, t)
        let fail = has(failPattern, t)
        let hard = has(hardPattern, t)

        var cutDev = 0.0
        if let c = cut {
            cutDev = c.pct >= 0.08 ? 1.5 : (c.pct >= 0.04 ? 1.0 : (c.pct >= 0.02 ? 0.5 : 0))
        } else if ease {
            cutDev = 0.5
        }
        var dev = max(cutDev, fail ? 1.5 : 0, hard ? 0.5 : 0)

        if dev == 0 {
            var easy = 0.0
            var negHit = false
            for m in allMatches(easyPattern, in: t) {
                guard let r = Range(m.range, in: t) else { continue }
                if negated(t, before: r.lowerBound) { negHit = true } else { easy = min(easy, -0.5) }
            }
            for m in allMatches(veryEasyPattern, in: t) {
                guard let r = Range(m.range, in: t) else { continue }
                if !negated(t, before: r.lowerBound) { easy = -1 }
            }
            if negHit && easy == 0 { dev = 0.5 } else { dev = easy }
        }

        var cause: String?
        for k in causeOrder {
            if let p = causePatterns[k], has(p, t) { cause = k; break }
        }
        dev = min(max((dev * 2).rounded() / 2, -1), 1.5)

        var r = FeedbackRead(text: raw, dev: dev, cutPct: cut?.pct, cutFromSec: cut?.from, cutToSec: cut?.to,
                             ease: ease, fail: fail, off: cause != nil, cause: cause, summary: "")
        r.summary = summary(r, ctx)
        return r
    }

    static func summary(_ r: FeedbackRead, _ ctx: FeedbackContext) -> String {
        var p: [String] = []
        func unit(_ s: Double) -> String { Fmt.pace(s, miles: ctx.miles) }
        if let a = r.cutFromSec, let b = r.cutToSec, let pct = r.cutPct {
            p.append("You slowed from \(unit(a)) to \(unit(b)) (about \(Int((pct * 100).rounded()))%).")
        } else if let pct = r.cutPct {
            p.append("You slowed by about \(Int((pct * 100).rounded()))%.")
        } else if r.ease {
            p.append("You had to ease the pace.")
        }
        if r.fail { p.append("You did not manage all of it.") }
        if r.cutPct == nil && !r.ease && !r.fail && r.dev > 0 { p.append("You said it felt worse than it should have.") }
        if r.dev < 0 { p.append("You said it felt easier than planned.") }
        if let c = r.cause, let label = causes[c] {
            if r.dev > 0 { p.append("That looks like \(label) rather than the plan, so it counts at half weight.") }
            else { p.append("You mentioned \(label), which is noted.") }
        }
        return p.isEmpty ? "Nothing here changes the plan." : p.joined(separator: " ")
    }
}
