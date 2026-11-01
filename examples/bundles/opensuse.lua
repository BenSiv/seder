-- Package names are the distribution's own, so each one gets a bundle.
return {
    zypper = {
        present = {"git", "jq", "python3-pipx"},
        absent = {"MozillaThunderbird"},
    },
}
