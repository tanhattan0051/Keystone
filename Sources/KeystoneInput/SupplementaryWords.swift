// SupplementaryWords.swift — words missing from the system word list
// (`/usr/share/dict/words`, the 1934 Webster corpus): internet, software and
// brand vocabulary that people type in chat and at work every day, including
// hosting/dev/sysadmin terms (the maintainer works at a Vietnam-market
// hosting company, Vietnix) — merged into the lexicon `RestoreDecision`
// consults by `LexiconLoader`. See DECISIONS.md "Restore chooses the
// composed word when it is the real one".
//
// Three SEPARATE lists doing three different jobs. `all` and
// `protectedRealWords` are merged into the lexicon by `LexiconLoader`;
// `forceEnglishWords` is a DIFFERENT, standalone list installed onto
// `Engine.forceEnglish` (via `EngineController.setForceEnglish`), not merged
// into the lexicon at all:
//   - `all`          — modern words the 1934 list never had a chance to
//                       include, so the COMPOSED (cancel-habit) spelling of
//                       one of them is recognized as a word (`gooogle`→
//                       `google`, `vietnixx`→`vietnix`).
//   - `protectedRealWords` — real, OLD English words (inflections, loanwords,
//                       acronyms, surnames) the 1934 list still lacks, whose
//                       *raw* natural typing must be recognized so it beats a
//                       coincidentally-real COMPOSED collapse. See that
//                       list's own header below.
//   - `forceEnglishWords` — a curated whitelist (Lớp B) of English words that
//                       already compose a VALID Vietnamese syllable (so they
//                       never reach the lexicon/restore machinery above at
//                       all) and must win over that Vietnamese homograph
//                       anyway — `test`→tét, `reset`→rết. See that list's own
//                       header below and DECISIONS.md "Force-English
//                       whitelist (Lớp B)".
//
// A word with no vowel is never added to either list: `Engine.finalize` only
// enters the restore/lexicon branch when the composition has a vowel cell
// (`compHasVowel`), so a vowel-less entry could never be looked up — dead
// weight. Likewise a word that already types as a VALID Vietnamese syllable
// (no diacritic needed, e.g. `cors`, `meme`, `orm`, `saas`) never reaches
// `RestoreDecision` either (`restoreIfInvalid`'s `!isValid(comp)` guard skips
// it) — also dead weight, also omitted.
//
// All lowercase; `LexiconLoaderTests` pins that constraint plus "no
// duplicates" for each list independently, and that the two lists are
// disjoint. Only real, widely-typed words — no filler.

public enum SupplementaryWords {
    /// Everyday internet/software/brand words + Vietnam-market hosting/
    /// telecom/dev/sysadmin vocabulary + regular inflections of this list's
    /// own nouns and verbs. Grouped by theme for readability only — the
    /// lexicon itself is a flat, unordered set. `vietnamMarket` (and within
    /// it, `vietnix`) comes first deliberately: it is the word this feature
    /// was built to stop mangling for the maintainer.
    public static let all: [String] = vietnamMarket
        + brandsAndProducts
        + internetAndNetworking
        + softwareAndDev
        + hostingAndSysadmin
        + sysadminDevTokens
        + socialAndChat
        + inflections

    // MARK: - Vietnam market (Vietnix vocabulary)

    private static let vietnamMarket: [String] = [
        "vietnix",
        "viettel", "vnpt", "fpt", "mobifone", "vinaphone", "matbao", "pavietnam",
        "nhanhoa", "tenten", "vinahost", "azdigi", "bizfly", "zalopay", "momo",
        "shopee", "lazada", "tiki",
    ]

    // MARK: - Brands & products

