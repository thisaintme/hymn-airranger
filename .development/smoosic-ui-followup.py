from pathlib import Path
root=Path('.')
p=root/'Sources/HymnAIrranger/Resources/Editor/editor.js'
s=p.read_text()
s=s.replace("async function load(kind, content, session) {\n    E.changing", "async function load(kind, content, session) {\n    await commandQueue;\n    E.changing")
s=s.replace("async function settled() { await view().renderer.renderPromise();", "async function settled() { await commandQueue; await view().renderer.renderPromise();")
s=s.replace("  async function run(command, arg) {\n", "  let commandQueue = Promise.resolve();\n  function run(command, arg) {\n    const next = commandQueue.then(() => execute(command, arg));\n    commandQueue = next.catch(() => {});\n    return next;\n  }\n  async function execute(command, arg) {\n")
p.write_text(s)
p=root/'Sources/HymnAIrranger/SmoosicEditor.swift'
s=p.read_text().replace('evaluate("return window.Editor.snapshot();")', 'evaluate("await window.Editor.settled(); return window.Editor.snapshot();")')
p.write_text(s)
p=root/'Sources/HymnAIrranger/Resources/Editor/editor.css'
s=p.read_text()
if '#smoo-top-bar{flex:0 0 44px' not in s:
 s+='''\n/* Bootstrap's flex-md-fill otherwise gives the ribbon half the window height. */
#smoo-top-bar{flex:0 0 44px!important;max-height:44px!important;min-height:44px;align-items:center;flex-wrap:nowrap;margin:0!important}
#media{flex:1 1 0!important;min-height:0;overflow:hidden}
#controls-left{height:100%!important;max-height:100%;overflow-y:auto}
'''
p.write_text(s)
