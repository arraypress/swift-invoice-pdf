#!/usr/bin/env python3
"""Validate Factur-X XML against the official schema and the profile's own rules.

Two stages, which is what a real validator does:

  1. XSD  — the UN/CEFACT CII D16B schema, structure and element order.
  2. Schematron — the Factur-X profile rules from the specification, compiled
     to XSLT and run with Saxon, giving SVRL back.

The profile rules are the ones that matter: MINIMUM and BASIC WL are not
EN 16931 profiles, so the EN 16931 ruleset is the wrong book to mark them
against.
"""

import subprocess
import sys
from pathlib import Path

from saxonche import PySaxonProcessor

# Everything fetched lives in .validator/, which validate-facturx.sh fills
# and .gitignore keeps out — the artefacts are published, not ours to vendor.
HERE = Path(__file__).parent.parent / ".validator"
ISO = HERE / "iso"
SCH = HERE / "mustangproject-master/validator/src/main/resources/schematron/ZF_250"
XSD = (HERE / "eInvoicing-EN16931-master/cii/schema/D16B SCRDM (Subset)/uncoupled clm"
       / "CII/uncefact/data/standard/CrossIndustryInvoice_100pD16B.xsd")

PROFILES = {
    "urn:factur-x.eu:1p0:minimum": "FACTUR-X_MINIMUM.sch",
    "urn:factur-x.eu:1p0:basicwl": "FACTUR-X_BASIC-WL.sch",
    "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic": "FACTUR-X_BASIC.sch",
    "urn:cen.eu:en16931:2017": "FACTUR-X_EN16931.sch",
}


def compile_schematron(proc, sch: Path) -> str:
    """Schematron to SVRL-producing XSLT: include, expand, then compile."""
    out = str(sch)
    for stage in ["iso_dsdl_include.xsl", "iso_abstract_expand.xsl", "iso_svrl_for_xslt2.xsl"]:
        xslt = proc.new_xslt30_processor()
        executable = xslt.compile_stylesheet(stylesheet_file=str(ISO / stage))
        result = executable.transform_to_string(source_file=out)
        out = str(sch.parent / f"stage-{stage}.xml")
        Path(out).write_text(result)
    return out


def profile_of(xml: Path) -> str:
    text = xml.read_text()
    start = text.find("<ram:ID>", text.find("GuidelineSpecifiedDocumentContextParameter"))
    return text[start + 8:text.find("</ram:ID>", start)].strip()


def validate(xml: Path) -> tuple[int, int]:
    print(f"\n{'=' * 78}\n{xml.name}\n{'=' * 78}")

    profile = profile_of(xml)
    print(f"profile   {profile}")

    schema = subprocess.run(
        ["xmllint", "--noout", "--schema", str(XSD), str(xml)],
        capture_output=True, text=True,
    )
    passed = "validates" in schema.stderr
    print(f"schema    {'passes the CII D16B schema' if passed else 'FAILS'}")
    if not passed:
        for line in schema.stderr.strip().splitlines()[:15]:
            print(f"          {line}")

    sch = SCH / PROFILES[profile]
    with PySaxonProcessor(license=False) as proc:
        compiled = compile_schematron(proc, sch)
        xslt = proc.new_xslt30_processor()
        executable = xslt.compile_stylesheet(stylesheet_file=compiled)
        svrl = executable.transform_to_string(source_file=str(xml))

    import xml.etree.ElementTree as ET
    SVRL = "{http://purl.oclc.org/dsdl/svrl}"
    tree = ET.fromstring(svrl)
    fired = tree.findall(f".//{SVRL}fired-rule")
    failures = []
    for tag in ("failed-assert", "successful-report"):
        for node in tree.iter(SVRL + tag):
            text = " ".join("".join(node.itertext()).split())
            failures.append((tag, node.get("id") or "\u2014", text))

    print(f"rules     {sch.name}: {len(fired)} rules fired, {len(failures)} findings")
    for kind, ident, text in failures:
        print(f"          [{ident}] {text[:150]}")

    return (0 if passed else 1) + len(failures), len(fired)


if __name__ == "__main__":
    problems = 0
    for path in sys.argv[1:]:
        found, fired = validate(Path(path))
        problems += found
        if fired == 0:
            print("          WARNING: no rules fired — the ruleset may not have matched anything")

    print(f"\n{'=' * 78}")
    print("Everything validates." if problems == 0 else f"{problems} problems.")
    sys.exit(1 if problems else 0)
