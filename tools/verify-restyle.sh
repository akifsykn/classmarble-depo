#!/usr/bin/env bash
# ClassMarble görsel restyle doğrulama harness'i.
#
# Kullanım:
#   tools/verify-restyle.sh                 -> mevcut assets/ setini denetle
#   tools/verify-restyle.sh <orijinal-dizin> -> ayrıca orijinal ile yan yana diff montage üret
#
# Çıktı: her görsel için PASS/FAIL + set geneli tutarlılık raporu.
# Referans bant: Göknur v2.1 restyle seti (köşe 216-234, ortalama 185-218).

set -uo pipefail

SITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SITE_DIR/assets"
ORIG_DIR="${1:-}"
OUT="${TMPDIR:-/tmp}/classmarble-verify"
mkdir -p "$OUT"

# --- eşikler (assets/_restyle-spec.json ile aynı) ---
CORNER_MIN=210      # arka plan köşe parlaklığı alt sınır
CORNER_MAX=240      # üst sınır
NEUTRAL_MAX=18      # |R-B| — soğuk/nötr arka plan kontrolü
MEAN_MIN=150
MEAN_MAX=215
# Not: Goknur v2.1 restyle seti 32-88KB araliginda. Temiz/duz arka plan cok iyi
# sikistigi icin dosyalar kucuk cikar — bu kalite dususu degil, basari isaretidir.
# Alt sinir bu yuzden 25KB; ust sinir sayfa agirligi icin 260KB.
SIZE_MIN=25000      # 25KB
SIZE_MAX=260000     # 260KB

fail_count=0
pass_count=0
means=()

printf "%-42s %-11s %-16s %-8s %-9s %s\n" "DOSYA" "BOYUT" "KOSE(R,G,B)" "|R-B|" "ORTALAMA" "SONUC"
printf '%.0s-' {1..104}; echo

for f in "$ASSETS"/*.webp; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"

  dims=$(identify -format "%wx%h" "$f" 2>/dev/null)
  bytes=$(stat -c%s "$f")

  read -r cr cg cb <<<"$(convert "$f" -resize 200x200! -colorspace sRGB \
    -format "%[fx:int(255*p{10,10}.r)] %[fx:int(255*p{10,10}.g)] %[fx:int(255*p{10,10}.b)]" info:)"
  mean=$(convert "$f" -resize 100x100! -colorspace sRGB \
    -format "%[fx:int(255*mean)]" info:)

  rb=$(( cr - cb )); [ $rb -lt 0 ] && rb=$(( -rb ))
  means+=("$mean")

  reasons=""
  [ "$cr" -lt $CORNER_MIN ] || [ "$cr" -gt $CORNER_MAX ] && reasons="${reasons}kose-parlaklik "
  [ "$rb" -gt $NEUTRAL_MAX ] && reasons="${reasons}sicak-ton "
  [ "$mean" -lt $MEAN_MIN ] || [ "$mean" -gt $MEAN_MAX ] && reasons="${reasons}ortalama "
  [ "$bytes" -lt $SIZE_MIN ] || [ "$bytes" -gt $SIZE_MAX ] && reasons="${reasons}dosya-boyutu "

  if [ -n "$ORIG_DIR" ] && [ -f "$ORIG_DIR/$name" ]; then
    odims=$(identify -format "%wx%h" "$ORIG_DIR/$name" 2>/dev/null)
    [ "$dims" != "$odims" ] && reasons="${reasons}BOYUT-DEGISTI($odims->$dims) "
    # geometri gözle denetimi için yan yana montage
    montage "$ORIG_DIR/$name" "$f" -tile 2x1 -geometry 600x+8+8 \
      -background '#2b2b2b' -label '%f' "$OUT/diff-$name.jpg" >/dev/null 2>&1
  fi

  if [ -z "$reasons" ]; then
    printf "%-42s %-11s %-16s %-8s %-9s %s\n" "$name" "$dims" "$cr,$cg,$cb" "$rb" "$mean" "PASS"
    pass_count=$((pass_count+1))
  else
    printf "%-42s %-11s %-16s %-8s %-9s %s\n" "$name" "$dims" "$cr,$cg,$cb" "$rb" "$mean" "FAIL: $reasons"
    fail_count=$((fail_count+1))
  fi
done

# --- set geneli tutarlılık (standart sapma) ---
if [ ${#means[@]} -gt 0 ]; then
  sd=$(printf '%s\n' "${means[@]}" | awk '{s+=$1; a[NR]=$1} END {m=s/NR; for(i=1;i<=NR;i++) v+=(a[i]-m)^2; printf "%.1f", sqrt(v/NR)}')
  echo
  echo "Set ortalama parlaklik std sapmasi: $sd  (hedef < 25; Goknur referansi ~10)"
fi

echo
echo "PASS: $pass_count   FAIL: $fail_count"
if [ -n "$ORIG_DIR" ]; then
  echo "Geometri denetimi icin yan yana diff'ler: $OUT/diff-*.jpg"
  echo "  -> Her birini GOZLE ac: kenar sayisi, bolme sayisi, delik sayisi, damar deseni eslesmeli."
fi

[ "$fail_count" -eq 0 ]
