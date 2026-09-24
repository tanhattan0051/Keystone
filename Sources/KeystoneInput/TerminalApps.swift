// TerminalApps.swift — pure bundle-id check for "the app accepting keyboard
// input is a terminal emulator", plus the pure gate for whether any
// capitalization path can fire at all, both used by App/AppModel.swift to
// mask sentence auto-capitalize (autoCapitalize/macroAutoCapitalize). No
// AppKit here — see DECISIONS.md "Không tự viết hoa trong Terminal".
public enum TerminalApps {
    /// Exact bundle ids of known terminal emulators, verified 2026-09-24
    /// (sources in DECISIONS.md "Không tự viết hoa trong Terminal"). An
    /// unlisted terminal just needs its id added here.
    static let knownBundleIDs: [String] = [
        // Apple / mainstream
        "com.apple.Terminal",            // Terminal
        "com.googlecode.iterm2",         // iTerm2
        "dev.warp.Warp-Stable",          // Warp
        "dev.warp.Warp-Preview",         // Warp Preview
        "com.mitchellh.ghostty",         // Ghostty
        "net.kovidgoyal.kitty",          // kitty
        "org.alacritty",                 // Alacritty
        "com.github.wez.wezterm",        // WezTerm
        "co.zeit.hyper",                 // Hyper
        "org.tabby",                     // Tabby
        "com.raphaelamorim.rio",         // Rio
        "com.raphaelamorim.canario",     // Canario
        "dev.commandline.waveterm",      // Wave
        "org.contourterminal.Contour",   // Contour
        "com.extraterm.extraterm",       // Extraterm
        "com.yourcompany.cool-retro-term", // cool-retro-term (ships with Qt's placeholder id)
        "dev.archipelago",               // Archipelago
        "io.appmakes.otty",              // Otty
        // SSH clients / connection managers
        "com.termius.mac",               // Termius (Mac App Store)
        "com.termius-dmg.mac",           // Termius (direct download)
        "com.panic.prompt.3",            // Prompt 3
        "com.vandyke.SecureCRT",         // SecureCRT
        "com.lemonmojo.RoyalTSX.App",    // Royal TSX
        "org.electerm.electerm",         // Electerm
        "KingToolbox.WindTerm",          // WindTerm
        "app.termix.Termix",             // Termix
        "io.coressh.shell",              // Core Shell
        "com.emtec.zoc9",                // ZOC 9
        "com.emtec.zoc7",                // ZOC 7
        "com.netsarang.portx",           // PortX
    ]

    private static let lowercasedIDs: Set<String> = Set(knownBundleIDs.map { $0.lowercased() })

    /// Case-insensitive because LaunchServices itself treats bundle ids
    /// case-insensitively and sources disagree on case (e.g. Prompt 3 is
    /// documented as both `com.panic.Prompt.3` and `com.panic.prompt.3`).
    /// Exact match rather than prefix/suffix because a shared vendor prefix
    /// like `com.panic.` or `com.apple.` also covers non-terminal apps (Nova,
    /// Transmit, TextEdit).
    public static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return lowercasedIDs.contains(bundleID.lowercased())
    }

    /// Whether ANY capitalization path can actually fire, given the current
    /// toggles — the terminal mask only matters, and the AX focus read is
    /// only worth running, while this is true. Mirrors
    /// `EngineController.handle`'s own gate: while Vietnamese is active, the
    /// engine's usual `autoCapitalize`/macro-triggered paths run; while
    /// inactive, `handle` only routes through the engine at all (the
    /// "English-mode macros" path) when BOTH `macrosEnabled` AND
    /// `macrosExpandWhenVietnameseOff` are on, so capitalization there can
    /// only come from `macroAutoCapitalize` on top of that same pair.
    public static func capitalizationCanFire(
        vietnameseEnabled: Bool,
        autoCapitalize: Bool,
        macrosEnabled: Bool,
        macroAutoCapitalize: Bool,
        macrosExpandWhenVietnameseOff: Bool
    ) -> Bool {
        vietnameseEnabled
            ? (autoCapitalize || (macrosEnabled && macroAutoCapitalize))
            : (macrosEnabled && macrosExpandWhenVietnameseOff && macroAutoCapitalize)
    }
}
