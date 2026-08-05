# Streaming huge-file and binary-view architecture

`StreamingFileBuffer` is the bounded-memory substrate for editable huge and
binary files. It reads at most 1 MiB per request, records non-overlapping edits
in original byte coordinates, and writes a new file by streaming unchanged
spans and replacements. `BinaryViewModel` converts only the loaded window into
offset/hex/ASCII rows.

The architecture deliberately does not decode arbitrary binary data into the
normal text document. A future UI can page byte windows through this layer and
commit with the existing atomic-file writer. Tests cover reads across the
1 MiB boundary, distant edits in a multi-megabyte file, overlap rejection,
bounded-chunk output, and binary row formatting.
