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
#   > hn -f                     # Force refresh (bypass cache)
#   > hn -j                     # Output raw JSON
#   > hn -e                     # Use emoji for link column
#   > hn -t                     # Plain text mode, no icons or color
#   > hno 1                     # Open story #1 in browser (1-based)
#   > hno 1 -c                  # Open HN discussion for story #1
#
# Requires Nushell 0.97+ for $nu.cache-dir support.

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

# Format the domain from a URL
def format-domain [url: string, mode: string]: nothing -> string {
    if ($url | is-empty) {
        if $mode == "text" {
            "self"
        } else {
            $"(ansi light_gray)hn(ansi reset)"
        }
    } else {
        let domain = ($url | split row "/" | get 2)
        let bare_domain = if ($domain | str starts-with "www.") {
            $domain | str substring 4..
        } else {
            $domain
        }

        $bare_domain
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
            let domain = ($url | split row "/" | get 2)
            let bare_domain = if ($domain | str starts-with "www.") {
                $domain | str substring 4..
            } else {
                $domain
            }
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
    let lower = ($title | str downcase)
    if ($lower | str starts-with "ask hn: ") {
        $title | str substring 8..
    } else if ($lower | str starts-with "show hn: ") {
        $title | str substring 9..
    } else if ($lower | str starts-with "launch hn: ") {
        $title | str substring 11..
    } else {
        $title
    }
}

# Re-order par-each results to match the original ID ordering,
# and drop any null/deleted stories the API may have returned.
def reorder-by-ids [ids: list<int>]: list<any> -> list<any> {
    let fetched = ($in | compact)
    $ids | each {|id|
        $fetched | where {|story| $story.id? == $id} | first
    } | compact
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

    let cache_dir = ($nu.cache-dir | path join "nu_hn_cache")
    if not ($cache_dir | path exists) { mkdir $cache_dir }
    let cache_file = ($cache_dir | path join "topstories.json")

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
        print $"(ansi cyan)DEBUG: Cache file:  ($cache_file)(ansi reset)"
        print $"(ansi cyan)DEBUG: Cache valid: ($is_cache_valid)(ansi reset)"
    }

    let stories = if $is_cache_valid {
        if $debug { print "Loading from cache..." }
        open $cache_file
    } else {
        print "Fetching top stories..."
        try {
            # Fetch ranked IDs
            let ids = (
                http get "https://hacker-news.firebaseio.com/v0/topstories.json"
                | first $limit
            )

            # Fetch details in parallel, then restore HN rank order
            let items = (
                $ids
                | par-each {|id|
                    http get $"https://hacker-news.firebaseio.com/v0/item/($id).json"
                }
                | reorder-by-ids $ids
            )

            $items | save --force $cache_file
            $items
        } catch {|err|
            print $"(ansi red)Error fetching stories: ($err.msg)(ansi reset)"
            return []
        }
    }

    if $json { return $stories }

    let term_width = (term size).columns
    let show_score = $term_width > 50
    let show_cmts = $term_width > 60
    let show_by = $term_width > 70
    let show_domain = $term_width > 80
    let show_type = $term_width > 90

    # Compute title budget by subtracting estimated widths of other columns
    # Estimates: Border(1) + Rank(5) + TitlePad/Border(3) = 9 base
    let used_width = (9
        + (if $show_score { 8 } else { 0 })   # Score: 5+2+1
        + (if $show_cmts { 7 } else { 0 })    # Cmts: 4+2+1
        + (if $show_by { 18 } else { 0 })     # By: 15+2+1
        + (if $show_domain { 23 } else { 0 }) # Domain: ~20+2+1
        + (if $show_type { 7 } else { 0 }))   # Type: 4+2+1
    let title_budget = ([($term_width - $used_width), 20] | math max)

    # Build display table (1-based rank for human-friendly indexing)
    let display_table = (
        $stories | enumerate | each {|it|
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

            let rec = { "#": $rank }
            let rec = if $show_score { $rec | insert "Score" (format-score ($item.score? | default 0)) } else { $rec }
            let rec = if $show_cmts { $rec | insert "Cmts" $cmts_display } else { $rec }
            let rec = if $show_domain { $rec | insert "Domain" (format-domain $url $icon_mode) } else { $rec }
            let rec = if $show_type { $rec | insert "Type" (format-type $title_text $url $icon_mode) } else { $rec }
            let rec = $rec | insert "Title" $title_display
            let rec = if $show_by { $rec | insert "By" ($item.by? | default "?" | fill -a l -w 15) } else { $rec }
            $rec
        }
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

# Open a cached Hacker News story in the browser (1-based index)
export def hno [
    index: int = 1              # Rank of the story to open, 1-based (default: 1)
    --comments (-c)             # Open HN discussion page instead of the article URL
]: nothing -> nothing {
    let cache_dir = ($nu.cache-dir | path join "nu_hn_cache")
    let cache_file = ($cache_dir | path join "topstories.json")

    if not ($cache_file | path exists) {
        print $"(ansi red)Cache empty. Run 'hn' first.(ansi reset)"
        return
    }

    let stories = open $cache_file
    let real_index = $index - 1

    if ($stories | length) <= $real_index or $real_index < 0 {
        print $"(ansi red)Index ($index) out of range. Valid range: 1–($stories | length)(ansi reset)"
        return
    }

    let story = ($stories | get $real_index)
    let hn_url = $"https://news.ycombinator.com/item?id=($story.id? | default 0)"

    if $comments {
        print $"(ansi light_gray)Opening HN discussion for: ($story.title? | default '?')(ansi reset)"
        start $hn_url
    } else if ($story.url? | is-empty) {
        print $"(ansi yellow)No external URL — opening HN discussion instead.(ansi reset)"
        start $hn_url
    } else {
        print $"(ansi light_gray)Opening: ($story.url)(ansi reset)"
        start $story.url
    }
}
