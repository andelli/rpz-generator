# RPZ Generator

Generate a single RPZ (Response Policy Zone) file by combining:

* Komdigi TrustPositif blocklist
* HaGeZi RPZ blocklists
* Optional SafeSearch overrides

The script automatically:

* Downloads source lists
* Detects updates using ETag validation
* Removes duplicate domains
* Gives Komdigi higher priority than HaGeZi
* Generates a valid RPZ zone file
* Validates RPZ conflicts before deployment

---

## Features

* ETag-based update checking
* Incremental downloads
* Automatic duplicate removal
* Komdigi priority over HaGeZi
* RPZ conflict detection
* SafeSearch support
* Cached mode when no source changes occur
* Minimal dependencies

---

## Sources

### Komdigi

Official TrustPositif DNS blocklist:

```text
https://trustpositif.komdigi.go.id/assets/dns_zone/trustpositifkominfo
```

Blocked domains are redirected to:

```text
[REDIRECT_URL]
```


### HaGeZi
[![HaGeZi](https://img.shields.io/badge/Powered%20By-HaGeZi-blue)](https://github.com/hagezi/dns-blocklists)


Official project repository:

[HaGeZi DNS Blocklists GitHub Repository](https://github.com/hagezi/dns-blocklists?utm_source=chatgpt.com)

HaGeZi provides multiple DNS blocklists focused on:

* Ads
* Tracking
* Telemetry
* Malware
* Phishing
* Scam domains
* Fake domains
* Popups
* Privacy protection

The RPZ generator currently uses this repo for additional filtering:

```text
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/pro.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/nsfw.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/popupads.txt
```

Project information, list variants, source references, and documentation are available in the official repository.

## Directory Structure

```text
/opt/rpz
├── generated
│   └── combined.rpz
│
├── tmp
│   ├── komdigi_*.txt
│   ├── komdigi_*.etag
│   ├── hagezi_*.txt
│   └── hagezi_*.etag
│
├── local
│   └── safesearch.txt
│
└── rpz-generator.sh
```

---


## Installation

Clone repository:

```bash
git clone https://github.com/yourusername/rpz-generator.git
cd rpz-generator
```

Make executable:

```bash
chmod +x rpz-generator.sh
```

Run:

```bash
./rpz-generator.sh
```

---

## SafeSearch

Optional SafeSearch rules can be placed in:

```text
/opt/rpz/local/safesearch.txt
```

Example:

```dns
www.google.com CNAME forcesafesearch.google.com.
*.google.com CNAME forcesafesearch.google.com.

www.bing.com CNAME strict.bing.com.
```

Lines beginning with:

```text
#
;
```

or empty lines are ignored.

---

## RPZ Generation Flow

```text
Download Sources
        │
        ▼
Check ETag
        │
        ▼
Build Domain Lists
        │
        ▼
Remove Duplicates
        │
        ▼
Generate RPZ
        │
        ▼
Validate Conflicts
        │
        ▼
combined.rpz
```

---

## Priority Rules

When a domain exists in both sources:

```text
Komdigi > HaGeZi
```

The HaGeZi entry is removed automatically.

Example:

```text
example.com
```

If present in Komdigi:

```dns
example.com CNAME redirecting.mediacepat.id.
*.example.com CNAME redirecting.mediacepat.id.
```

The HaGeZi version will not be included.

---

## Output

Generated file:

```text
/opt/rpz/generated/combined.rpz
```

Example:

```dns
$TTL 60

@ IN SOA localhost. root.localhost. (
  2026053001
  1h
  15m
  30d
  2h
)

@ IN NS localhost.

example.com CNAME redirecting.mediacepat.id.
*.example.com CNAME redirecting.mediacepat.id.
```

---

## Validation

Before completion the script checks for RPZ conflicts:

```text
same-domain -> different-target
```

Example conflict:

```dns
example.com CNAME .
example.com CNAME sinkhole.example.net.
```

If conflicts are detected:

```text
ERROR: RPZ conflict detected!
```

The script exits with status code:

```text
1
```

---

## Automation Example

Run every hour:

```cron
0 * * * * /opt/rpz/rpz-generator.sh
```

Run every 30 minutes:

```cron
*/30 * * * * /opt/rpz/rpz-generator.sh
```

---

## Author

Andeli

Powered by:

* ChatGPT
* Rokok LA Bold
