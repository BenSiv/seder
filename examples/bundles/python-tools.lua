-- pipx is described in managers/pipx.lua; it runs after the system
-- packages, so the pipx those install is there first.
return {
    pipx = {present = {"black", "httpie"}},
}
