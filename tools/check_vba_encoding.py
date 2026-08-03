#!/usr/bin/env python3
"""Guard the .bas source against the VBE's ANSI import.

File > Import File... reads .bas source as system ANSI (cp1252 on an
en-AU/en-US box), not UTF-8. A UTF-8 em dash in a comment arrives as three
mojibake characters, and the VBE offers no encoding choice on import. Keeping
the source pure ASCII makes the ANSI read lossless on every code page that is
ASCII-compatible.

The VBE also expects CRLF. A file checked out with bare LF imports as one long
line, so .gitattributes pins *.bas to CRLF and this guard confirms the working
tree actually matches.

Run from anywhere:

    python tools/check_vba_encoding.py

Exit status is 0 when every file passes, 1 when any file fails.
"""

from __future__ import annotations

import sys
from pathlib import Path

MAX_ASCII = 0x7F
UTF8_BOM = b"\xef\xbb\xbf"
CR = 0x0D
LF = 0x0A

# Offsets listed per file before the report truncates. The count is always
# reported in full, so truncation never hides the scale of a problem.
MAX_REPORTED = 20


class EncodingCheckError(Exception):
    """A checked file is not importable by the VBE as written."""


def _describe(offsets: list[int], data: bytes) -> str:
    shown = offsets[:MAX_REPORTED]
    parts = ["0x%04x (byte 0x%02x)" % (off, data[off]) for off in shown]
    if len(offsets) > len(shown):
        parts.append("... %d more" % (len(offsets) - len(shown)))
    return ", ".join(parts)


def check_bytes(data: bytes) -> list[str]:
    """Return one message per problem found. Empty list means the file passes."""
    problems = []

    if data.startswith(UTF8_BOM):
        problems.append(
            "starts with a UTF-8 BOM; the VBE reads it as literal text on the "
            "Attribute line"
        )

    non_ascii = [i for i, b in enumerate(data) if b > MAX_ASCII]
    if non_ascii:
        problems.append(
            "%d non-ASCII byte(s) at %s"
            % (len(non_ascii), _describe(non_ascii, data))
        )

    bare_lf = [
        i for i, b in enumerate(data) if b == LF and (i == 0 or data[i - 1] != CR)
    ]
    if bare_lf:
        problems.append(
            "%d bare LF line ending(s) at %s; the VBE needs CRLF"
            % (len(bare_lf), _describe(bare_lf, data))
        )

    bare_cr = [
        i
        for i, b in enumerate(data)
        if b == CR and (i + 1 >= len(data) or data[i + 1] != LF)
    ]
    if bare_cr:
        problems.append(
            "%d bare CR (no following LF) at %s"
            % (len(bare_cr), _describe(bare_cr, data))
        )

    return problems


def check_file(path: Path) -> list[str]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise EncodingCheckError("cannot read %s: %s" % (path, exc.strerror)) from exc
    return check_bytes(data)


def collect_targets(argv: list[str]) -> list[Path]:
    if argv:
        targets = [Path(arg) for arg in argv]
        missing = [str(p) for p in targets if not p.is_file()]
        if missing:
            raise EncodingCheckError("no such file: %s" % ", ".join(sorted(missing)))
        return targets

    vba_dir = Path(__file__).resolve().parent.parent / "vba"
    if not vba_dir.is_dir():
        raise EncodingCheckError("no vba directory at %s" % vba_dir)
    targets = sorted(vba_dir.glob("*.bas"))
    if not targets:
        # A rename or a move must fail loudly. A guard that silently checks
        # nothing is worse than no guard.
        raise EncodingCheckError("no .bas files found in %s" % vba_dir)
    return targets


def run(argv: list[str]) -> int:
    targets = collect_targets(argv)
    failures = []
    for path in targets:
        problems = check_file(path)
        if problems:
            failures.append((path, problems))
        else:
            print("ok   %s" % path)

    if failures:
        for path, problems in failures:
            for problem in problems:
                print("FAIL %s: %s" % (path, problem))
        raise EncodingCheckError(
            "%d of %d file(s) are not VBE-importable as written"
            % (len(failures), len(targets))
        )

    print("%d file(s) pass: pure ASCII, CRLF, no BOM" % len(targets))
    return 0


def main(argv: list[str]) -> int:
    try:
        return run(argv)
    except EncodingCheckError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
