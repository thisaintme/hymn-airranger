'use strict';
(() => {
  let toolkit, events = [], active = [], activeLyrics = [], page = null;
  function ready() {
    toolkit = new verovio.toolkit();
    window.Hymn = {
      render(payload) {
        try {
          events = payload.events; active = []; activeLyrics = []; page = null;
          toolkit.setOptions({pageWidth:2100,pageHeight:2970,pageMarginTop:120,pageMarginBottom:140,pageMarginLeft:130,pageMarginRight:110,scale:40,adjustPageHeight:false,breaks:'auto',spacingStaff:12,spacingSystem:14,lyricSize:5,header:'auto',footer:'none',svgViewBox:true});
          // MEI 5 uses child labels and keysig, not the legacy staff label/key.sig attributes.
          // Normalize our escaped musical payload before engraving so printed parts are identifiable.
          const documentXML = new DOMParser().parseFromString(payload.mei, 'application/xml');
          if (documentXML.querySelector('parsererror')) throw new Error('The score contains invalid musical XML.');
          documentXML.querySelectorAll('staffDef').forEach(staff => {
            [['label', 'label'], ['label.abbr', 'labelAbbr']].forEach(([attribute, element]) => {
              if (!staff.hasAttribute(attribute)) return;
              const node = documentXML.createElementNS(staff.namespaceURI, element);
              node.textContent = staff.getAttribute(attribute);
              staff.append(node); staff.removeAttribute(attribute);
            });
          });
          documentXML.querySelectorAll('[key\\.sig]').forEach(definition => {
            definition.setAttribute('keysig', definition.getAttribute('key.sig'));
            definition.removeAttribute('key.sig');
          });
          if (!toolkit.loadData(new XMLSerializer().serializeToString(documentXML))) throw new Error('The engraving engine rejected the score.');
          const host = document.getElementById('pages'); host.replaceChildren();
          const total = toolkit.getPageCount();
          for (let i = 1; i <= total; ++i) {
            const sheet = document.createElement('section'); sheet.className = 'paper';
            sheet.innerHTML = toolkit.renderToSVG(i); // Only our structured, XML-escaped score is passed to Verovio.
            const stamp = document.createElement('div'); stamp.className = 'stamp';
            const left = document.createElement('span'); left.textContent = payload.stamp || 'Hymn AIrranger · working draft';
            const right = document.createElement('span'); right.textContent = `${i} / ${total}`;
            stamp.append(left,right); sheet.append(stamp); host.append(sheet);
          }
          document.getElementById('loading').hidden = true;
          post({kind:'rendered',pages:total,renderID:payload.renderID});
        } catch (e) { post({kind:'error',message:String(e.message || e)}); }
      },
      highlight(tick) {
        active.forEach(id => document.getElementById(id)?.classList.remove('playing'));
        activeLyrics.forEach(node => node.classList.remove('playing-lyric'));
        const sounding = events.filter(e => e.pitch != null && tick >= e.tick && tick < e.tick+e.ticks);
        active = sounding.map(e => e.id);
        const owners = [...new Set(sounding.map(e => e.lyricOwnerID).filter(Boolean))];
        activeLyrics = owners.flatMap(id => [...(document.getElementById(id)?.querySelectorAll('.syl') || [])]);
        activeLyrics.forEach(node => node.classList.add('playing-lyric'));
        active.forEach(id => document.getElementById(id)?.classList.add('playing'));
        const next = active.length ? document.getElementById(active[0])?.closest('.paper') : null;
        if (next && next !== page) { page = next; next.scrollIntoView({behavior:'smooth',block:'start'}); }
      },
      printRects() {
        document.body.classList.add('printing');
        return [...document.querySelectorAll('.paper')].map(p => { const r=p.getBoundingClientRect(); return {x:r.left+window.scrollX,y:r.top+window.scrollY,width:r.width,height:r.height}; });
      },
      endPrint() { document.body.classList.remove('printing'); }
    };
    document.addEventListener('click', e => { const element = e.target.closest('.note'); if (element) post({kind:'note',id:element.id}); });
    post({kind:'ready'});
  }
  if (typeof verovio === 'undefined') { post({kind:'error',message:'Verovio is missing. Run Build App.command and rebuild.'}); }
  else if (verovio.module.calledRun) ready();
  else verovio.module.onRuntimeInitialized = ready;
})();
