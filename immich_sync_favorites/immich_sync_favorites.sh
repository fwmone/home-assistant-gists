#!/bin/sh
set -eu

IMMICH_BASE="${IMMICH_BASE}"
ENDPOINT="$IMMICH_BASE/api/search/metadata"
EINKOPTIMIZE="${EINKOPTIMIZE}"
HOMEASSISTANT_PUBLIC_ADDRESS="${HOMEASSISTANT_PUBLIC_ADDRESS}"

# Root target directories. The script creates portrait/ and landscape/ below them.
DEST_DIR_ORIGINALS="${DEST_DIR_ORIGINALS}"
PUBLISH_DIR="${PUBLISH_DIR}"
DEST_DIR_BLOOMIN8="${DEST_DIR_BLOOMIN8}"
DEST_DIR_PAPERLESSPAPER="${DEST_DIR_PAPERLESSPAPER}"

API_KEY="${IMMICH_API_KEY}"

TMP_JSON="/tmp/immich_favorites.json"
TMP_LIST="/tmp/immich_favorites_urls.txt"
TMP_KEEP_BLOOMIN8="/tmp/immich_favorites_keep_bloomin8.txt"
TMP_KEEP_PAPERLESSPAPER="/tmp/immich_favorites_keep_paperlesspaper.txt"

STATUS_FILE="/config/scripts/immich_sync_favorites.status"
SYNC_OK=1
ERROR_MSG=""

BLOOMIN8_P="$DEST_DIR_BLOOMIN8/portrait"
BLOOMIN8_L="$DEST_DIR_BLOOMIN8/landscape"
PAPERLESSPAPER_P="$DEST_DIR_PAPERLESSPAPER/portrait"
PAPERLESSPAPER_L="$DEST_DIR_PAPERLESSPAPER/landscape"

mkdir -p \
  "$DEST_DIR_ORIGINALS" \
  "$BLOOMIN8_P" "$BLOOMIN8_L" \
  "$PAPERLESSPAPER_P" "$PAPERLESSPAPER_L"

# 1) Fetch favorites from Immich.
#
# Current Immich search API uses the V3 request shape:
#   filter.isFavorite instead of top-level isFavorite
# and cursor-based pagination instead of page/nextPage.
: > "$TMP_LIST"
CURSOR=""

while :; do
  PAYLOAD="$(CURSOR="$CURSOR" python3 - << 'PY'
import json
import os

payload = {
    "size": 1000,
    "withExif": False,
    "filter": {
        "isFavorite": {"eq":True},
        "type": {"eq":"IMAGE"},
        "visibility": {"eq":"timeline"},
    },
}

cursor = os.environ.get("CURSOR", "")
if cursor:
    payload["cursor"] = cursor

print(json.dumps(payload, separators=(",", ":")))
PY
)"

HTTP_CODE="$(
  curl -sS --connect-timeout 10 --max-time 60 -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "x-api-key: $API_KEY" \
    "$ENDPOINT" \
    -d "$PAYLOAD" \
    -o "$TMP_JSON" \
    -w "%{http_code}"
)"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  SYNC_OK=0
  ERROR_MSG="Immich search failed with HTTP $HTTP_CODE: $(cat "$TMP_JSON")"
  break
fi

  # Extract image assets and nextCursor without jq.
  # width/height are Immich's normalized asset dimensions and therefore already
  # account for EXIF orientation.
  CURSOR="$(TMP_JSON="$TMP_JSON" TMP_LIST="$TMP_LIST" python3 - << 'PY'
import json
import os

tmp_json = os.environ["TMP_JSON"]
tmp_list = os.environ["TMP_LIST"]

with open(tmp_json, "r", encoding="utf-8") as f:
    data = json.load(f)

assets = data.get("assets") or {}
items = assets.get("items") or []

