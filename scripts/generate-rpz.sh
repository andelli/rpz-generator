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
SOURCE_CHANGED=0

mkdir -p "${OUTDIR}" "${TMPDIR}" "${LOCALDIR}"
GREEN='\033[0;32m'
NC='\033[0m'
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

  echo "[PROCESS] Downloading ${url}"

  curl -L \
    --fail \
    --silent \
    --show-error \
    "${url}" \
    -o "${file}"
}
download_if_modified() {
  local url="$1"
  local file="$2"

  echo "[*] Checking ${url}"

  HTTP_CODE=$(
    curl -s -L \
      -z "${file}" \
      -o "${file}.tmp" \
      -w "%{http_code}" \
      "${url}"
  )

  case "${HTTP_CODE}" in
    200)
      mv "${file}.tmp" "${file}"
      echo "[*] Updated"
      ;;
    304)
      rm -f "${file}.tmp"
      echo -e "${GREEN}[*] not modified${NC}"
      ;;
    *)
      rm -f "${file}.tmp"
      echo "[!] Download failed (${HTTP_CODE})"
      exit 1
      ;;
  esac
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
find "${TMPDIR}" \
  -type f \
  ! -name 'komdigi_*.txt' \
  ! -name 'komdigi_*.etag' \
  ! -name 'hagezi_*.txt' \
  ! -name 'hagezi_*.etag' \
  -delete
#################################
# KOMDIGI
#################################
echo "####################################################################################################################################"
echo "=============================="
echo "RPZ GENERATOR"
echo "=============================="
echo "Script by    : Andeli"
echo "Powered by   : ChatGPT + Rokok LA Bold"
echo "=============================="
echo "####################################################################################################################################"
echo "[PROCESS] Processing Komdigi"

COUNT=0
for URL in "${KOMDIGI_SOURCES[@]}"; do

  echo "[PROCESS] Checking ETAG ${URL}"

  COUNT=$((COUNT + 1))

  FILE="${TMPDIR}/komdigi_${COUNT}.txt"
  ETAG_FILE="${TMPDIR}/komdigi_${COUNT}.etag"

  REMOTE_ETAG=$(
    curl -sI "${URL}" |
    awk -F'"' '/^etag:/ {print $2}' |
    cut -d'-' -f2
  )

  if [[ -f "${ETAG_FILE}" ]]; then

    LOCAL_ETAG=$(cut -d'-' -f2 < "${ETAG_FILE}" | tr -d '"\r')

    if [[ "${LOCAL_ETAG}" == "${REMOTE_ETAG}" ]]; then

      echo -e "${GREEN}[SKIP] Komdigi not modified${NC}"

    else

      echo "[*] Komdigi updated"

      download_file "${URL}" "${FILE}"

      echo "${REMOTE_ETAG}" > "${ETAG_FILE}"

      SOURCE_CHANGED=1

    fi

  else

    echo "[PROCESS] First download"

    download_file "${URL}" "${FILE}"

    echo -e "${REMOTE_ETAG}" > "${ETAG_FILE}"

    SOURCE_CHANGED=1
    echo "[DONE] Download Finished"
  fi
done
#################################
# HAGEZI
#################################
echo 
echo "[PROCESS] Processing HaGeZi"

> "${TMPDIR}/hagezi_raw.txt"
COUNT=0
for URL in "${HAGEZI_SOURCES[@]}"; do

  COUNT=$((COUNT + 1))

  FILE="${TMPDIR}/hagezi_${COUNT}.txt"
  ETAG_FILE="${TMPDIR}/hagezi_${COUNT}.etag"

  echo "[PROCESS] Checking ETAG ${URL}"

  REMOTE_ETAG=$(
    curl -sI "${URL}" \
    | awk -F': ' '
        BEGIN{IGNORECASE=1}
        /^etag:/{
            gsub("\r","",$2)
            print $2
        }'
  )

  if [[ -z "${REMOTE_ETAG}" ]]; then
    echo "[!] Failed to retrieve ETag"
    exit 1
  fi

  if [[ -f "${ETAG_FILE}" ]]; then

    LOCAL_ETAG=$(cat "${ETAG_FILE}")

    if [[ "${LOCAL_ETAG}" == "${REMOTE_ETAG}" ]]; then

      echo -e "${GREEN}[SKIP] HaGeZi not modified${NC}"

    else

      echo "[UPDATE] HaGeZi updated"

      download_file "${URL}" "${FILE}"

      echo "${REMOTE_ETAG}" > "${ETAG_FILE}"
      SOURCE_CHANGED=1

    fi

  else

    echo "[PROCESS] First download"

    download_file "${URL}" "${FILE}"

    echo "${REMOTE_ETAG}" > "${ETAG_FILE}"
    SOURCE_CHANGED=1
    echo -e "${GREEN}[DONE] Download Finished${NC}"
  fi

  if [[ ! -f "${FILE}" ]]; then
    echo "[!] Missing HaGeZi source file"
    exit 1
  fi
  cat "${FILE}" \
    | tr -d '\r' \
    | grep 'CNAME' \
    >> "${TMPDIR}/hagezi_raw.txt"
done

if [[ "${SOURCE_CHANGED}" == "0" ]]; then

    TOTAL_RECORDS=$(grep -vc '^;' "${OUTPUT_FILE}")

    echo
    echo -e "${GREEN}[*] No source changes detected${NC}"
    echo -e "${GREEN}[*] Existing RPZ is still valid${NC}"
    echo

    echo "=============================="
    echo "RPZ GENERATED (CACHED)"
    echo "=============================="
    echo "Output       : ${OUTPUT_FILE}"
    echo "Records      : ${TOTAL_RECORDS}"
    echo "Current date : $(date)"
    echo "=============================="
    echo "####################################################################################################################################"
    exit 0
fi
  echo "[PROCESS] Building records HaGeZi"
> "${TMPDIR}/komdigi_domains.txt"

for FILE in "${TMPDIR}"/komdigi_[0-9]*.txt; do
  
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
echo "[PROCESS] Building records komdigi"
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
# REMOVE DOMAINS
# THAT ALREADY EXIST IN KOMDIGI
#################################
echo "[PROCESS] Remove Duplicate"
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

echo "[PROCESS] Generating RPZ"

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
echo "[PROCESS] Checking RPZ conflicts ($(wc -l < "${OUTPUT_FILE}") records)"
START=$(date +%s)
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
END=$(date +%s)
echo "[PROCESS] Conflict check completed in $((END-START)) seconds"
#################################
# STATS
#################################

TOTAL_RECORDS=$(grep -vc '^$\|^\s*;' "${OUTPUT_FILE}")

echo
echo "=============================="
echo "RPZ GENERATED"
echo "=============================="
echo "Output       : ${OUTPUT_FILE}"
echo "Records      : ${TOTAL_RECORDS}"
echo "Conflicts    : ${CONFLICTS}"
echo "Last Update  : $(date)"
echo "=============================="


if [[ "${CONFLICTS}" != "0" ]]; then
  echo
  echo "ERROR: RPZ conflict detected!"
  exit 1
fi

echo
echo "RPZ validation passed."

echo "####################################################################################################################################"