    private static let brandsAndProducts: [String] = [
        "google", "gmail", "youtube", "facebook", "instagram", "tiktok",
        "twitter", "zalo", "messenger", "whatsapp", "telegram", "github",
        "gitlab", "bitbucket", "linkedin", "pinterest", "reddit",
        "wikipedia", "amazon", "netflix", "spotify", "discord", "slack",
        "zoom", "skype", "dropbox", "paypal", "stripe", "shopify",
        "wordpress", "drupal", "joomla", "magento", "woocommerce", "canva",
        "figma", "notion", "trello", "asana", "jira", "confluence",
        "salesforce", "oracle", "microsoft", "apple", "iphone", "ipad",
        "ipod", "macbook", "imac", "airpods", "android", "samsung",
        "xiaomi", "huawei", "oppo", "vivo", "nokia", "blackberry",
        "cloudflare", "godaddy", "namecheap", "digitalocean", "linode",
        "vultr", "heroku", "vercel", "netlify",
    ]

    // MARK: - Internet & networking
    //
    // No-vowel entries dropped here vs. an earlier draft (dead weight — see
    // this file's header): http, https, dns, ssl, tls, vpn, cdn.

    private static let internetAndNetworking: [String] = [
        "email", "website", "webpage", "homepage", "online", "offline",
        "internet", "wifi", "bluetooth", "hotspot", "router", "modem",
        "firewall", "malware", "spyware", "ransomware", "phishing",
        "hacker", "hacking", "login", "logout", "signup", "signin",
        "signout", "username", "download", "upload", "inbox", "outbox",
        "attachment", "attachments", "browser", "bookmark", "bookmarks",
        "cookie", "cookies", "spam", "url", "urls",
        "bandwidth", "uptime",
        "downtime", "latency", "backup", "blockchain", "bitcoin",
        "ethereum", "crypto", "cryptocurrency",
    ]

    // MARK: - Software & dev
    //
    // No-vowel entries dropped: html, css, npm, xml, ssh, ftp, sftp, sql,
    // mvc, jwt, xss. Valid-Vietnamese-typing entries dropped: cors, orm,
    // saas, paas (see this file's header).

    private static let softwareAndDev: [String] = [
        "app", "apps", "database", "backend", "frontend", "fullstack",
        "api", "apis", "javascript", "typescript",
        "python", "xcode", "webpack", "docker", "kubernetes",
        "jenkins", "terraform", "ansible", "json", "yaml",
        "nosql", "crud",
        "oauth", "microservices", "serverless",
        "iaas", "devops", "cicd", "localhost", "sandbox", "debug",
        "debugging", "breakpoint", "refactor", "refactoring", "commit",
        "commits", "merge", "rebase", "codebase", "repo", "repos",
        "clone", "gitignore", "readme", "screenshot", "screenshots",
        "clipboard", "keyboard", "touchscreen", "touchpad", "trackpad",
        "webcam", "smartwatch", "smartphone", "laptop", "desktop",
        "motherboard", "harddrive", "firmware", "plugin", "plugins",
        "addon", "addons", "widget", "widgets", "template", "templates",
        "framework", "frameworks", "chatbot", "chatbots", "changelog",
        "deploy", "deployment", "rollback", "staging", "dashboard",
        "analytics", "roadmap", "milestone", "sprint", "standup",
        "backlog",
    ]

    // MARK: - Hosting & sysadmin (Vietnix vocabulary)
    //
    // No-vowel entries dropped: whm, vps.

    private static let hostingAndSysadmin: [String] = [
        "hosting", "domain", "subdomain", "nameserver", "dedicated",
        "colocation", "cpanel", "directadmin", "plesk",
        "nginx", "apache", "mysql", "mariadb", "postgres", "postgresql",
        "mongodb", "redis", "memcached", "elasticsearch", "rabbitmq",
        "kafka", "grafana", "prometheus", "datadog", "letsencrypt",
        "htaccess", "phpmyadmin", "linux", "ubuntu", "debian", "centos",
        "fedora", "macos",
    ]

    // MARK: - Sysadmin / dev tokens (with vowels — a no-vowel token like
    // `dns`/`ssl` can never reach `RestoreDecision`, see this file's header)

    private static let sysadminDevTokens: [String] = [
        "systemctl", "openssl", "stderr", "stdout", "sudoers", "iptables",
        "xargs", "dmarc", "exim", "iframe", "nodejs", "haproxy", "firebase",
        "pytest", "eslint", "websocket", "vhost", "laravel", "jquery",
        "flexbox",
    ]

