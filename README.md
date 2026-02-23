# nu_script_hnews — Hacker News in your terminal

Read Hacker News from Nushell. Fetches the top stories, caches them for 15 minutes, and prints a table you can actually read.

```nushell
> hn
Fetching top stories...
Loaded 15 stories in 1sec 203ms
╭────┬───────┬──────┬────────────────────────────────────────────────┬─────────────────┬─────╮
│  # │ Score │ Cmts │ Title                                          │ By              │ Lnk │
├────┼───────┼──────┼────────────────────────────────────────────────┼─────────────────┼─────┤
│  1 │   847 │  312 │ Ask HN: What's your morning routine?           │ throwaway9182   │ [x] │
│  2 │   432 │   88 │ I rewrote my blog in C                         │ pjmlp           │ [x] │
│ .. │   ... │  ... │ ...                                            │ ...             │ ... │
╰────┴───────┴──────┴────────────────────────────────────────────────┴─────────────────┴─────╯
```

---

## Requirements

- **Nushell 0.97+** (needs `$nu.cache-dir`)
- Internet access to hit the [HN Firebase API](https://hacker-news.firebaseio.com/)

---

## Install

Copy `hnews.nu` somewhere on your system, then add it to your `config.nu`:

```nushell
use /path/to/hnews.nu *
```

Or drop it into a folder you already `use` as a module.

---

## Usage

```nushell
hn              # Top 15 stories
hn 30           # Top 30 stories
hn -f           # Force refresh, ignore cache
hn -j           # Raw JSON output
hn -r           # Raw records (no ANSI formatting)

hno 3           # Open story #3's URL in your browser
hno 3 -c        # Open the HN comments page instead
```

### Icon modes

The link column (`Lnk`) can show different indicators depending on your setup:

| Flag / env var | What you get |
| --- | --- |
| `--emoji` / `-e` | 🔗 |
| `--nerd` / `-n` or `$env.NERD_FONTS = "1"` |  |
| `--text` / `-t` (default) | `[x]` or `-` |

Stories without an external URL (self-posts, Ask HN, etc.) show a dim dash instead.

---

## Caching

Stories are cached for **15 minutes** in `$nu.cache-dir/nu_hn_cache/topstories.json`. Run `hn -f` to bypass the cache. `hno` reads from that same cache, so run `hn` at least once before trying to open stories.

---

## Options

### `hn`

| Flag | Short | Description |
| --- | --- | --- |
| `--force` | `-f` | Bypass cache |
| `--json` | `-j` | Return raw JSON |
| `--raw` | `-r` | Return records without ANSI color |
| `--emoji` | `-e` | Use 🔗 for link column |
| `--nerd` | `-n` | Use Nerd Font glyph |
| `--text` | `-t` | Plain text, no color |
| `--debug` | `-d` | Print cache/config debug info |

### `hno`

| Flag | Short | Description |
| --- | --- | --- |
| `--comments` | `-c` | Open HN discussion instead of article |

---

## Score colors

| Score | Color |
| --- | --- |
| 300+ | Red bold |
| 100–299 | Yellow |
| < 100 | Green |

Comment counts follow the same idea: cyan bold for 200+, plain cyan for 50+, plain text below that.
