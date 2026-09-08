#!/usr/bin/env bash
#
# Regenerate the site image assets from the Koikoi app repository.
#
# Usage: Scripts/assets.sh [path-to-koikoi-swift]
#
# Produces, under static/img/:
#   screenshots/{en,ja}/*.webp  app screenshots, resized and encoded as WebP
#   cards/*.webp                the five bright hanafuda cards used in the hero
#   icon.png                    the app icon (artwork SVG on the icon's cream background)
#   icon-512.png                a 512px copy of it
#
# Intermediate PNGs are written to a temporary directory and never land in the
# repository. The script is idempotent: running it again just overwrites.

set -euo pipefail

APP_REPO=${1:-../koikoi-swift}
SITE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ ! -d "$APP_REPO" ]; then
  echo "error: app repository not found at $APP_REPO" >&2
  exit 1
fi
APP_REPO=$(cd "$APP_REPO" && pwd)

SHOTS_SRC="$APP_REPO/fastlane/screenshots"
CARDS_SRC="$APP_REPO/Resources/Assets.xcassets/Cards"
IMG_DIR="$SITE_ROOT/static/img"

WEBP_QUALITY=82

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/koikoi-assets.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required but not installed" >&2; exit 1; }
}
need cwebp
need sips

# resize_to_webp <source-png> <target-width> <destination-webp>
resize_to_webp() {
  local src=$1 width=$2 dest=$3
  local tmp="$TMP_DIR/$(basename "$dest" .webp)-$RANDOM.png"
  sips --resampleWidth "$width" "$src" --out "$tmp" >/dev/null
  cwebp -quiet -q "$WEBP_QUALITY" "$tmp" -o "$dest" >/dev/null
  rm -f "$tmp"
}

# Screenshot map: <output name>|<source path under fastlane/screenshots, %s = locale>|<width>
SHOTS="
iphone-game|ios/%s/2_iphone69_game.png|660
iphone-night|ios/%s/4_iphone69_night.png|660
iphone-setup|ios/%s/1_iphone69_setup.png|660
iphone-landscape|ios/%s/5_iphone69_landscape.png|1440
ipad-game|ios/%s/2_ipad13_game.png|1032
mac-translucent|mac/%s/5_mac_translucent.png|1440
vision-game|visionos/%s/2_visionpro_game.png|1920
vision-board|visionos/%s/5_visionpro_board.png|1920
"

echo "==> Screenshots"
for pair in "en:en-US" "ja:ja"; do
  lang=${pair%%:*}
  locale=${pair##*:}
  out_dir="$IMG_DIR/screenshots/$lang"
  mkdir -p "$out_dir"
  while IFS='|' read -r name pattern width; do
    [ -n "$name" ] || continue
    # shellcheck disable=SC2059
    src="$SHOTS_SRC/$(printf "$pattern" "$locale")"
    if [ ! -f "$src" ]; then
      echo "  skip $lang/$name.webp (missing $src)" >&2
      continue
    fi
    resize_to_webp "$src" "$width" "$out_dir/$name.webp"
    echo "  $lang/$name.webp"
  done <<< "$SHOTS"
done

echo "==> Cards"
CARDS="00_matsu_tsuru 08_sakura_maku 28_susuki_tsuki 40_yanagi_michikaze 44_kiri_hoo"
CARD_WIDTH=374
mkdir -p "$IMG_DIR/cards"
for card in $CARDS; do
  slug=$(echo "${card#*_}" | tr '_' '-')
  svg="$CARDS_SRC/$card.imageset/$card.svg"
  if [ ! -f "$svg" ]; then
    echo "  skip cards/$slug.webp (missing $svg)" >&2
    continue
  fi
  png="$TMP_DIR/$slug.png"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$CARD_WIDTH" "$svg" -o "$png"
  else
    # Fall back to the QuickLook renderer that ships with macOS.
    qlmanage -t -s $((CARD_WIDTH * 2)) -o "$TMP_DIR" "$svg" >/dev/null 2>&1
    sips --resampleWidth "$CARD_WIDTH" "$TMP_DIR/$(basename "$svg").png" --out "$png" >/dev/null
  fi
  cwebp -quiet -q "$WEBP_QUALITY" "$png" -o "$IMG_DIR/cards/$slug.webp" >/dev/null
  echo "  cards/$slug.webp"
done

echo "==> Icon"
# The app icon is an Icon Composer document; its flat artwork lives in
# AppIconArtwork.svg. Composite it on the icon's light background colour and
# rasterise with the app repository's AppKit renderer (no ImageMagick needed).
ICON_ART="$APP_REPO/Resources/Assets.xcassets/AppIconArtwork.imageset/AppIconArtwork.svg"
ICON_RENDER="$APP_REPO/Scripts/render_icon.swift"
ICON_BG="#F4EDDC"
if [ -f "$ICON_ART" ] && [ -f "$ICON_RENDER" ]; then
  composed="$TMP_DIR/icon.svg"
  {
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\">"
    echo "<rect width=\"1024\" height=\"1024\" fill=\"$ICON_BG\"/>"
    sed -e '1,/<svg/d' -e 's#</svg>##' -e '/<!--/d' "$ICON_ART"
    echo "</svg>"
  } > "$composed"
  swift "$ICON_RENDER" "$composed" "$IMG_DIR/icon.png" 1024
  echo "  icon.png"
else
  echo "  skip icon.png (missing $ICON_ART or $ICON_RENDER)" >&2
fi
sips -Z 512 "$IMG_DIR/icon.png" --out "$IMG_DIR/icon-512.png" >/dev/null
echo "  icon-512.png"

echo "Done."
