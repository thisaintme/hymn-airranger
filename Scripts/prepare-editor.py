#!/usr/bin/env python3
"""Bundle pinned local editor resources. No runtime CDN, remote samples or font files."""
from pathlib import Path
import hashlib, json, re, subprocess, shutil
ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'Sources/HymnAIrranger/Resources/Editor/Vendor'
CACHE = ROOT / '.build/EditorDownloads'
DEST.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(parents=True, exist_ok=True)
manifest = json.loads((ROOT/'Scripts/smoosic-dependencies.json').read_text())
for relative, entry in manifest.items():
    cache = CACHE / relative
    cache.parent.mkdir(parents=True, exist_ok=True)
    if not cache.exists():
        partial = cache.with_suffix(cache.suffix+'.partial')
        subprocess.run(['/usr/bin/curl','--fail','--location','--retry','2','--proto','=https','--tlsv1.2',entry['url'],'-o',str(partial)],check=True)
        partial.replace(cache)
    data=cache.read_bytes()
    if hashlib.sha256(data).hexdigest()!=entry['sha256']:
        raise SystemExit('Pinned editor dependency checksum mismatch: '+relative)
    target=DEST/relative;target.parent.mkdir(parents=True, exist_ok=True)
    text=data.decode('utf-8')
    if relative.endswith('.css'):
        text=re.sub(r'@font-face\s*\{[^}]*\}', '',text)
    if relative=='smoosic.js':
        # Formatting-only adapter: no deprecated XSLT dependency in export. This
        # changes neither the MusicXML DOM nor musical values; serializer handles it.
        original='return _common_serializationHelpers__WEBPACK_IMPORTED_MODULE_9__.smoSerialize.prettifyXml(dom);'
        if text.count(original)!=1: raise SystemExit('Pinned Smoosic export adapter no longer matches')
        text=text.replace(original,'return dom; /* Hymn PoC: direct XML serialization, no XSLT formatter. */')
        # The imported SmoNote constructor initially has no tuplet ID and
        # overwrites its written type with the sounding duration. Restore the
        # type already read from XML for explicitly time-modified notes only.
        original='xmlState.previousNote = new _data_note__WEBPACK_IMPORTED_MODULE_10__.SmoNote(noteData);'
        if text.count(original)!=1: raise SystemExit('Pinned tuplet import adapter no longer matches')
        text=text.replace(original, original + " if (noteElement.querySelector('time-modification')) { xmlState.previousNote.stemTicks = stemTicks; }")
        # Do not substitute a blank default score when conversion fails.
        original=r"console.warn(exc);\n            return _data_score__WEBPACK_IMPORTED_MODULE_5__.SmoScore.getDefaultScore(_data_score__WEBPACK_IMPORTED_MODULE_5__.SmoScore.defaults, _data_measure__WEBPACK_IMPORTED_MODULE_6__.SmoMeasure.defaults);"
        if text.count(original)!=1: raise SystemExit('Pinned failed-import adapter no longer matches')
        text=text.replace(original, 'throw exc; /* Hymn PoC: surface failed import, never substitute an empty score. */')
    target.write_text(text,encoding='utf-8')
shutil.copy(ROOT/'Docs/Smoosic PoC.md',DEST/'Integration-notes.md')
# jQuery's distribution carries its copyright header and MIT licence reference.
(DEST/'jQuery-LICENSE.txt').write_text('''Copyright OpenJS Foundation and other contributors, https://openjsf.org/

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
''')
files=sorted(p for p in DEST.rglob('*') if p.is_file() and p.name!='SHA256SUMS')
(DEST/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(DEST))+'\n' for p in files))
print('Pinned Smoosic PoC assets ready; no fonts, samples or runtime network dependencies.')
