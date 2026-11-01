-- An Alpine machine, with apk described in managers/apk.lua.
return {
    requires_seder = "0.5.0",
    vars = {dotfiles = "~/dotfiles"},
    bundles = {"base", "alpine", "python-tools"},
}
