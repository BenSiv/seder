-- tst/unit/shell.lua
-- Unit tests for src/shell.lua's pure helpers: quoting, parent paths and
-- the home-directory check that decides between sudo and plain commands.
-- Same style as daat's tst/unit/ (require the module, check(), run
-- inline, exit 1 on failure).

shell = require("shell")

FAILURES = 0

function check(condition, message)
    if condition != true then
        FAILURES = FAILURES + 1
        print("FAIL: " .. message)
    end
end

function test_quote()
    print("Testing shell.quote survives single quotes")
    check(shell.quote("a b") == "'a b'", "plain string")
    check(shell.quote("it's") == "'it'\\''s'", "embedded quote, got " .. shell.quote("it's"))
    out, ok = shell.capture("printf %s " .. shell.quote("it's $HOME"))
    check(ok == true and out == "it's $HOME", "round trip through sh, got " .. out)
end

function test_capture_status()
    print("Testing shell.capture reports exit status")
    out, ok = shell.capture("echo hi")
    check(ok == true and out == "hi\n", "success, got " .. out)
    _, ok = shell.capture("exit 3")
    check(ok == false, "failure")
end

function test_parent()
    print("Testing shell.parent")
    check(shell.parent("/a/b/c") == "/a/b", "nested")
    check(shell.parent("/a") == "/", "top level")
    check(shell.parent("machines/laptop.lua") == "machines", "relative")
    check(shell.parent("laptop.lua") == ".", "bare name")
end

function test_in_home()
    print("Testing shell.in_home")
    home = shell.home()
    check(shell.in_home(home .. "/.bashrc") == true, "file in home")
    check(shell.in_home(home .. "x/.bashrc") == false, "sibling sharing the prefix")
    check(shell.in_home("/usr/local/bin/luam") == false, "system path")
end

-- Run them
test_quote()
test_capture_status()
test_parent()
test_in_home()

if FAILURES > 0 then
    print(FAILURES .. " test(s) failed")
    os.exit(1)
end
print("All shell.lua tests passed")
