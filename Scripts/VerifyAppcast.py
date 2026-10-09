"""Verify Sparkle's archive signature against the public key embedded by Xcode."""
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

feed, archive, config = map(Path, sys.argv[1:])
key = re.search(r"^CKIT_UPDATE_PUBLIC_KEY\s*=\s*(\S+)", config.read_text(), re.M)[1]
enclosure = ET.parse(feed).find("./channel/item/enclosure")
signature = enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
assert int(enclosure.attrib["length"]) == archive.stat().st_size, "Update archive size mismatch"

# CryptoKit is available on every supported release machine; no crypto dependency.
with tempfile.TemporaryDirectory(prefix="ckit-verify-signature-") as directory:
    source = Path(directory) / "Verify.swift"
    source.write_text('''import CryptoKit
import Foundation
let args = CommandLine.arguments
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: args[1])!)
let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
guard key.isValidSignature(Data(base64Encoded: args[2])!, for: data) else {
    fputs("Update signature does not match Ckit's public key.\\n", stderr)
    exit(1)
}
''')
    subprocess.run(["swift", str(source), key, signature, str(archive)], check=True)
print("Verified Ckit update archive signature.")
