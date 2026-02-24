# nu_script_hnews - Hacker News Terminal Reader
#
# Fetches and displays top Hacker News stories with caching,
# rich formatting, and parallel fetching.
#
# Icon mode priority: --emoji / --text flag > $env.NERD_FONTS == "1" > plain text
#
# Examples:
#   > hn                        # Fetch top 15 stories
#   > hn 30                     # Fetch top 30
#   > hn -N                     # Fetch new stories
#   > hn -b                     # Fetch best stories
#   > hn -a                     # Fetch Ask HN stories
#   > hn -f                     # Force refresh (bypass cache)
#   > hn -j                     # Output raw JSON
#   > hn -e                     # Use emoji for link column
#   > hn -t                     # Plain text mode, no icons or color
#
# Requires Nushell 0.97+ for $nu.cache-dir support.

const COL_SCORE_MIN_WIDTH = 50
const COL_CMTS_MIN_WIDTH = 60
const COL_AGE_MIN_WIDTH = 60
const COL_BY_MIN_WIDTH = 70
const COL_DOMAIN_MIN_WIDTH = 80
const COL_TYPE_MIN_WIDTH = 90

# Estimated widths for budget calculation
const WIDTH_BASE = 9    # Border(1) + Rank(5) + TitlePad/Border(3)
const WIDTH_SCORE = 8   # 5+2+1
const WIDTH_CMTS = 7    # 4+2+1
const WIDTH_AGE = 6     # 3+2+1
const WIDTH_BY = 18     # 15+2+1
const WIDTH_DOMAIN = 23 # ~20+2+1
const WIDTH_TYPE = 7    # 4+2+1

const DOMAIN_ICONS = {
    "github.com": { nerd: "", emoji: "🐙", color: "#ffffff", tag: "git" }
    "arxiv.org": { nerd: "", emoji: "📄", color: "#b31b1b", tag: "sci" }
    "youtube.com": { nerd: "󰗃", emoji: "📺", color: "#ff0000", tag: "vid" }
    "en.wikipedia.org": { nerd: "󰖬", emoji: "🌐", color: "#e6e6e6", tag: "wiki" }
    "openai.com": { nerd: "", emoji: "🤖", color: "#74aa9c", tag: "ai" }
    "huggingface.co": { nerd: "", emoji: "🤗", color: "#ff9000", tag: "ai" }
    "substack.com": { nerd: "󱕬", emoji: "📧", color: "#ff6719", tag: "news" }
    "nytimes.com": { nerd: "", emoji: "🗞️", color: "#ffffff", tag: "news" }
    "bloomberg.com": { nerd: "󰓗", emoji: "📈", color: "#2800d7", tag: "biz" }
    "theverge.com": { nerd: "󱐋", emoji: "⚡", color: "#ff005a", tag: "tech" }
    "arstechnica.com": { nerd: "󰭟", emoji: "🛰️", color: "#ff4e00", tag: "tech" }
    "medium.com": { nerd: "", emoji: "📝", color: "#ffffff", tag: "blog" }
    "economist.com": { nerd: "󰦨", emoji: "📊", color: "#e3120b", tag: "econ" }
    "wsj.com": { nerd: "", emoji: "📉", color: "#000000", tag: "biz" }
    "reuters.com": { nerd: "󰎕", emoji: "🌍", color: "#ff8000", tag: "news" }
    "paulgraham.com": { nerd: "󰠮", emoji: "🍦", color: "#f60000", tag: "yc" }
    "danluu.com": { nerd: "󰙨", emoji: "💾", color: "#4caf50", tag: "blog" }
    "simonwillison.net": { nerd: "󱚣", emoji: "🧠", color: "#ffcc00", tag: "blog" }
    "jvns.ca": { nerd: "󱫐", emoji: "🪄", color: "#f06000", tag: "blog" }
    "blog.cloudflare.com": { nerd: "", emoji: "☁️", color: "#f38020", tag: "sys" }
}

const TYPE_ICONS = {
    ask: { nerd: "󰆆", emoji: "❓" }
    show: { nerd: "󰈈", emoji: "👀" }
    launch: { nerd: "󰑣", emoji: "🚀" }
    default: { nerd: "", emoji: "•" }
}

# Format a score with color based on popularity
def format-score [score: int]: nothing -> string {
    if $score >= 300 {
        $"(ansi red_bold)($score)(ansi reset)"
    } else if $score >= 100 {
        $"(ansi yellow)($score)(ansi reset)"
    } else {
        $"(ansi green)($score)(ansi reset)"
    }
}

# Format a comment count with color
def format-comments [count: int]: nothing -> string {
    if $count >= 200 {
        $"(ansi cyan_bold)($count)(ansi reset)"
    } else if $count >= 50 {
        $"(ansi cyan)($count)(ansi reset)"
    } else {
        $"($count)"
    }
}

