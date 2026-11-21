#!/usr/bin/env python3
"""Load each committed fixture with the `prov` library and print its record count.

Requires: pip install "prov[rdf]"
"""
import glob
import sys

from prov.model import ProvDocument

paths = sorted(glob.glob("test/fixtures/prov/*.jsonld"))
if not paths:
    sys.exit("no fixtures found")

failed = False
for path in paths:
    try:
        doc = ProvDocument.deserialize(source=path, format="rdf", rdf_format="json-ld")
        count = len(doc.get_records())
    except Exception as exc:  # noqa: BLE001
        print(f"{path}: FAILED {exc!r}")
        failed = True
        continue
    if count == 0:
        print(f"{path}: FAILED no records")
        failed = True
    else:
        print(f"{path}: {count} records")

sys.exit(1 if failed else 0)