def guess_ext(original_name: str, mime: str) -> str:
    if original_name and "." in original_name and not original_name.endswith("."):
        ext = "." + original_name.rsplit(".", 1)[1].lower()
    elif mime and mime.startswith("image/"):
        ext = "." + mime.split("/", 1)[1].lower()
    else:
        ext = ".jpg"

    if ext == ".jpeg":
        ext = ".jpg"
    return ext

with open(tmp_list, "a", encoding="utf-8") as out:
    for item in items:
        # V3 filter already asks for IMAGE, but keep this defensive check.
        if item.get("type") not in (None, "IMAGE"):
            continue

        asset_id = item.get("id")
        if not asset_id:
            continue

        original = item.get("originalFileName") or ""
        mime = item.get("originalMimeType") or ""
        ext = guess_ext(original, mime)

        width = item.get("width")
        height = item.get("height")

        try:
            width_i = int(width) if width is not None else 0
            height_i = int(height) if height is not None else 0
        except (TypeError, ValueError):
            width_i = 0
            height_i = 0

        # Square images and the extremely unlikely missing-dimension case are
        # assigned to portrait to keep behavior deterministic/backward-friendly.
        orientation = "landscape" if width_i > height_i else "portrait"

        out.write(f"{asset_id}|{ext}|{width_i}|{height_i}|{orientation}\n")

next_cursor = assets.get("nextCursor")
print(str(next_cursor).strip() if next_cursor else "")
PY
)"

  [ -n "$CURSOR" ] || break
done

if [ "$SYNC_OK" -ne 1 ]; then
  echo "error|$(date -Is)|$ERROR_MSG" > "$STATUS_FILE"
  exit 1
fi

# Dedupe in case Immich ever returns an asset twice.
sort -u "$TMP_LIST" -o "$TMP_LIST"

# 2) Download missing originals and optimize into orientation-specific folders.
: > "$TMP_KEEP_BLOOMIN8"
: > "$TMP_KEEP_PAPERLESSPAPER"

while IFS='|' read -r ID EXT WIDTH HEIGHT ORIENTATION; do
  [ -n "$ID" ] || continue
  [ -n "$EXT" ] || EXT=".jpg"

  FNAME="${ID}${EXT}"
  FNAME_JPG="${ID}.jpg"
  FNAME_PNG="${ID}.png"
  DEST="$DEST_DIR_ORIGINALS/$FNAME"
  URL="$IMMICH_BASE/api/assets/$ID/original"

  case "$ORIENTATION" in
    landscape)
      DESTOPT_BLOOMIN8="$BLOOMIN8_L/$FNAME_JPG"
      DESTOPT_PAPERLESSPAPER="$PAPERLESSPAPER_L/$FNAME_PNG"
      KEEP_BLOOMIN8="landscape/$FNAME_JPG"
      KEEP_PAPERLESSPAPER="landscape/$FNAME_PNG"
      BLOOMIN8_W=1600
      BLOOMIN8_H=1200
      PAPERLESSPAPER_W=800
      PAPERLESSPAPER_H=480
      ;;
    *)
      DESTOPT_BLOOMIN8="$BLOOMIN8_P/$FNAME_JPG"
      DESTOPT_PAPERLESSPAPER="$PAPERLESSPAPER_P/$FNAME_PNG"
      KEEP_BLOOMIN8="portrait/$FNAME_JPG"
      KEEP_PAPERLESSPAPER="portrait/$FNAME_PNG"
      BLOOMIN8_W=1200
      BLOOMIN8_H=1600
      PAPERLESSPAPER_W=480
      PAPERLESSPAPER_H=800
      ;;
  esac

  echo "$KEEP_BLOOMIN8" >> "$TMP_KEEP_BLOOMIN8"
  echo "$KEEP_PAPERLESSPAPER" >> "$TMP_KEEP_PAPERLESSPAPER"

  # Already fully processed in the correct orientation folder.
  if [ -f "$DESTOPT_BLOOMIN8" ] && [ -f "$DESTOPT_PAPERLESSPAPER" ]; then
    continue
  fi

  if ! curl -fsS --connect-timeout 10 --max-time 60 \
       -H "x-api-key: $API_KEY" \
       -o "$DEST" \
       "$URL"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Bild nicht herunterladen: ${URL}"
    break
  fi

  if ! curl -fsS --connect-timeout 10 --max-time 60 \
       -H "Content-Type: application/json" \
       -d "{\"imageUrl\":\"${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}\",\"outW\":${BLOOMIN8_W},\"outH\":${BLOOMIN8_H},\"format\":\"jpeg\",\"spectra6_optimize\":0,\"eink_optimize\":1,\"fit\":\"cover\",\"gamma\":0.85,\"saturation\":1.15,\"lift\":13,\"liftThreshold\":90}" \
       -o "$DESTOPT_BLOOMIN8" \
       "$EINKOPTIMIZE"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Bild für Bloomin8 nicht optimieren: ${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}"
    rm -f "$DEST"
    break
  fi

  if ! curl -fsS --connect-timeout 10 --max-time 60 \
       -H "Content-Type: application/json" \
       -d "{\"imageUrl\":\"${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}\",\"outW\":${PAPERLESSPAPER_W},\"outH\":${PAPERLESSPAPER_H},\"format\":\"png\",\"epd_optimize\":0,\"color_optimize\":0,\"fit\":\"cover\"}" \
       -o "$DESTOPT_PAPERLESSPAPER" \
       "$EINKOPTIMIZE"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Bild für Paperlesspaper nicht optimieren: ${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}"
    rm -f "$DEST"
    break
  fi

  rm -f "$DEST"