# Extract the bare domain from a URL (removes protocol and www)
def parse-domain [url: string]: nothing -> string {
    let domain = ($url | split row "/" | get 2)
    if ($domain | str starts-with "www.") {
        $domain | str substring 4..
    } else {
        $domain
    }
}

# Format the domain from a URL
def format-domain [url: string, mode: string]: nothing -> string {
    if ($url | is-empty) {
        if $mode == "text" {
            "self"
        } else {
            $"(ansi light_gray)hn(ansi reset)"
        }
    } else {
        parse-domain $url
    }
}

# Lookup domain info from URL
def lookup-domain-info [url: string]: nothing -> any {
    if ($url | is-empty) {
        null
    } else {
        let bare_domain = (parse-domain $url)
        let match = ($DOMAIN_ICONS | transpose key info | where {|it| ($bare_domain | str downcase) | str contains $it.key})
        if ($match | is-empty) {
            null
        } else {
            $match | first | get info
        }
    }
}

# Detect post type tag (ask, show, launch, or domain tag)
export def detect-post-type [title: string, url: string]: nothing -> string {
    let lower = ($title | str downcase)
    if ($lower | str starts-with "ask hn:") {
        "ask"
    } else if ($lower | str starts-with "show hn:") {
        "show"
    } else if ($lower | str starts-with "launch hn:") {
        "launch"
    } else {
        let info = (lookup-domain-info $url)
        if ($info | is-not-empty) and ($info.tag? | is-not-empty) {
            $info.tag
        } else {
            ""
        }
    }
}

# Format the post type icon/text
def format-type-icon [post_type: string, domain_info: any, icon_mode: string]: nothing -> string {
    if $post_type == "ask" {
        let icon = if $icon_mode == "text" { "ask" } else if $icon_mode == "emoji" { $TYPE_ICONS.ask.emoji } else { $TYPE_ICONS.ask.nerd }
        $"(ansi yellow)($icon)(ansi reset)"
    } else if $post_type == "show" {
        let icon = if $icon_mode == "text" { "show" } else if $icon_mode == "emoji" { $TYPE_ICONS.show.emoji } else { $TYPE_ICONS.show.nerd }
        $"(ansi green)($icon)(ansi reset)"
    } else if $post_type == "launch" {
        let icon = if $icon_mode == "text" { "launch" } else if $icon_mode == "emoji" { $TYPE_ICONS.launch.emoji } else { $TYPE_ICONS.launch.nerd }
        $"(ansi red)($icon)(ansi reset)"
    } else {
        if $icon_mode == "text" {
            $post_type
        } else {
            let domain_icon = if ($domain_info | is-not-empty) {
                let icon = if $icon_mode == "emoji" { $domain_info.emoji } else { $domain_info.nerd }
                if $icon_mode == "nerd" and ($domain_info.color? | is-not-empty) {
                    $"(ansi ($domain_info.color))($icon)(ansi reset)"
                } else {
                    $icon
                }
            } else {
                null
            }

            if ($domain_icon | is-not-empty) {
                $domain_icon
            } else {
                let icon = if $icon_mode == "emoji" { $TYPE_ICONS.default.emoji } else { $TYPE_ICONS.default.nerd }
                $"(ansi light_gray)($icon)(ansi reset)"
            }
        }
    }
}

# Strip HN prefixes from title
def strip-hn-prefix [title: string]: nothing -> string {
    $title | str replace --regex '^(?i)(ask|show|launch) hn: ' ''
}

# Format relative time (age)
def format-age [time: int]: nothing -> string {
    let now_sec = (date now | format date '%s' | into int)
    let diff = ($now_sec - $time)

    if $diff < 60 {
        $"($diff | into int)s"
    } else if $diff < 3600 {
        $"(($diff / 60) | into int)m"
    } else if $diff < 86400 {
        $"(($diff / 3600) | into int)h"
    } else if $diff < 604800 {
        $"(($diff / 86400) | into int)d"
    } else {
        $"(($diff / 604800) | into int)w"
    }
}

# Re-order par-each results to match the original ID ordering,
# and drop any null/deleted stories the API may have returned.
def reorder-by-ids [ids: list<int>]: list<any> -> list<any> {
    let fetched = ($in | compact)
    $ids | each { |target_id|
        let match = ($fetched | where id == $target_id)
        if ($match | is-empty) { null } else { $match | first }
    } | compact
}

