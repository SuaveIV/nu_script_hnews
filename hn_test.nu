use hnews.nu [hn, detect-post-type]
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
    assert equal (detect-post-type "Ask HN: Who is hiring?" "") "ask"
    assert equal (detect-post-type "Show HN: My Project" "") "show"
    assert equal (detect-post-type "Launch HN: New Thing" "") "launch"
    assert equal (detect-post-type "Regular Story" "https://github.com/nushell/nushell") "git"
    assert equal (detect-post-type "Random Site" "https://example.com") ""

    print "All tests passed!"
}
