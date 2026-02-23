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

# Format a link indicator for the story URL column.
# mode: "nerd" = Nerd Font glyph, "emoji" = 🔗, "text" = plain x / dash.
# Shows a dim dash (or plain dash in text mode) for stories with no external URL.
def format-link [
    url: string
    mode: string
]: nothing -> string {
    if ($url | is-empty) {
        if $mode == "text" { "-" } else { $"(ansi grey)-(ansi reset)" }
    } else {
        let label = match $mode {
            "nerd"  => $"(ansi blue)[](ansi reset)"
            "emoji" => $"(ansi blue)[🔗](ansi reset)"
            _       => "[x]"
        }
        $url | ansi link --text $label
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

    # Build display table (1-based rank for human-friendly indexing)
    let display_table = (
        $stories | enumerate | each {|it|
            let rank = $it.index + 1
            let item = $it.item
            {
                "#": $rank
                "Score": (format-score ($item.score? | default 0))
                "Cmts": (format-comments ($item.descendants? | default 0))
                "Title": ($item.title? | default "(no title)")
                "By": ($item.by? | default "?" | fill -a l -w 15)
                "Lnk": (format-link ($item.url? | default "") $icon_mode)
            }
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