# Helper to fetch URL with retries
def http-get-with-retry [url: string, max_retries: int = 3, timeout: duration = 10sec]: nothing -> any {
    for attempt in 1..$max_retries {
        try {
            let result = (http get --max-time $timeout $url)
            return $result
        } catch {
            if $attempt == $max_retries {
                error make {msg: $"Failed to fetch ($url) after ($max_retries) attempts"}
            }
            sleep 200ms
        }
    }
}

# Fetch stories from HN API and save to cache
def fetch-new-stories [feed: string, limit: int, cache_file: string]: nothing -> list<any> {
    print $"Fetching ($feed)..."

    # Fetch ranked IDs
    let ids = try {
            http-get-with-retry $"https://hacker-news.firebaseio.com/v0/($feed).json"
            | first $limit
    } catch { |err|
        print $"(ansi red)Error fetching IDs: ($err.msg)(ansi reset)"
        []
    }

    if ($ids | is-empty) {
        []
    } else {
        # Fetch details in parallel, then restore HN rank order
        let items = ($ids
            | compact
            | par-each { |id|
                try {
                    http-get-with-retry $"https://hacker-news.firebaseio.com/v0/item/($id).json"
                } catch { null }
            }
            | reorder-by-ids $ids
        )

        $items | save --force $cache_file
        $items
    }
}

# Build the rich table display for stories
def build-stories-display [stories: list<any>, icon_mode: string, visible_cols: list<string>]: nothing -> list<any> {
    let term_width = (term size).columns

    let show_score = ($visible_cols | any { |it| $it == "Score" })
    let show_cmts = ($visible_cols | any { |it| $it == "Cmts" })
    let show_age = ($visible_cols | any { |it| $it == "Age" })
    let show_by = ($visible_cols | any { |it| $it == "By" })
    let show_domain = ($visible_cols | any { |it| $it == "Domain" })
    let show_type = ($visible_cols | any { |it| $it == "Type" })

    # Compute title budget by subtracting estimated widths of other columns
    let used_width = {
        base: $WIDTH_BASE
        score: (if $show_score { $WIDTH_SCORE } else { 0 })
        cmts: (if $show_cmts { $WIDTH_CMTS } else { 0 })
        age: (if $show_age { $WIDTH_AGE } else { 0 })
        by: (if $show_by { $WIDTH_BY } else { 0 })
        domain: (if $show_domain { $WIDTH_DOMAIN } else { 0 })
        type: (if $show_type { $WIDTH_TYPE } else { 0 })
    } | values | math sum
    let title_budget = ([($term_width - $used_width), 20] | math max)

    $stories | enumerate | each { |it|
        let rank = $it.index + 1
        let item = $it.item

        let title_text = ($item.title? | default "(no title)")
        let clean_title = (strip-hn-prefix $title_text)

        let trunc_title = if ($clean_title | str length) > $title_budget {
            ($clean_title | str substring 0..($title_budget - 2)) + "…"
        } else {
            $clean_title
        }

        let url = ($item.url? | default "")
        let title_display = if ($url | is-empty) { $trunc_title } else { $url | ansi link --text $trunc_title }

        let cmts_text = (format-comments ($item.descendants? | default 0))
        let hn_url = $"https://news.ycombinator.com/item?id=($item.id? | default 0)"
        let cmts_display = $hn_url | ansi link --text $cmts_text

        let age_display = (format-age ($item.time? | default 0))

        let domain_info = (lookup-domain-info $url)
        let post_type = (detect-post-type $title_text $url)
        let type_display = (format-type-icon $post_type $domain_info $icon_mode)

        {
            "#": $rank
            "Score": (format-score ($item.score? | default 0))
            "Cmts": $cmts_display
            "Age": $age_display
            "Domain": (format-domain $url $icon_mode)
            "Type": $type_display
            "Title": $title_display
            "By": ($item.by? | default "?" | fill -a l -w 15)
        }
    }
    | select ...$visible_cols
}

# Build a compact one-line display for narrow terminals
def build-oneline-display [stories: list<any>, icon_mode: string]: nothing -> string {
    $stories | enumerate | each { |it|
        let rank = $it.index + 1
        let item = $it.item
        let title = ($item.title? | default "(no title)")
        let url = ($item.url? | default "")
        let title_display = if ($url | is-empty) { $title } else { $url | ansi link --text $title }
        $"($rank). ($title_display)"
    } | str join "\n"
}

