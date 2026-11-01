-- Shared by every machine: nothing here depends on the distribution.
return {
    path = {present = {"~/.local/bin"}},
    link = {present = {{path = "~/.bashrc", target = "${dotfiles}/bashrc"}}},
}
