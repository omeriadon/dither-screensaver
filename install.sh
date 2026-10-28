#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
SOURCE_APP="${DITHER_SOURCE_APP:-$ROOT/experimental/appex/build/DitherHost.app}"
DESTINATION="${DITHER_INSTALL_DESTINATION:-$HOME/Applications/Dither Screen Saver.app}"
DESTINATION_PARENT="${DESTINATION:h}"
BACKUP_ROOT="${DITHER_INSTALL_BACKUP_ROOT:-$HOME/Library/Application Support/Dither/Backups}"
LSREGISTER="${DITHER_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
CODESIGN="${DITHER_CODESIGN:-codesign}"
PLUGINKIT="${DITHER_PLUGINKIT:-pluginkit}"

fail() {
    print -u2 "install.sh: $*"
    exit 1
}

[[ -d "$SOURCE_APP" ]] || fail "built app not found: $SOURCE_APP"
[[ -d "$SOURCE_APP/Contents/PlugIns/DitherExtension.appex" ]] || fail "built extension not found in $SOURCE_APP"
[[ -x "$LSREGISTER" ]] || fail "Launch Services registrar not found: $LSREGISTER"
command -v "$CODESIGN" >/dev/null || fail "codesign is required"
command -v "$PLUGINKIT" >/dev/null || fail "pluginkit is required"

"$CODESIGN" --verify --deep --strict "$SOURCE_APP" || fail "built app signature verification failed"

mkdir -p "$DESTINATION_PARENT" "$BACKUP_ROOT"
[[ ! -L "$DESTINATION" ]] || fail "refusing to replace symlink destination: $DESTINATION"

STAGE_ROOT="$(mktemp -d "$DESTINATION_PARENT/.dither-install.XXXXXX")"
STAGED_APP="$STAGE_ROOT/Dither Screen Saver.app"
BACKUP_APP=""
cleanup() {
    rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

ditto --noqtn "$SOURCE_APP" "$STAGED_APP"
"$CODESIGN" --verify --deep --strict "$STAGED_APP" || fail "staged app signature verification failed"

if [[ -e "$DESTINATION" ]]; then
    BACKUP_APP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).app"
    [[ ! -e "$BACKUP_APP" ]] || fail "backup path already exists: $BACKUP_APP"
    mv "$DESTINATION" "$BACKUP_APP"
fi

mv "$STAGED_APP" "$DESTINATION"
"$CODESIGN" --verify --deep --strict "$DESTINATION" || fail "installed app signature verification failed"

"$LSREGISTER" -f "$DESTINATION"
APPEX="$DESTINATION/Contents/PlugIns/DitherExtension.appex"
"$PLUGINKIT" -a "$APPEX"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Contents/Info.plist")"
REGISTRATION="$("$PLUGINKIT" -m -v -A -D -i "$IDENTIFIER")"
[[ "$REGISTRATION" == *"$APPEX"* ]] || fail "extension registration path was not verified"

if pgrep -f '/ScreenSaverEngine.app/Contents/MacOS/' >/dev/null; then
    print "Screen saver is active; leaving WallpaperAgent running."
elif pgrep -x WallpaperAgent >/dev/null; then
    pkill -x WallpaperAgent || fail "could not restart WallpaperAgent"
fi

print "Installed and registered $DESTINATION"
if [[ -n "$BACKUP_APP" ]]; then
    print "Previous app backed up at $BACKUP_APP"
fi