# Generate hardcoded test data for offline testing
def test-data [count: int]: nothing -> list<any> {
    let now = (date now | format date '%s' | into int)
    [
        {
            id: 1001
            title: "Nushell: A new type of shell"
            score: 542
            descendants: 120
            by: "jntrnr"
            time: ($now - 7200)
            url: "https://www.nushell.sh"
            type: "story"
            kids: [10011 10012]
        }
        {
            id: 1002
            title: "Ask HN: What is your favorite shell?"
            score: 256
            descendants: 85
            by: "user1"
            time: ($now - 1800)
            url: ""
            type: "story"
            kids: []
        }
        {
            id: 1003
            title: "Show HN: A Hacker News reader in Nushell"
            score: 89
            descendants: 12
            by: "suave"
            time: ($now - 86400)
            url: "https://github.com/nushell/nushell"
            type: "story"
            kids: [10031]
        }
        {
            id: 1004
            title: "Rust 1.80.0 released"
            score: 1024
            descendants: 340
            by: "rust-lang"
            time: ($now - 300)
            url: "https://blog.rust-lang.org/"
            type: "story"
            kids: [10041 10042 10043]
        }
    ] | first $count
}

# Fetch and display top Hacker News stories
export def hn [
    limit: int = 15             # Number of stories to fetch (default: 15)
    --force (-f)                # Bypass cache and force refresh
    --json (-j)                 # Return raw JSON data
    --raw (-r)                  # Return raw record data (no formatting)
    --emoji (-e)                # Use emoji for icons (overrides $env.NERD_FONTS)
    --nerd (-n)                 # Use Nerd Font glyphs for icons if available
    --text (-t)                 # Plain text mode — no icons or color
    --debug (-d)                # Print debug info
    --new (-N)                  # Fetch new stories
    --best (-b)                 # Fetch best stories
    --ask (-a)                  # Fetch Ask HN stories
    --show (-s)                 # Fetch Show HN stories
    --test                      # Use hardcoded test data (offline mode)
]: nothing -> any {
    let start_fetch = (date now)

    # Resolve icon mode once: explicit flag > $env.NERD_FONTS > plain text
    let icon_mode = if $emoji {
        "emoji"
    } else if $text {
        "text"
    } else if $nerd or ($env.NERD_FONTS? == "1") {
        "nerd"
    } else {
        "text"
    }

    let feed = if $new {
        "newstories"
    } else if $best {
        "beststories"
    } else if $ask {
        "askstories"
    } else if $show {
        "showstories"
    } else {
        "topstories"
    }

    let cache_dir = ($nu.cache-dir | path join "nu_hn_cache")
    if not ($cache_dir | path exists) { mkdir $cache_dir }
    let cache_file = ($cache_dir | path join $"($feed).json")

    # Check cache validity (15 minutes)
    let is_cache_valid = if $force or $test {
        false
    } else if ($cache_file | path exists) {
        let modified = (ls $cache_file | get modified | first)
        (date now) - $modified < 15min
    } else {
        false
    }

    if $debug {
        print $"(ansi cyan)DEBUG: Icon mode:   ($icon_mode)(ansi reset)"
        print $"(ansi cyan)DEBUG: Feed:        ($feed)(ansi reset)"
        print $"(ansi cyan)DEBUG: Cache file:  ($cache_file)(ansi reset)"
        print $"(ansi cyan)DEBUG: Cache valid: ($is_cache_valid)(ansi reset)"
    }

    let stories = if $test {
        if $debug { print "Loading test data..." }
        test-data $limit
    } else if $is_cache_valid {
        if $debug { print "Loading from cache..." }
        open $cache_file
    } else {
        fetch-new-stories $feed $limit $cache_file
    }

    if $json { return $stories }

    let term_width = (term size).columns
    let show_score = $term_width > $COL_SCORE_MIN_WIDTH
    let show_cmts = $term_width > $COL_CMTS_MIN_WIDTH
    let show_age = $term_width > $COL_AGE_MIN_WIDTH
    let show_by = $term_width > $COL_BY_MIN_WIDTH
    let show_domain = $term_width > $COL_DOMAIN_MIN_WIDTH
    let show_type = $term_width > $COL_TYPE_MIN_WIDTH

    let visible_columns = [
        "#"
        (if $show_score { "Score" })
        (if $show_cmts { "Cmts" })
        (if $show_age { "Age" })
        (if $show_domain { "Domain" })
        (if $show_type { "Type" })
        "Title"
        (if $show_by { "By" })
    ] | compact

    let result = if ($term_width < $COL_SCORE_MIN_WIDTH) and (not $raw) {
        build-oneline-display $stories $icon_mode
    } else {
        build-stories-display $stories $icon_mode $visible_columns
    }

    if $raw { return $result }

    let duration = (date now) - $start_fetch
    if $test {
        print $"(ansi light_gray)Loaded test data(ansi reset)"
    } else if not $is_cache_valid {
        print $"(ansi light_gray)Loaded ($limit) stories in ($duration)(ansi reset)"
    } else {
        print $"(ansi light_gray)Loaded from cache(ansi reset)"
    }

    $result
}
