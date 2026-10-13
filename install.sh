#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

destination="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/cz.saruman.strava"
if [[ $# -eq 2 && $1 == --destination && -n $2 ]]; then
    destination=$2
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--destination DIRECTORY]" >&2
    exit 2
fi

if ! command -v plasmashell >/dev/null; then
    echo "KDE Plasma 6.3 or newer is required (Debian 13 KDE or equivalent)." >&2
    exit 1
fi
if ! plasma_version=$(plasmashell --version); then
    echo "Could not start plasmashell to check its version. Run this installer from your KDE desktop session." >&2
    exit 1
fi
if [[ ! $plasma_version =~ plasmashell[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
    echo "Could not determine the installed Plasma version." >&2
    exit 1
fi
if (( BASH_REMATCH[1] < 6 || (BASH_REMATCH[1] == 6 && BASH_REMATCH[2] < 3) )); then
    echo "The no-compile backend requires Plasma 6.3 or newer." >&2
    exit 1
fi

# Debian ships qtpaths6 with development tools: it must remain optional.
# Multiarch globs cover Debian amd64, arm64 and other architectures.
qml_roots=()
if command -v qtpaths6 >/dev/null; then
    if qml_root=$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null); then
        qml_roots+=("$qml_root")
    fi
fi
IFS=: read -r -a extra_qml_roots <<< "${QML_IMPORT_PATH:-}"
qml_roots+=("${extra_qml_roots[@]}" /usr/lib/*/qt6/qml /usr/lib/qt6/qml /usr/lib64/qt6/qml)
module_found=false
for qml_root in "${qml_roots[@]}"; do
    if [[ -n $qml_root && -f "$qml_root/org/kde/plasma/workspace/dbus/qmldir" ]]; then
        module_found=true
        break
    fi
done
if [[ $module_found == false ]]; then
    echo "The installed Plasma runtime lacks org.kde.plasma.workspace.dbus." >&2
    echo "On Debian 13, install the plasma-workspace runtime package." >&2
    exit 1
fi

# Merge package code/configuration without touching account settings or wallet data.
# Exclude generated/private data and compiled artifacts from the source checkout.
mkdir -p "$destination"
tar -C package --exclude='*.so' --exclude='*.so.*' --exclude='__pycache__' \
    -cf - metadata.json contents/ui contents/code contents/config \
    | tar -C "$destination" -xf -

echo "Installed without compilation: $destination"
echo "Add Strava Meals from Plasma's Add Widgets menu."
echo "If updating an existing instance, log out and back in to reload it."