    // MARK: - Social & chat
    //
    // No-vowel entries dropped: wfh. Valid-Vietnamese-typing entries
    // dropped: meme, memes.

    private static let socialAndChat: [String] = [
        "okay", "emoji", "emojis", "hashtag", "selfie", "selfies",
        "vlog", "vlogger", "blog", "blogger", "blogging", "podcast",
        "podcasts", "livestream", "streaming", "streamer", "gamer",
        "gaming", "esports", "viral", "trending",
        "follower", "followers", "subscriber", "subscribers",
        "unfollow", "unsubscribe", "retweet", "influencer",
        "influencers", "startup", "startups", "freelancer", "freelance",
        "remote", "crowdfunding", "fintech", "ecommerce",
        "marketplace",
    ]

    // MARK: - Inflections
    //
    // Regular plural/past/-ing forms of nouns and verbs already elsewhere in
    // this list (the base form doesn't imply the inflection is in
    // `/usr/share/dict/words` — often it isn't), plus a handful of common
    // Webster-missing inflections the maintainer types daily that aren't
    // derived from any word above.

    private static let inflections: [String] = [
        // Of this list's own nouns/verbs.
        "emails", "websites", "domains", "servers", "backups", "uploads",
        "downloads", "logins", "deployed", "deploying",
        // Common Webster-missing inflections, not derived from the above.
        "tasks", "passed", "errors", "fixes", "offsets", "hashes",
        "processes", "processed", "files", "users",
    ]

    /// Real, OLD English words — inflections, loanwords, acronyms, surnames
    /// — that `/usr/share/dict/words` (1934 Webster) still lacks, found by an
    /// exhaustive offline search: each one's COMPOSED (collapsed-doubled-
    /// letter) form happens to already be a different real word in the
    /// system list, so typing the word NATURALLY (raw) would otherwise lose
    /// to that unrelated word — `fussed`→`fused`, `jarred`→`jared`,
    /// `OSS`→`OS`, `Herr`→`Her`, `Kerr`→`Ker`. Adding them here makes `raw`
    /// itself recognized, so `RestoreDecision.choose`'s `!lexicon.contains(raw)`
    /// requirement keeps `.raw` winning — exactly HEAD's (pre-lexicon)
    /// behavior for these words. This list protects RAW typing; `all` above
    /// is what enables the COMPOSED side. See DECISIONS.md "Restore chooses
    /// the composed word when it is the real one" and its known-limitation
    /// note: a real word missing from BOTH lists can still collapse this way
    /// — this list covers the cases an exhaustive search actually found, not
    /// every English word.
    public static let protectedRealWords: [String] = [
        "fussed", "mussed", "mussing", "jarred", "purred", "parring", "riffling",
        "coiffed", "squirreling", "moussing", "suss", "terra", "torr", "iff", "barre",
        "lassi", "frisson", "farro", "barrie", "currie", "buffo", "triffid",
        "transsonic", "hassidic", "hassidim", "chassidim", "mycorrhiza", "degass",
        "unbiassed", "aaa", "iss", "poisson", "cassava", "cassaba", "hassan",
        "parramatta", "oss", "herr", "kerr", "orr", "starr", "barr", "neff", "foxx", "maxx",
    ]

    /// Force-English whitelist (Lớp B): English words whose Telex keystrokes ALSO
    /// spell a VALID Vietnamese syllable (so `restoreIfInvalid` never reverts them
    /// and they stay Vietnamese today: `test`→tét, `reset`→rết, `row`→rơ, …).
    /// When `spellCheck` is on, `Engine.finalize` commits the raw English for a
    /// word in this list instead of the Vietnamese homograph. Each entry is a
    /// deliberate choice to SHADOW its Vietnamese collision, so keep it to words
    /// whose English use vastly outweighs the (usually rare) Vietnamese word, and
    /// only real Lớp B words — a word that already types as itself, or reverts via
    /// restore-if-invalid, does not belong here. All lowercase, no duplicates,
    /// disjoint from `all`/`protectedRealWords`.
    public static let forceEnglishWords: [String] = [
        "reset", "test", "row", "box", "six", "refer", "defer",
    ]
}
