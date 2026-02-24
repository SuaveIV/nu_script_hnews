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

# Format the post type (Ask, Show, Launch)
def format-type [title: string, url: string, mode: string]: nothing -> string {
    let lower = ($title | str downcase)
    if ($lower | str starts-with "ask hn:") {
        let icon = if $mode == "text" { "ask" } else if $mode == "emoji" { $TYPE_ICONS.ask.emoji } else { $TYPE_ICONS.ask.nerd }
        $"(ansi yellow)($icon)(ansi reset)"
    } else if ($lower | str starts-with "show hn:") {
        let icon = if $mode == "text" { "show" } else if $mode == "emoji" { $TYPE_ICONS.show.emoji } else { $TYPE_ICONS.show.nerd }
        $"(ansi green)($icon)(ansi reset)"
    } else if ($lower | str starts-with "launch hn:") {
        let icon = if $mode == "text" { "launch" } else if $mode == "emoji" { $TYPE_ICONS.launch.emoji } else { $TYPE_ICONS.launch.nerd }
        $"(ansi red)($icon)(ansi reset)"
    } else {
        let domain_info = if ($url | is-empty) {
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

        if $mode == "text" {
            if ($domain_info | is-not-empty) and ($domain_info.tag? | is-not-empty) {
                $domain_info.tag
            } else {
                ""
            }
        } else {
            let domain_icon = if ($domain_info | is-not-empty) {
                let icon = if $mode == "emoji" { $domain_info.emoji } else { $domain_info.nerd }
                if $mode == "nerd" and ($domain_info.color? | is-not-empty) {
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
                let icon = if $mode == "emoji" { $TYPE_ICONS.default.emoji } else { $TYPE_ICONS.default.nerd }
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
    let now_sec = ((date now) | into int) / 1_000_000_000
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
    let lookup = ($fetched | each { |it| { key: ($it.id | into string), value: $it } } | into record)
    $ids | each { |id| $lookup | get --ignore-errors ($id | into string) } | compact
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
    let is_cache_valid = if $force {
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

    let stories = if $is_cache_valid {
        if $debug { print "Loading from cache..." }
        open $cache_file
    } else {
        print $"Fetching ($feed)..."

        # Fetch ranked IDs
        let ids = try {
                http get $"https://hacker-news.firebaseio.com/v0/($feed).json"
                | first $limit
        } catch { |err|
            print $"(ansi red)Error fetching IDs: ($err.msg)(ansi reset)"
            []
        }

        if ($ids | is-empty) {
            []
        } else {
            # Fetch details in parallel, then restore HN rank order
            let items = (
                $ids
                | compact
                | par-each { |id|
                    try {
                        http get $"https://hacker-news.firebaseio.com/v0/item/($id).json"
                    } catch { null }
                }
                | reorder-by-ids $ids
            )

            $items | save --force $cache_file
            $items
        }
    }

    if $json { return $stories }

    let term_width = (term size).columns
    let show_score = $term_width > $COL_SCORE_MIN_WIDTH
    let show_cmts = $term_width > $COL_CMTS_MIN_WIDTH
    let show_age = $term_width > $COL_AGE_MIN_WIDTH
    let show_by = $term_width > $COL_BY_MIN_WIDTH
    let show_domain = $term_width > $COL_DOMAIN_MIN_WIDTH
    let show_type = $term_width > $COL_TYPE_MIN_WIDTH

    # Compute title budget by subtracting estimated widths of other columns
    # Estimates: Border(1) + Rank(5) + TitlePad/Border(3) = 9 base
    let used_width = ($WIDTH_BASE
        + (if $show_score { $WIDTH_SCORE } else { 0 })
        + (if $show_cmts { $WIDTH_CMTS } else { 0 })
        + (if $show_age { $WIDTH_AGE } else { 0 })
        + (if $show_by { $WIDTH_BY } else { 0 })
        + (if $show_domain { $WIDTH_DOMAIN } else { 0 })
        + (if $show_type { $WIDTH_TYPE } else { 0 }))
    let title_budget = ([($term_width - $used_width), 20] | math max)

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

    # Build display table (1-based rank for human-friendly indexing)
    let display_table = (
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

            {
                "#": $rank
                "Score": (format-score ($item.score? | default 0))
                "Cmts": $cmts_display
                "Age": $age_display
                "Domain": (format-domain $url $icon_mode)
                "Type": (format-type $title_text $url $icon_mode)
                "Title": $title_display
                "By": ($item.by? | default "?" | fill -a l -w 15)
            }
        }
        | select ...$visible_columns
    )

    if $raw { return $display_table }

    let duration = (date now) - $start_fetch
    if not $is_cache_valid {
        print $"(ansi light_gray)Loaded ($limit) stories in ($duration)(ansi reset)"
    } else {
        print $"(ansi light_gray)Loaded from cache(ansi reset)"
    }

    $display_table
}
