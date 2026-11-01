-- Python applications for the current user: no sudo, and after npm, so
-- every package manager that might install pipx itself runs first.
-- `pipx list --short` prints "name version"; only the name counts.
-- `pipx uninstall` takes one package at a time.
return {
    list = "pipx list --short",
    install = "pipx install",
    remove = "pipx uninstall",
    sudo = false,
    one_at_a_time = true,
    after = "npm",
}
