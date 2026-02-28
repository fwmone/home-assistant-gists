#!/bin/sh
set -eu

IMMICH_BASE="${IMMICH_BASE}"
ENDPOINT="$IMMICH_BASE/api/search/metadata"
EINKOPTIMIZE="${EINKOPTIMIZE}"
HOMEASSISTANT_PUBLIC_ADDRESS="${HOMEASSISTANT_PUBLIC_ADDRESS}"

# Zielordner (muss existieren)
DEST_DIR_ORIGINALS="${DEST_DIR_ORIGINALS}"
PUBLISH_DIR="${PUBLISH_DIR}"
DEST_DIR_BLOOMIN8="${DEST_DIR_BLOOMIN8}"
DEST_DIR_PAPERLESSPAPER="${DEST_DIR_PAPERLESSPAPER}"

# API-Key. Dann in HA unter secrets.yaml setzen
# und in der shell_command per ENV übergeben (siehe unten).
API_KEY="${IMMICH_API_KEY}"

TMP_JSON="/tmp/immich_favorites.json"
TMP_LIST="/tmp/immich_favorites_urls.txt"
TMP_KEEP_BLOOMIN8="/tmp/immich_favorites_keep_bloomin8.txt"
TMP_KEEP_PAPERLESSPAPER="/tmp/immich_favorites_keep_paperlesspaper.txt"

STATUS_FILE="/config/scripts/immich_sync_favorites.status"
SYNC_OK=1
ERROR_MSG=""

mkdir -p "$DEST_DIR_ORIGINALS" "$PUBLISH_DIR" "$DEST_DIR_BLOOMIN8" "$DEST_DIR_PAPERLESSPAPER"

# 1) Favoritenliste ziehen (paginiert über /api/search/metadata)
: > "$TMP_LIST"
PAGE="1"

while [ -n "$PAGE" ]; do
  PAYLOAD=$(printf '{"page":%s,"withExif":false,"isVisible":true,"language":"de","isFavorite":true}' "$PAGE")

  if ! curl -fsS --connect-timeout 10 --max-time 60 -X POST \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "x-api-key: $API_KEY" \
      "$ENDPOINT" \
      -d "$PAYLOAD" > "$TMP_JSON"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Favoriten-Liste (metadata, page=$PAGE) nicht von Immich herunterladen"
    break
  fi

  # Assets aus Seite extrahieren + nextPage ermitteln (ohne jq)
  PAGE="$(TMP_JSON="$TMP_JSON" TMP_LIST="$TMP_LIST" python3 - << 'PY'
import json, os

tmp_json = os.environ["TMP_JSON"]
tmp_list = os.environ["TMP_LIST"]

with open(tmp_json, "r", encoding="utf-8") as f:
    data = json.load(f)

assets = data.get("assets") or {}
items = assets.get("items") or []

def guess_ext(original_name: str, mime: str) -> str:
    # 1) aus Dateiname
    if original_name and "." in original_name and not original_name.endswith("."):
        ext = "." + original_name.rsplit(".", 1)[1].lower()
    # 2) fallback aus mime
    elif mime and mime.startswith("image/"):
        ext = "." + mime.split("/", 1)[1].lower()
    else:
        ext = ".jpg"

    if ext == ".jpeg":
        ext = ".jpg"
    return ext

with open(tmp_list, "a", encoding="utf-8") as out:
    for it in items:
        asset_id = it.get("id")
        if not asset_id:
            continue
        original = it.get("originalFileName") or ""
        mime = it.get("originalMimeType") or ""
        ext = guess_ext(original, mime)
        out.write(f"{asset_id}|{ext}\n")

next_page = assets.get("nextPage")
if next_page is None:
    print("")
else:
    print(str(next_page).strip())
PY
)"

done

# Wenn Pull schief ging, sauber abbrechen
if [ "$SYNC_OK" -ne 1 ]; then
  echo "error|$(date -Is)|$ERROR_MSG" > "$STATUS_FILE"
  exit 1
fi

