#!/usr/bin/env bash

set -euo pipefail

#################################
# CONFIG
#################################

WORKDIR="/opt/rpz"
OUTDIR="${WORKDIR}/generated"
TMPDIR="${WORKDIR}/tmp"
LOCALDIR="${WORKDIR}/local"

OUTPUT_FILE="${OUTDIR}/combined.rpz"
SAFESEARCH_FILE="${LOCALDIR}/safesearch.txt"

KOMDIGI_TARGET="redirecting.mediacepat.id."

SERIAL=$(date +%Y%m%d%H)

mkdir -p "${OUTDIR}" "${TMPDIR}" "${LOCALDIR}"

#################################
# SOURCES
#################################

HAGEZI_SOURCES=(
  "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/pro.txt"
  "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/nsfw.txt"
  "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/popupads.txt"
)

KOMDIGI_SOURCES=(
  "https://trustpositif.komdigi.go.id/assets/dns_zone/trustpositifkominfo"
)

#################################
# FUNCTIONS
#################################

generate_header() {
cat <<EOF
\$TTL 60
@ IN SOA localhost. root.localhost. (
  ${SERIAL}
  1h
  15m
  30d
  2h
)

@ IN NS localhost.

EOF
}

download_file() {
  local url="$1"
  local file="$2"

  echo "[*] Downloading ${url}"

  curl -L \
    --fail \
    --silent \
    --show-error \
    "${url}" \
    -o "${file}"
}

normalize_domain() {
  tr '[:upper:]' '[:lower:]' \
  | sed 's/\.$//' \
  | sed 's/^www\.//' \
  | grep -E '^[a-z0-9._*-]+$' \
  | awk 'length($0) <= 253'
}

#################################
# CLEAN
#################################

rm -f "${TMPDIR}"/*

#################################
# KOMDIGI
#################################

echo "[*] Processing Komdigi"

> "${TMPDIR}/komdigi_domains.txt"

COUNT=0

for URL in "${KOMDIGI_SOURCES[@]}"; do

  COUNT=$((COUNT + 1))

  FILE="${TMPDIR}/komdigi_${COUNT}.txt"

  download_file "${URL}" "${FILE}"

  cat "${FILE}" \
    | tr -d '\r' \
    | grep 'CNAME' \
    | awk '{print $1}' \
    | normalize_domain \
    >> "${TMPDIR}/komdigi_domains.txt"

done

sort -u \
  "${TMPDIR}/komdigi_domains.txt" \
  -o "${TMPDIR}/komdigi_domains.txt"

#################################
# BUILD KOMDIGI DOMAIN MAP
#################################

awk '
{
    d[$1]=1
}
END{
    for(i in d)
        print i
}
' "${TMPDIR}/komdigi_domains.txt" \
| sort \
> "${TMPDIR}/komdigi_unique.txt"

#################################
# HAGEZI
#################################

echo "[*] Processing HaGeZi"

> "${TMPDIR}/hagezi_raw.txt"

COUNT=0

for URL in "${HAGEZI_SOURCES[@]}"; do

  COUNT=$((COUNT + 1))

  FILE="${TMPDIR}/hagezi_${COUNT}.txt"

  download_file "${URL}" "${FILE}"

  cat "${FILE}" \
    | tr -d '\r' \
    | grep 'CNAME' \
    >> "${TMPDIR}/hagezi_raw.txt"

done

#################################
# REMOVE DOMAINS
# THAT ALREADY EXIST IN KOMDIGI
#################################

awk '
NR==FNR {
    komdigi[tolower($1)] = 1
    next
}

{
    domain = tolower($1)

    base = domain
    gsub(/^\*\./,"",base)

    if (!(base in komdigi))
        print
}
' \
"${TMPDIR}/komdigi_unique.txt" \
"${TMPDIR}/hagezi_raw.txt" \
| sort -u \
> "${TMPDIR}/hagezi_filtered.txt"

#################################
# GENERATE RPZ
#################################

echo "[*] Generating RPZ"

{
  generate_header

  #################################
  # SAFESEARCH
  #################################

  if [[ -f "${SAFESEARCH_FILE}" ]]; then

    echo "; ==================================="
    echo "; SAFESEARCH"
    echo "; ==================================="

    cat "${SAFESEARCH_FILE}" \
      | tr -d '\r' \
      | grep -Ev '^\s*$|^\s*#|^\s*;'

    echo

  fi

  #################################
  # KOMDIGI FIRST
  #################################

  echo "; ==================================="
  echo "; KOMDIGI"
  echo "; ==================================="

  awk -v target="${KOMDIGI_TARGET}" '
  {
      print $1 " CNAME " target
      print "*." $1 " CNAME " target
  }
  ' "${TMPDIR}/komdigi_unique.txt"

  echo

  #################################
  # HAGEZI SECOND
  #################################

  echo "; ==================================="
  echo "; HAGEZI"
  echo "; ==================================="

  cat "${TMPDIR}/hagezi_filtered.txt"

} > "${OUTPUT_FILE}"

#################################
# VALIDATION
#################################

echo "[*] Checking RPZ conflicts"

CONFLICTS=$(
awk '
$1 ~ /^;/ {next}

toupper($2) != "CNAME" {next}

{
    name=tolower($1)
    target=tolower($3)

    if(seen[name] && seen[name] != target)
        conflicts++

    seen[name]=target
}
END{
    print conflicts+0
}
' "${OUTPUT_FILE}"
)
#################################
# STATS
#################################

TOTAL_RECORDS=$(grep -vc '^$\|^\s*;' "${OUTPUT_FILE}")

echo
echo "=============================="
echo "RPZ GENERATED"
echo "=============================="
echo "Output      : ${OUTPUT_FILE}"
echo "Records     : ${TOTAL_RECORDS}"
echo "Conflicts   : ${CONFLICTS}"
echo "=============================="

if [[ "${CONFLICTS}" != "0" ]]; then
  echo
  echo "ERROR: RPZ conflict detected!"
  exit 1
fi

echo
echo "RPZ validation passed."
