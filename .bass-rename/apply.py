from pathlib import Path


def replace(path, old, new):
    p = Path(path)
    text = p.read_text()
    assert text.count(old) == 1, f'{path}: expected exactly one match for {old!r}'
    p.write_text(text.replace(old, new))


replace('Sources/HymnCore/Models.swift', 'case .lower: return "Lower voice"', 'case .lower: return "Bass"')
replace('Sources/HymnCore/Models.swift', 'case .lower: return "L"', 'case .lower: return "B"')
replace('Sources/HymnCore/Models.swift', '"S · A · Lower" : "S · A · T · Lower"', '"S · A · B" : "S · A · T · B"')
replace('Sources/HymnCore/Models.swift', '    case soprano, alto, tenor, lower', '    // Keep the persisted identifier "lower" so existing projects, mixes and logs remain compatible.\n    // User-facing labels use Bass/B; this rename does not change any vocal range.\n    case soprano, alto, tenor, lower')
replace('Sources/HymnAIrranger/WorkspaceView.swift', '2 T  ·  1 lower', '2 T  ·  1 B')
replace('Sources/HymnAIrranger/Editors.swift', 'Your lower singer is not treated as a deep bass.', 'Your Bass singer is not treated as a deep bass.')
replace('Sources/HymnCore/AIClient.swift', 'Never substitute Lower voice for a missing Tenor.', 'The display name Bass maps to the stable JSON voice identifier lower; always use lower in targetVoices and edit voice fields for Bass requests, and Bass in user-facing summaries. Keep its supplied vocal range unchanged; the label does not imply a deep bass range. Never substitute Bass for a missing Tenor.')
replace('VERSION', '0.1.0-alpha.3', '0.1.0-alpha.4')

# Refresh current introductory documentation and shipped notation examples, not
# historical prompt logs, project revisions or older release documentation.
p = Path('README.md')
s = p.read_text()
s = s.replace('Soprano · Alto · Tenor · Lower voice', 'Soprano · Alto · Tenor · Bass')
s = s.replace('Soprano · Alto · Lower voice', 'Soprano · Alto · Bass')
p.write_text(s)
for path in ('Examples/A quiet song.mei', 'Examples/A quiet song.musicxml'):
    p = Path(path)
    s = p.read_text().replace('Lower voice', 'Bass')
    s = s.replace('label.abbr="L"', 'label.abbr="B"')
    s = s.replace('<part-abbreviation>L</part-abbreviation>', '<part-abbreviation>B</part-abbreviation>')
    p.write_text(s)

# Fail instead of silently leaving active UI labels behind.
for p in Path('Sources').rglob('*.swift'):
    s = p.read_text()
    assert 'Lower voice' not in s, f'Old display name remains: {p}'
    assert 'S · A · Lower' not in s, f'Old voicing label remains: {p}'
print('Renamed display labels only; persisted lower identifiers and range values are unchanged.')
