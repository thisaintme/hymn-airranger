# v0.1.0-alpha.4 — Bass naming

The part previously displayed as Lower voice is now **Bass**, abbreviated **B**.
Choir selectors, score headers, Practice controls, new PDF/MusicXML output and
rehearsal-track filenames use Bass. The sidebar uses S/A/T/B abbreviations.
The AI planner explicitly maps Bass requests to the existing voice.

This is a display-name change, not a musical change: notes, rhythms, dynamics,
ranges, voice ordering and previous versions are unchanged. In saved project
data the identifier remains `lower`, preserving format-1/format-2 compatibility.
Previous prompt text and exported files are not rewritten. Re-export existing
scores and tracks to obtain the new labels. Both Bass and lower voice remain
accepted request aliases. No project migration or API-key reset is required.

Five new regression tests cover labels, the persisted identifier, default and
customized ranges, legacy project/history round trips, full/individual score
labels and request aliases. Consult the associated macOS workflow for results.

Quit the previous app, replace it in Applications and reopen it. This remains
an ad-hoc-signed, non-notarized development alpha.
