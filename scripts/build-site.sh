#!/usr/bin/env bash
# Prepares the GitHub Pages site in docs/ before Jekyll builds it.
# METHODOLOGY.md stays the single source: it is copied into docs/methodology.md
# with front matter, and its links to files of the repository are rewritten to
# point to GitHub, since those files are not part of the site. resources/config.json
# is copied for the simulator.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
docs="$root/docs"
repo="https://github.com/DigitalPebble/aspen"
raw="https://raw.githubusercontent.com/DigitalPebble/aspen/main"

mkdir -p "$docs/assets"
cp "$root/resources/brand/seasons/aspen-icon-autumn.svg" "$docs/assets/aspen-icon.svg"
# the simulator reads the model values from the same file as the estimator
cp "$root/resources/config.json" "$docs/assets/config.json"

{
  printf -- '---\nlayout: page\ntitle: Methodology\npermalink: /methodology/\n---\n{%% raw %%}\n'
  sed -E \
    -e "s#\]\((resources/[^)]*\.(png|svg))\)#](${raw}/\1)#g" \
    -e "s#\]\(((resources|src|tests|scripts)/[^)]*)\)#](${repo}/blob/main/\1)#g" \
    -e "s#\]\((README|CONTRIBUTING)\.md(\#[^)]*)?\)#](${repo}/blob/main/\1.md\2)#g" \
    "$root/METHODOLOGY.md"
  printf '\n{%% endraw %%}\n'
} > "$docs/methodology.md"