done < "$TMP_LIST"

# 3) Cleanup: remove optimized files that are no longer current Immich favorites
# or that now belong to the other orientation folder.
if [ "$SYNC_OK" -eq 1 ]; then
  sort -u "$TMP_KEEP_BLOOMIN8" > "$TMP_KEEP_BLOOMIN8.sorted"
  sort -u "$TMP_KEEP_PAPERLESSPAPER" > "$TMP_KEEP_PAPERLESSPAPER.sorted"

  for orientation in portrait landscape; do
    DIR="$DEST_DIR_BLOOMIN8/$orientation"
    for f in "$DIR"/*; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"

      case "$base" in
        *.jpg|*.jpeg|*.png|*.webp) : ;;
        *) continue ;;
      esac

      rel="$orientation/$base"
      if ! grep -Fqx "$rel" "$TMP_KEEP_BLOOMIN8.sorted"; then
        rm -f "$f"
      fi
    done
  done

  for orientation in portrait landscape; do
    DIR="$DEST_DIR_PAPERLESSPAPER/$orientation"
    for f in "$DIR"/*; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"

      case "$base" in
        *.jpg|*.jpeg|*.png|*.webp) : ;;
        *) continue ;;
      esac

      rel="$orientation/$base"
      if ! grep -Fqx "$rel" "$TMP_KEEP_PAPERLESSPAPER.sorted"; then
        rm -f "$f"
      fi
    done
  done

  # Remove legacy optimized image files left directly in the root directories by
  # pre-orientation versions of this script. Only files are removed; the new
  # portrait/landscape directories are untouched.
  for f in "$DEST_DIR_BLOOMIN8"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      *.jpg|*.jpeg|*.png|*.webp) rm -f "$f" ;;
    esac
  done

  for f in "$DEST_DIR_PAPERLESSPAPER"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      *.jpg|*.jpeg|*.png|*.webp) rm -f "$f" ;;
    esac
  done
fi

# Remove a possibly leftover original if the run failed between download and cleanup.
# On success, originals are already deleted one by one.
if [ "$SYNC_OK" -eq 1 ]; then
  echo "ok|$(date -Is)" > "$STATUS_FILE"
  exit 0
else
  echo "error|$(date -Is)|$ERROR_MSG" > "$STATUS_FILE"
  exit 1
fi
