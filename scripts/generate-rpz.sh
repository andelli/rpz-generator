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

REDIRECT_URL="redirecting.mediacepat.id."

IP_KOMDIGI="139.255.196.202"
ZONE_NAME="trustpositifkominfo"
KOMDIGI_SERIAL_FILE="${TMPDIR}/komdigi.serial"
KOMDIGI_DOMAINS="${TMPDIR}/komdigi_domains.txt"

# Service to restart after a successful update (empty to disable)
PDNS_SERVICE="pdns-recursor"

SERIAL=$(date +%Y%m%d%H)
SOURCE_CHANGED=0

mkdir -p "${OUTDIR}" "${TMPDIR}" "${LOCALDIR}"
GREEN='\033[0;32m'
NC='\033[0m'
#################################
# SOURCES
#################################
HAGEZI_SOURCES=(
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/pro.txt"
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/nsfw.txt"
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/popupads.txt"
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
  ! -name 'komdigi_domains.txt' \
  ! -name 'komdigi.serial' \
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
echo "[PROCESS] Processing Komdigi (AXFR)"

echo "[PROCESS] Checking SOA serial ${ZONE_NAME} @ ${IP_KOMDIGI}"

REMOTE_SERIAL=$(
  dig +short SOA "${ZONE_NAME}" @"${IP_KOMDIGI}" \
  | awk '{print $3}'
)

if [[ -z "${REMOTE_SERIAL}" ]]; then
  echo "[!] Failed to retrieve Komdigi SOA serial"
  exit 1
fi

if [[ -f "${KOMDIGI_SERIAL_FILE}" && -f "${KOMDIGI_DOMAINS}" ]] \
  && [[ "$(cat "${KOMDIGI_SERIAL_FILE}")" == "${REMOTE_SERIAL}" ]]; then

  echo -e "${GREEN}[SKIP] Komdigi not modified (serial ${REMOTE_SERIAL})${NC}"

else

  echo "[*] Komdigi updated (serial ${REMOTE_SERIAL})"
  echo "[PROCESS] Transferring zone via AXFR"

  if ! dig +noall +answer AXFR "${ZONE_NAME}" @"${IP_KOMDIGI}" \
      | tr -d '\r' \
      | awk '$4 == "CNAME" { print $1 }' \
      | sed "s/\.${ZONE_NAME}\.$//" \
      | normalize_domain \
      | sort -u > "${KOMDIGI_DOMAINS}"; then
    echo "[!] Komdigi AXFR transfer failed"
    exit 1
  fi

  if [[ ! -s "${KOMDIGI_DOMAINS}" ]]; then
    echo "[!] No domains retrieved from Komdigi AXFR"
    exit 1
  fi

  echo "${REMOTE_SERIAL}" > "${KOMDIGI_SERIAL_FILE}"
  SOURCE_CHANGED=1
  echo "[DONE] Komdigi AXFR finished"
fi
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
  if ! tr -d '\r' < "${FILE}" | grep -q 'CNAME'; then
    echo "[!] HaGeZi source looks invalid (no CNAME records): ${URL}"
    exit 1
  fi

  tr -d '\r' < "${FILE}" \
    | grep 'CNAME' \
    >> "${TMPDIR}/hagezi_raw.txt"
done

if [[ "${SOURCE_CHANGED}" == "0" ]]; then

  STALE=0

  if [[ ! -f "${OUTPUT_FILE}" ]]; then
    STALE=1
  else
    while IFS= read -r MARKER; do
      if [[ "${MARKER}" -nt "${OUTPUT_FILE}" ]]; then
        STALE=1
        break
      fi
    done < <(find "${TMPDIR}" -maxdepth 1 -type f \
               \( -name 'komdigi.serial' -o -name 'hagezi_*.etag' \))
  fi

  if [[ "${STALE}" == "0" ]]; then

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

  echo
  echo -e "${GREEN}[*] Cache markers newer than output - regenerating${NC}"
fi

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
"${KOMDIGI_DOMAINS}" \
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

  awk -v target="${REDIRECT_URL}" \
    '{ print $1 " CNAME " target }' \
    "${KOMDIGI_DOMAINS}"

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

if [[ -n "${PDNS_SERVICE}" ]]; then
  echo
  echo "[PROCESS] Restarting ${PDNS_SERVICE}"
  if systemctl restart "${PDNS_SERVICE}"; then
    echo -e "${GREEN}[DONE] ${PDNS_SERVICE} restarted${NC}"
  else
    echo "[!] Failed to restart ${PDNS_SERVICE}"
    exit 1
  fi
fi

echo "####################################################################################################################################"
