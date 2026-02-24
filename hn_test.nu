# Test suite for hnews.nu
#
# Usage:
#   > nu hn_test.nu
#
# Tests cover:
# - Output structure (Table vs JSON vs String)
# - Post type detection logic (Ask/Show/Launch/Domain tags)
# - Display tier flags (--full, --compact, --minimal, --oneline)
# - Demo mode execution

use ./hnews.nu [hn, detect-post-type]
use std assert

export def main [] {
    print "Running tests..."

    # Test 1: Verify --test --raw returns a table with expected columns
    print "Test 1: Structure of --raw output"
    let result = (hn --test --raw 1)
    print $"DEBUG: Result table:"
    print ($result | table)
    assert equal ($result | length) 1
    let columns = ($result | columns)
    assert ($"#" in $columns)
    assert ("Title" in $columns)

    # Test 2: Verify --test --json returns the raw data structure
    print "Test 2: Structure of --json output"
    let json_result = (hn --test --json 1)
    print $"DEBUG: JSON result length: ($json_result | length)"
    assert equal ($json_result | length) 1
    let item = ($json_result | first)
    print $"DEBUG: Item ID: ($item.id), Kids: ($item.kids)"
    assert ($item.id == 1001)
    assert ($item.kids | is-not-empty)

    # Test 3: Verify detect-post-type logic
    print "Test 3: detect-post-type logic"
    print $"DEBUG: Ask HN -> (detect-post-type 'Ask HN: Who is hiring?' '')"
    assert equal (detect-post-type "Ask HN: Who is hiring?" "") "ask"
    assert equal (detect-post-type "Show HN: My Project" "") "show"
    assert equal (detect-post-type "Launch HN: New Thing" "") "launch"
    print $"DEBUG: github.com -> (detect-post-type 'Regular Story' 'github.com')"
    assert equal (detect-post-type "Regular Story" "github.com") "git"
    assert equal (detect-post-type "Random Site" "example.com") ""

    # Test 4: Verify display tiers
    print "Test 4: Display tiers"

    print "DEBUG: Testing --full"
    let full = (hn --test --full 1)
    let full_cols = ($full | columns)
    assert ("Domain" in $full_cols)
    assert ("Type" in $full_cols)
    assert ("Score" in $full_cols)

    print "DEBUG: Testing --compact"
    let compact = (hn --test --compact 1)
    let compact_cols = ($compact | columns)
    assert ("Domain" not-in $compact_cols)
    assert ("Type" not-in $compact_cols)
    assert ("Score" in $compact_cols)

    print "DEBUG: Testing --minimal"
    let minimal = (hn --test --minimal 1)
    let minimal_cols = ($minimal | columns)
    assert ("Score" not-in $minimal_cols)
    assert ("By" not-in $minimal_cols)
    assert ("Title" in $minimal_cols)

    print "DEBUG: Testing --oneline"
    let oneline = (hn --test --oneline 1)
    assert equal ($oneline | describe) "string"
    assert ($oneline | str contains "Nushell")

    # Test 5: Verify --demo runs
    print "Test 5: Demo mode"
    hn --test --demo 1

    print "All tests passed!"
}