# Optional: Deduplizieren (falls Immich mal doppelt liefert)
sort -u "$TMP_LIST" -o "$TMP_LIST"

# 2) Dateien herunterladen + optimieren
: > "$TMP_KEEP_BLOOMIN8"
: > "$TMP_KEEP_PAPERLESSPAPER"

while IFS='|' read -r ID EXT; do
  [ -n "$ID" ] || continue
  [ -n "$EXT" ] || EXT=".jpg"

  FNAME="${ID}${EXT}"
  FNAME_JPG="${ID}.jpg"
  FNAME_PNG="${ID}.png"
  DEST="$DEST_DIR_ORIGINALS/$FNAME"
  DESTOPT_BLOOMIN8="$DEST_DIR_BLOOMIN8/$FNAME_JPG"
  DESTOPT_PAPERLESSPAPER="$DEST_DIR_PAPERLESSPAPER/$FNAME_PNG"
  URL="$IMMICH_BASE/api/assets/$ID/original"

  echo "$FNAME_JPG" >> "$TMP_KEEP_BLOOMIN8"
  echo "$FNAME_PNG" >> "$TMP_KEEP_PAPERLESSPAPER"

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
       -d "{\"imageUrl\":\"${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}\",\"outW\":1200,\"outH\":1600,\"format\":\"jpeg\", \"spectra6_optimize\": 0, \"eink_optimize\": 1, \"fit\":\"cover\", \"gamma\": 0.85, \"saturation\": 1.15, \"lift\": 13, \"liftThreshold\": 90}" \
       -o "$DESTOPT_BLOOMIN8" \
       "$EINKOPTIMIZE"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Bild für Bloomin8 nicht optimieren: ${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}"
    break
  fi

  if ! curl -fsS --connect-timeout 10 --max-time 60 \
       -H "Content-Type: application/json" \
       -d "{\"imageUrl\":\"${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}\",\"outW\":480,\"outH\":800,\"format\":\"png\", \"epd_optimize\": 1, \"color_optimize\": 0, \"fit\":\"cover\"}" \
       -o "$DESTOPT_PAPERLESSPAPER" \
       "$EINKOPTIMIZE"
  then
    SYNC_OK=0
    ERROR_MSG="Konnte Bild für Paperlesspaper nicht optimieren: ${HOMEASSISTANT_PUBLIC_ADDRESS}${PUBLISH_DIR}/${FNAME}"
    break
  fi

  rm -f "$DEST"

done < "$TMP_LIST"

# 3) Aufräumen: lokale Dateien löschen, die nicht mehr Favorit sind
if [ "$SYNC_OK" -eq 1 ]; then
  if [ -d "$DEST_DIR_BLOOMIN8" ]; then
    sort -u "$TMP_KEEP_BLOOMIN8" > "$TMP_KEEP_BLOOMIN8.sorted"

    for f in "$DEST_DIR_BLOOMIN8"/*; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"

      case "$base" in
        *.jpg|*.jpeg|*.png|*.webp) : ;;
        *) continue ;;
      esac

      if ! grep -qx "$base" "$TMP_KEEP_BLOOMIN8.sorted"; then
        rm -f "$f"
      fi
    done
  fi

  if [ -d "$DEST_DIR_PAPERLESSPAPER" ]; then
    sort -u "$TMP_KEEP_PAPERLESSPAPER" > "$TMP_KEEP_PAPERLESSPAPER.sorted"

    for f in "$DEST_DIR_PAPERLESSPAPER"/*; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"

      case "$base" in
        *.jpg|*.jpeg|*.png|*.webp) : ;;
        *) continue ;;
      esac

      if ! grep -qx "$base" "$TMP_KEEP_PAPERLESSPAPER.sorted"; then
        rm -f "$f"
      fi
    done
  fi
fi

if [ "$SYNC_OK" -eq 1 ]; then
  echo "ok|$(date -Is)" > "$STATUS_FILE"
  exit 0
else
  echo "error|$(date -Is)|$ERROR_MSG" > "$STATUS_FILE"
  exit 1
fi
