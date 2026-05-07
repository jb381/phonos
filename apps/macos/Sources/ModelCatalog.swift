enum ModelCatalog {
    static func description(for model: String) -> String {
        switch model {
        case "tiny.en":
            return "Fastest, lowest memory; good for short dictation."
        case "base.en":
            return "Fast and lightweight; balanced default for most Macs."
        case "small.en":
            return "Better accuracy with moderate CPU and memory cost."
        case "medium.en":
            return "Higher accuracy; noticeably slower on CPU."
        case "turbo":
            return "Speed-optimized multilingual model."
        case "distil-large-v3":
            return "Strong quality with lower cost than large-v3."
        case "large-v3":
            return "Highest quality; slow and memory-heavy on CPU."
        default:
            return "Custom configured model."
        }
    }

    static func isLargeCPUModel(_ model: String) -> Bool {
        model == "medium.en" || model == "distil-large-v3" || model == "large-v3"
    }
}
