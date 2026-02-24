# nu_script_hnews — Hacker News in your terminal

Read Hacker News from Nushell. Fetches stories, caches them for 15 minutes, and prints a table you can actually read.

<img width="1222" height="217" alt="image" src="https://github.com/user-attachments/assets/cd3213ab-4fe5-49a3-b334-2a43fb4909b6" />
<img width="909" height="212" alt="image" src="https://github.com/user-attachments/assets/45dd61b6-b9f0-4488-a46f-12e8e835e6f7" />
<img width="623" height="212" alt="image" src="https://github.com/user-attachments/assets/fdb61c6b-c08b-4556-9b2a-31f133020cca" />
<img width="486" height="126" alt="image" src="https://github.com/user-attachments/assets/e51bf22f-ad3a-487e-9ae9-023444ce2e2a" />


> Title and Cmts are clickable links in terminals that support OSC-8 (iTerm2, kitty, WezTerm, etc.).

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

---

## Usage

```nushell
hn              # Top 15 stories
hn 30           # Top 30 stories
hn -f           # Force refresh, ignore cache
hn --new        # New stories
hn --best       # Best stories
hn --ask        # Ask HN
hn --show       # Show HN
hn -j           # Raw JSON output
hn -r           # Raw records (no ANSI formatting)
```

---

## Columns

Columns appear and disappear based on terminal width, so narrow windows don't wrap:

| Column | Min width | Notes |
| -------- | ----------- | ------- |
| `#` | always | 1-based rank |
| `Score` | 50 | Color-coded: green / yellow / red bold |
| `Cmts` | 60 | Clickable link to HN discussion |
| `Age` | 60 | Time since posted: `Xs` `Xm` `Xh` `Xd` `Xw` |
| `Domain` | 80 | Source domain |
| `Type` | 90 | Site or post-type icon (Ask, Show, Launch) |
| `Title` | always | Clickable link to article. Truncated to fit remaining width |
| `By` | 70 | Username |

---

## Icon modes

| Flag | Result |
| ------ | -------- |
| `--emoji` / `-E` | Emoji icons |
| `--nerd` / `-N` | Nerd Font glyphs |
| `--text` / `-T` | Plain text (default) |

You can also set `$env.NERD_FONTS = "1"` in your `env.nu` to default to Nerd Font glyphs without passing a flag every time.

---

## Feeds

Each feed is cached separately, so switching between them doesn't blow away your top stories cache.

| Flag | Feed |
| ------ | ------ |
| *(default)* | Top stories |
| `--new` / `-n` | New |
| `--best` / `-b` | Best |
| `--ask` / `-a` | Ask HN |
| `--show` / `-s` | Show HN |

---

## Caching

Stories are cached for 15 minutes under `$nu.cache-dir/nu_hn_cache/`. Run `hn -f` to skip the cache and fetch fresh results.

---

## All flags

| Flag | Short | Description |
| ------ | ------- | ------------- |
| `--force` | `-f` | Bypass cache |
| `--new` | `-n` | New stories feed |
| `--best` | `-b` | Best stories feed |
| `--ask` | `-a` | Ask HN feed |
| `--show` | `-s` | Show HN feed |
| `--json` | `-j` | Raw JSON output |
| `--raw` | `-r` | Raw records, no ANSI color |
| `--emoji` | `-E` | Emoji icons |
| `--nerd` | `-N` | Nerd Font glyphs |
| `--text` | `-T` | Plain text, no color |
| `--full` | `-F` | Force full width display |
| `--compact` | `-C` | Force compact display |
| `--minimal` | `-M` | Force minimal display |
| `--oneline` | `-1` | Force one-line display |
| `--demo` | | Display all layouts |
| `--test` | | Use hardcoded test data |
| `--debug` | | Print cache and icon mode info |

---

## Pipeline use

`--raw` and `--json` are there for when you want to pipe results into something else:

```nushell
# Stories with 500+ points
hn 50 --raw | where { |it| $it.Score > 500 }

# Titles only, from the ask feed
hn --ask --json | select title score by
```

---

## Customisation

Column breakpoints and width estimates are named constants at the top of `hnews.nu`:

```nushell
const COL_SCORE_MIN_WIDTH  = 50
const COL_CMTS_MIN_WIDTH   = 60
const COL_BY_MIN_WIDTH     = 70
const COL_DOMAIN_MIN_WIDTH = 80
const COL_TYPE_MIN_WIDTH   = 90
```

Adjust them if your font or table renderer makes columns wider or narrower than expected.
