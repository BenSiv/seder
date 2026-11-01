-- An openSUSE machine. zypper has no built-in provider; managers/zypper.lua
-- describes it.
return {
    requires_seder = "0.5.0",
    vars = {dotfiles = "~/dotfiles"},
    bundles = {"base", "opensuse", "python-tools"},
}
