<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The ZIP container

Reading uses `archive.unpack`. Writing does not use `archive.pack`.

## ODF requires a member the library cannot write

An ODF container must carry `mimetype` as its **first** member, **stored
uncompressed**, so that a magic-byte sniffer finds the media type at a fixed
offset:

```
0..30    the local file header
30..38   the member name, which must be exactly "mimetype"
38..     the media type, in the clear
```

`archive.pack` preserves the order it is given but always deflates, with no
per-entry control. The result:

| Writer | what `file(1)` reports |
|---|---|
| `archive.pack` | `Zip archive data, ... method=deflate` |
| `src/topics/zip.j` | **`OpenDocument Spreadsheet`** |

A desktop treats a file identified as a generic archive as an archive, not a
spreadsheet. So the deck writes the local file headers, central directory and
end-of-central-directory record itself, choosing stored or deflated per
member. The checksum comes from `crc.compute(b, "crc32")`, which
returns four big-endian `bytes` rather than an int, and the payload from
`compress.pack(b, "deflate")`.

Checked with Python's `zipfile` (`testzip()` clean, CRCs correct), `unzip -t`
and `file(1)`. A well-formed container can still be refused by a spreadsheet
application, which is what `tools/validate-output.sh` checks in its own CI
job.

## Not supported

- **No ZIP64.** Member count and offsets are 16 and 32 bits, so the writer
  refuses more than 65 535 members or 4 GiB instead of writing a corrupt
  archive. Reading large archives goes through `archive.unpack`, whose
  ZIP64 support is untested here.
- **No timestamps.** Modification time and date are written as zero, so the
  same workbook always gives the same bytes.

## Reading

`archive.unpack` reads the central directory, so it handles **data
descriptors** (general-purpose bit 3, sizes after the payload), which Excel
emits. Tested.
