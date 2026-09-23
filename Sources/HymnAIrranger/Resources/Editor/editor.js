/* Hymn AIrranger Smoosic PoC adapter. Local-only, pinned engine; never edits a .hymn Project. */
'use strict';
(() => {
  const E = { app: null, session: '', lastSnapshot: '', changing: false, source: '', importFindings: [], ready: false };
  const post = (kind, extra = {}) => window.webkit?.messageHandlers?.editor?.postMessage({ kind, session: E.session, ...extra });
  const status = (text) => { document.getElementById('editor-status').textContent = text; };
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const safeJSON = (text) => {
    if (typeof text !== 'string' || text.length > 12000000) throw Error('Editor data is too large.');
    const object = JSON.parse(text); let budget = 250000;
    const visit = (value, depth=0) => {
      if (--budget < 0 || depth > 60) throw Error('Editor data is too complex.');
      if (value && typeof value === 'object') for (const [key, child] of Object.entries(value)) {
        if (['__proto__','prototype','constructor'].includes(key)) throw Error('Unsafe editor field.');
        if (key === 'ctor' && (typeof child !== 'string' || !/^Smo[A-Za-z0-9_]{1,80}$/.test(child) || (typeof Smo[child] !== 'function' && !['SmoLayoutManager','SmoPageLayout','SmoPartInfo','SmoTupletTree','SmoTuplet','SmoScoreText'].includes(child)))) throw Error('Unknown editor object type: '+child);
        visit(child, depth+1);
      }
    }; visit(object);
    if (!Array.isArray(object.staves) || !object.staves.length || object.staves.length > 16 || object.dictionary) throw Error('Unsupported editor document.');
    return object;
  };
  const parseXML = (text) => {
    if (typeof text !== 'string' || text.length > 5000000 || /<!DOCTYPE|<!ENTITY/i.test(text)) throw Error('Use uncompressed MusicXML under 5 MB, without DTD/entity declarations.');
    const doc = new DOMParser().parseFromString(text, 'application/xml');
    if (doc.querySelector('parsererror') || doc.documentElement.localName !== 'score-partwise') throw Error('The file is not valid score-partwise MusicXML.');
    if (doc.querySelectorAll('note').length > 8000 || doc.querySelectorAll('part').length > 16 || doc.querySelectorAll('measure').length > 2400) throw Error('This score exceeds the prototype limits.');
    return doc;
  };
  function view() { if (!E.app?.view) throw Error('Wait for the editor to load.'); return E.app.view; }
  function nativeJSON() { return JSON.stringify(view().storeScore.serialize({skipStaves:false, useDictionary:false, preserveStaffIds:true})); }
  function exportedXML() { return new XMLSerializer().serializeToString(Smo.SmoToXml.convert(view().storeScore)); }
  // Diagnostic comparison, not a promise of full MusicXML fidelity. Note events are
  // compared per printed part/measure; no score is changed to make a check pass.
  function summary(doc) {
    return [...doc.querySelectorAll('score-partwise > part')].map(part => {
      let divisions=null;
      return [...part.children].filter(x=>x.localName==='measure').map(measure => {
        const div = measure.querySelector('attributes > divisions'); if (div) divisions = Number(div.textContent);
        return [...measure.children].filter(x=>x.localName==='note').map(n=>({
          pitch:n.querySelector('rest') ? 'rest' : [n.querySelector('pitch > step')?.textContent||'',n.querySelector('pitch > alter')?.textContent||'0',n.querySelector('pitch > octave')?.textContent||''].join(':'),
          beats:divisions ? Number(n.querySelector('duration')?.textContent || 0) / divisions : null,
          type:n.querySelector('type')?.textContent || '', dots:n.querySelectorAll(':scope > dot').length,
          ratio:[n.querySelector('actual-notes')?.textContent || '1',n.querySelector('normal-notes')?.textContent || '1'].join(':'),
          ties:[...n.querySelectorAll(':scope > tie')].map(t=>t.getAttribute('type')).sort().join(','),
          lyrics:[...n.querySelectorAll(':scope > lyric')].map(l=>[l.getAttribute('number')||'1', l.querySelector('text')?.textContent||'',l.querySelector('syllabic')?.textContent||'single'])
        }));
      });
    });
  }
  function compareXML(a, b) {
    const x=summary(a), y=summary(b), issues=[];
    if (x.length!==y.length) issues.push(`Printed part count changed: ${x.length} → ${y.length}.`);
    for(let p=0;p<Math.min(x.length,y.length);p++) {
      if(x[p].length!==y[p].length) issues.push(`Part ${p+1}: measure count changed.`);
      for(let m=0;m<Math.min(x[p].length,y[p].length);m++) {
        if(x[p][m].length!==y[p][m].length) issues.push(`Part ${p+1}, bar ${m+1}: note/rest count changed (${x[p][m].length} → ${y[p][m].length}).`);
        for(let n=0;n<Math.min(x[p][m].length,y[p][m].length);n++) {
          const aa=x[p][m][n],bb=y[p][m][n];
          for(const k of ['pitch','type','dots','ratio','ties','lyrics']) if(JSON.stringify(aa[k])!==JSON.stringify(bb[k])) issues.push(`Part ${p+1}, bar ${m+1}, event ${n+1}: ${k} differs.`);
          if(aa.beats!==null && bb.beats!==null && Math.abs(aa.beats-bb.beats)>1e-8) issues.push(`Part ${p+1}, bar ${m+1}, event ${n+1}: performed duration differs.`);
          if(issues.length>=100) return issues.concat('Report limited to the first 100 differences.');
        }
      }
    }
    [...b.querySelectorAll('score-partwise > part')].forEach((p,i)=>{if(!p.querySelector('measure > attributes > divisions')) issues.push(`Part ${i+1}: exported timing divisions are missing; duration fidelity cannot be established for this part.`);});
    const fractional = [...b.querySelectorAll('duration')].some(d=>!Number.isInteger(Number(d.textContent)));
    if(fractional) issues.push('Smoosic exported fractional duration numbers. The current Hymn MusicXML importer requires exact integer durations: rehearsal transfer is not yet safe.');
    return issues;
  }
  function validateScore(score) {
    if (!score?.staves?.length || score.staves.length>16) throw Error('Smoosic did not produce a score.');
    let notes=0;
    for(const staff of score.staves) for(const m of staff.measures) for(const v of m.voices) for(const n of v.notes) {
      if (++notes>8000 || !Number.isFinite(n.tickCount) || n.tickCount<=0 || !Number.isFinite(n.stemTicks) || n.stemTicks<=0) throw Error('The imported editor score has invalid durations.');
    }
    return score;
  }
  function decorate() {
    // Text labels replace upstream font-only icons; no external font files required.
    for(const b of document.querySelectorAll('#controls-top button')) {
      const def=Smo.SmoConfiguration.defaults.buttonDefinition.find(x=>x.id===b.id);
      if(def && !b.textContent.trim()) b.textContent = def.leftText || def.rightText || b.id;
      b.setAttribute('aria-label',b.textContent.trim() || b.id);
    }
    const sel=view().tracker.selections[0];
    document.getElementById('selection-info').textContent=sel ? `Part ${sel.selector.staff+1} · Bar ${sel.selector.measure+1} · Note ${sel.selector.tick+1}` : 'Click a note in the score';
  }
  async function install(score) {
    if (E.app) { await view().changeScore(score); return; }
    Smo.SuiApplication.initSync(); await Smo.SuiApplication.registerFonts();
    const defaults=Smo.SmoConfiguration.defaults, layout=clone(defaults.ribbonLayout);
    layout.left=layout.left.filter(x=>!['fileMenu','libraryMenu','languageMenu','helpDialog'].includes(x));
    layout.top=layout.top.filter(x=>!['playButton2','stopButton2','refresh','zoomout','zoomin'].includes(x));
    // Use the pinned application's UI without its sample-download startup path.
    // All note audition in this PoC uses a local oscillator below.
    const app=new Smo.SuiApplication(new Smo.SmoConfiguration({mode:'application',domContainer:'smoo',initialScore:score,libraryUrl:'',ribbonLayout:layout}));
    E.app=app; await app.createScore(); app.createUiDom();
    app.navigation.showSplash.value=false;
    await new Promise(r=>setTimeout(r,40)); app.createUi();
    app.view.score.preferences.autoPlay=false; app.view.storeScore.preferences.autoPlay=false;
    await app.view.renderer.renderPromise();
  }
  async function load(kind, content, session) {
    await commandQueue;
    E.changing=true; E.ready=false; status('Loading a separate editing copy…');
    const previous=E.app ? nativeJSON() : null;
    try {
      Smo.SuiApplication.initSync(); await Smo.SuiApplication.registerFonts();
      let score;
      if(kind==='xml') score=validateScore(Smo.XmlToSmo.convert(parseXML(content)));
      else { const obj=safeJSON(content); score=validateScore(Smo.SmoScore.deserialize(JSON.stringify(obj))); }
      await install(score); await view().updateZoom(1.3); E.session=session;
      E.source=kind==='xml' ? content : '';
      E.importFindings=kind==='xml' ? compareXML(parseXML(content),parseXML(exportedXML())) : [];
      E.lastSnapshot=nativeJSON(); E.ready=true; decorate();
      status('Local editor · Your rehearsal project is unchanged. Save an editor copy to keep all notation.');
      return {scoreJSON:E.lastSnapshot, findings:E.importFindings};
    } catch(e) {
      if(previous && E.app) { try { await view().changeScore(Smo.SmoScore.deserialize(previous)); E.ready=true; }catch(_){} }
      status('Editor load failed: '+String(e)); throw e;
    } finally { E.changing=false; }
  }
  async function settled() { await commandQueue; await view().renderer.renderPromise(); await new Promise(r=>setTimeout(r,300)); return document.querySelectorAll('.vf-stavenote').length; }
  function snapshot() { validateScore(view().storeScore); return nativeJSON(); }
  let commandQueue = Promise.resolve();
  function run(command, arg) {
    const next = commandQueue.then(() => execute(command, arg));
    commandQueue = next.catch(() => {});
    return next;
  }
  async function execute(command, arg) {
    if(!E.ready || E.changing) throw Error('Wait for the editor to finish.');
    E.changing=true;
    try {
      const v=view();
      switch(command) {
      case 'zoomIn': await v.updateZoom(Math.min(3,v.score.layoutManager.globalLayout.zoomScale*1.2)); break;
      case 'zoomOut': await v.updateZoom(Math.max(.5,v.score.layoutManager.globalLayout.zoomScale/1.2)); break;
      case 'up': await v.transposeSelections(1); break;
      case 'down': await v.transposeSelections(-1); break;
      case 'shorter': await v.batchDurationOperation('halveDuration'); break;
      case 'longer': await v.batchDurationOperation('doubleDuration'); break;
      case 'dot': await v.batchDurationOperation('dotDuration'); break;
      case 'rest': await v.makeRest(); break;
      case 'undo': await v.undo(); break;
      case 'pitch': if(!/^[a-g]$/.test(arg)) throw Error('Choose A–G.'); await v.setPitch(arg); break;
      case 'lyric': {
        const sel=v.tracker.selections[0]; if(!sel?.note || sel.note.isRest()) throw Error('Select a sounding note for the syllable.');
        if(!arg || !Number.isInteger(arg.verse) || arg.verse<1 || arg.verse>8 || typeof arg.text!=='string' || arg.text.length>100) throw Error('Use verse 1–8 and one short syllable.');
        await v.addOrUpdateLyric(sel.selector,new Smo.SmoLyric({...Smo.SmoLyric.defaults,verse:arg.verse-1,text:arg.text})); break;
      }
      case 'select': {
        if(!Array.isArray(arg) || arg.length!==3 || arg.some(x=>!Number.isInteger(x)||x<0)) throw Error('Invalid selection.');
        v.tracker._replaceSelection({staff:arg[0],measure:arg[1],voice:0,tick:arg[2],pitches:[]},true); break;
      }
      default: throw Error('Unknown editor action.');
      }
      return snapshot();
    } finally { E.changing=false; emit(); }
  }
  function emit() {
    if(!E.ready || E.changing) return;
    try { decorate(); const json=nativeJSON(); if(json!==E.lastSnapshot) { E.lastSnapshot=json; post('changed',{scoreJSON:json}); } }
    catch(e) { post('failure',{message:String(e).slice(0,2000)}); }
  }
  function audition() {
    const n=view().tracker.selections[0]?.note; if(!n || n.isRest()) return;
    const pitch=n.pitches[0], midi=Smo.SmoMusic.midiNumberAndDetuneFromPitch(pitch,0,null).midinumber;
    post('audition',{midi});
    if(!window.webkit?.messageHandlers?.editor) {
      const ctx=E.audio || (E.audio=new AudioContext());ctx.resume();
      const oscillator=ctx.createOscillator(), gain=ctx.createGain(); oscillator.type='triangle';oscillator.frequency.value=440*Math.pow(2,(midi-69)/12);
      oscillator.connect(gain);gain.connect(ctx.destination);gain.gain.setValueAtTime(.12,ctx.currentTime);gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+.35);oscillator.start();oscillator.stop(ctx.currentTime+.4);
    }
  }
  function diagnostics() {
    const xml=exportedXML(); const converted=validateScore(Smo.XmlToSmo.convert(parseXML(xml)));
    const again=new XMLSerializer().serializeToString(Smo.SmoToXml.convert(converted));
    return {scope:'PoC diagnostic only: event pitches, durations, written values, ratios, ties and lyrics. Not complete score fidelity.', engine:'Smoosic 1427042ef0d6b9d8684b140c8f2a489270e8cc9f', importFindings:E.importFindings, exportReimportFindings:compareXML(parseXML(xml),parseXML(again)), sourcePartCount:E.source?summary(parseXML(E.source)).length:null, editorPartCount:view().storeScore.staves.length};
  }
  window.Editor={loadXML:(xml,session)=>load('xml',xml,session),loadNative:async(json,session,source='',findings=[])=>{const result=await load('native',json,session);E.source=source;E.importFindings=findings;return result;},snapshot,exportXML:exportedXML,run,diagnostics,settled,
    inspect:()=>({ready:E.ready,notes:view().storeScore.staves.map(s=>s.measures.map(m=>m.voices.map(v=>v.notes.map(n=>({pitches:n.pitches,ticks:n.tickCount,stem:n.stemTicks,lyrics:n.getTrueLyrics().map(l=>({verse:l.verse,text:l.text})),type:n.noteType}))))),tuplets:document.querySelectorAll('.vf-tuplet').length,selection:view().tracker.selections[0]?.selector})};
  document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=> {
    if(button.dataset.action==='audition') { audition(); return; }
    run(button.dataset.action).catch(e=>status(String(e)));
  }));
  document.getElementById('set-lyric').addEventListener('click',()=>run('lyric',{verse:Number(document.getElementById('lyric-verse').value),text:document.getElementById('lyric-text').value}).catch(e=>status(String(e))));
  document.addEventListener('keydown',ev=>{
    if(['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)) return;
    if((ev.metaKey||ev.ctrlKey) && ev.key.toLowerCase()==='s') {ev.preventDefault();ev.stopImmediatePropagation();post('saveRequested');}
    else if((ev.metaKey||ev.ctrlKey) && ev.key.toLowerCase()==='z') {ev.preventDefault();ev.stopImmediatePropagation(); if(ev.shiftKey) status('Redo is not connected in this PoC. Save editor copies as checkpoints.'); else run('undo').catch(e=>status(String(e)));}
    else if([' ','p','P'].includes(ev.key)) {ev.preventDefault();ev.stopImmediatePropagation();audition();}
  },true);
  window.addEventListener('error',ev=>post('failure',{message:String(ev.message).slice(0,2000)}));
  window.addEventListener('unhandledrejection',ev=>post('failure',{message:String(ev.reason).slice(0,2000)}));
  setInterval(emit,1000);
  post('loaded');
})();
