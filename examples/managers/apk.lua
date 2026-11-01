-- Alpine. `apk info` prints one installed package name per line.
return {
    list = "apk info",
    install = "apk add",
    remove = "apk del",
    refresh = "apk update",
}
