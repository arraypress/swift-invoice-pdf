#!/usr/bin/env bash
#
# Put the XML this library writes through a real validator.
#
# Two stages, which is what any conformance check does:
#
#   1. The UN/CEFACT CII D16B schema — structure, element order, data types.
#      CII declares a sequence, so an element in the wrong place is a
#      rejection, not a warning.
#   2. The Factur-X profile rules, as Schematron, from the specification.
#      Minimum and Basic WL are not EN 16931 profiles, so the EN 16931
#      ruleset is the wrong book to mark them against — each profile has its
#      own, and this uses the right one for whichever the document declares.
#
# Nothing is uploaded anywhere. The artefacts are public and fetched once
# into .validator/, which is gitignored; the invoices stay on this machine.
#
# Needs: python3, xmllint (both ship with macOS). Saxon arrives through pip
# into a virtualenv here, because the Schematron is XSLT 2.0 and xsltproc
# only does 1.0. No JDK.
#
# Usage:
#   Scripts/validate-facturx.sh                  # generates a matrix and checks it
#   Scripts/validate-facturx.sh some/file.xml …  # checks the files you name
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache="$root/.validator"
mkdir -p "$cache"

say() { printf '\033[36m%s\033[0m\n' "$*"; }

# ── The published artefacts ────────────────────────────────────────────────

if [ ! -d "$cache/eInvoicing-EN16931-master" ]; then
  say "Fetching the EN 16931 reference artefacts (the CII schema)…"
  curl -sL -o "$cache/en16931.zip" \
    https://github.com/ConnectingEurope/eInvoicing-EN16931/archive/refs/heads/master.zip
  unzip -q -o "$cache/en16931.zip" -d "$cache"
fi

if [ ! -d "$cache/mustangproject-master" ]; then
  say "Fetching the Factur-X profile rules…"
  curl -sL -o "$cache/mustang.zip" \
    https://github.com/ZUGFeRD/mustangproject/archive/refs/heads/master.zip
  unzip -q -o "$cache/mustang.zip" -d "$cache"
fi

if [ ! -d "$cache/iso" ]; then
  say "Fetching the ISO Schematron compiler…"
  mkdir -p "$cache/iso"
  base=https://raw.githubusercontent.com/Schematron/schematron/master/trunk/schematron/code
  for f in iso_dsdl_include.xsl iso_abstract_expand.xsl iso_svrl_for_xslt2.xsl \
           iso_schematron_skeleton_for_saxon.xsl; do
    curl -sfL -o "$cache/iso/$f" "$base/$f"
  done
fi

if [ ! -x "$cache/venv/bin/python" ]; then
  say "Installing Saxon…"
  python3 -m venv "$cache/venv"
  "$cache/venv/bin/pip" install -q saxonche
fi

# ── The documents ──────────────────────────────────────────────────────────

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  say "Generating a document for every treatment, profile and currency…"
  out="$cache/xml"
  rm -rf "$out" && mkdir -p "$out"
  swift run --package-path "$root/Scripts/Generator" generator "$out"
  files=("$out"/*.xml)
fi

exec "$cache/venv/bin/python" "$root/Scripts/facturx-validate.py" "${files[@]}"
