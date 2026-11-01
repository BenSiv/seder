-- openSUSE. rpm lists what is installed; zypper changes it.
return {
    list = "rpm -qa --qf '%{NAME}\\n'",
    install = "zypper --non-interactive install",
    remove = "zypper --non-interactive remove",
}
