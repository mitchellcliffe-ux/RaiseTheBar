import Foundation

struct FuelAdvice {
    var needsCarbs: Bool
    var before: String
    var during: String
    var caffeine: String?
    var note: String
}

/// Carbohydrate guidance before and during a run. Written for running, so it sits at the low end of the cycling numbers:
/// running upsets the stomach more, and a runner cannot sip while bouncing.
///
/// Starting points to check before you publish: Burke et al. 2011 (J Sports Sci), the 2016 joint position stand of the
/// Academy of Nutrition and Dietetics, Dietitians of Canada and the ACSM (Thomas, Erdman, Burke), and Jeukendrup 2014 (Sports Med).
/// This is general guidance, not medical advice; people with diabetes or other conditions should get individual advice.
enum FuelPlan {

    private static func round5(_ x: Double) -> Int { Int((x / 5).rounded()) * 5 }
    private static func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func advice(kind: SessionKind, minutes: Int, weightKg: Double, gut: Gut, caffeine: Bool) -> FuelAdvice {
        let load = SessionLibrary.info(kind).load
        let hard = load == .hard
        let d = minutes
        let w = max(weightKg, 30)
        let note = "Practise in training, not on race day. Running is harder on the stomach than cycling, so start at the low end and build up. Sources to check: Burke et al. 2011; Thomas, Erdman and Burke 2016; Jeukendrup 2014. General guidance, not medical advice."

        if kind == .strength || kind == .recovery {
            return FuelAdvice(needsCarbs: false,
                              before: "Nothing special. Eat normally.",
                              during: "None needed.",
                              caffeine: nil, note: note)
        }

        // Before
        let before: String
        if d < 45 && !hard {
            before = "Nothing special. Run after your normal meal or fasted, whichever you prefer."
        } else if d < 75 && !hard {
            before = "Optional light snack (about 30 g of carbohydrate, such as a banana or toast) about an hour before if you feel hungry."
        } else {
            var lo = 1.5, hi = 2.5
            switch gut {
            case .sensitive: lo = 1.0; hi = 1.5
            case .normal: lo = 1.5; hi = 2.5
            case .robust: lo = 2.0; hi = 3.0
            }
            if d >= 120 || kind == .race { hi += 0.5 }
            let hours = gut == .sensitive ? "3 hours" : "2 to 3 hours"
            before = "A meal with about \(round5(w * lo)) to \(round5(w * hi)) g of carbohydrate (\(String(format: "%.1f", lo)) to \(String(format: "%.1f", hi)) g per kg) \(hours) before. A small carb snack of about 30 g 30 to 60 minutes before is fine if you tolerate it."
        }

        // During
        var during: String
        var needs = false
        if d < 45 {
            during = "None needed."
        } else if d < 60 {
            during = hard
                ? "None needed. For a hard effort this long a mouth rinse with a sports drink can help but is optional."
                : "None needed."
        } else if d < 90 {
            if hard || kind == .longRun {
                during = "About 30 g in the second half (one gel or a few chews). Optional if the session is easy."
                needs = true
            } else {
                during = "Optional. Up to 30 g if you want it. Good practice for race-day fuelling."
            }
        } else if d <= 150 {
            let range: String
            switch gut {
            case .sensitive: range = "about 30 g an hour"
            case .normal: range = "30 to 45 g an hour"
            case .robust: range = "40 to 60 g an hour"
            }
            during = "\(capitalised(range)), starting around 30 to 40 minutes in. Take it in small amounts every 15 to 20 minutes."
            needs = true
        } else {
            let range: String
            switch gut {
            case .sensitive: range = "30 to 40 g an hour"
            case .normal: range = "40 to 60 g an hour"
            case .robust: range = "60 g an hour, and up to 90 g only if you have trained your gut with a glucose and fructose mix"
            }
            during = "\(capitalised(range)). Take it in small amounts every 15 to 20 minutes."
            needs = true
        }
        if d >= 60 { during += " Drink to thirst, and add salt if it is hot or you sweat heavily." }

        // Caffeine
        var caf: String?
        if caffeine && (hard || d >= 90) && kind != .openers {
            caf = "Optional: about 3 mg per kg (roughly \(Int((w * 3 / 10).rounded()) * 10) mg) about an hour before. Avoid it late in the day."
        }

        return FuelAdvice(needsCarbs: needs || !before.hasPrefix("Nothing"), before: before, during: during, caffeine: caf, note: note)
    }
}
