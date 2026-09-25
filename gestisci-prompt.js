// Gestione dei prompt con i dialoghi nativi di macOS: nessuna app da installare,
// nessuna finestra da disegnare, nessun permesso da chiedere.
//
//   osascript -l JavaScript gestisci-prompt.js <percorso-prompt.json>
//
// Scrive il file solo a modifica conclusa, e sempre dopo aver messo da parte una copia:
// chi perde i suoi prompt per un clic sbagliato non li riscrive, smette di usare la cosa.

ObjC.import('Foundation');

const app = Application.currentApplication();
app.includeStandardAdditions = true;

const DESTINAZIONI = [
  ['sostituisci', 'Sostituisci il testo selezionato'],
  ['finestra',    'Apri la risposta in una finestra'],
  ['appunti',     'Metti la risposta negli appunti'],
];

function leggi(f) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(f, $.NSUTF8StringEncoding, null);
  return s.js;
}

function scrivi(f, testo) {
  return $.NSString.alloc.initWithUTF8String(testo)
    .writeToFileAtomicallyEncodingError(f, true, $.NSUTF8StringEncoding, null);
}

function salva(file, prompt) {
  // copia di sicurezza prima di ogni scrittura
  const attuale = leggi(file);
  if (attuale) scrivi(file + '.backup', attuale);
  scrivi(file, JSON.stringify(prompt, null, 2) + '\n');
}

function avviso(testo, titolo) {
  app.displayDialog(testo, {
    withTitle: titolo || 'Prompt di Gemini',
    buttons: ['OK'], defaultButton: 'OK',
  });
}

function chiedi(testo, predefinito) {
  try {
    const r = app.displayDialog(testo, {
      withTitle: 'Prompt di Gemini',
      defaultAnswer: predefinito || '',
      buttons: ['Annulla', 'OK'], defaultButton: 'OK', cancelButton: 'Annulla',
    });
    return r.textReturned;
  } catch (e) { return null; }          // Annulla
}

function scegli(voci, domanda, okName) {
  const r = app.chooseFromList(voci, {
    withPrompt: domanda,
    defaultItems: [voci[0]],
    okButtonName: okName || 'Scegli',
    cancelButtonName: 'Chiudi',
  });
  return r === false ? null : r[0];
}

function conferma(testo) {
  try {
    app.displayDialog(testo, {
      withTitle: 'Prompt di Gemini',
      buttons: ['Annulla', 'Elimina'], defaultButton: 'Annulla', cancelButton: 'Annulla',
    });
    return true;
  } catch (e) { return false; }
}

/** Un id stabile ricavato dal nome, senza collisioni. */
function idDa(nome, presi) {
  let base = nome.toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'prompt';
  let id = base, n = 2;
  while (presi.indexOf(id) >= 0) id = base + '-' + (n++);
  return id;
}

function etichettaDestinazione(v) {
  const d = DESTINAZIONI.find(x => x[0] === v);
  return d ? d[1] : v;
}

function scegliDestinazione(attuale) {
  const voci = DESTINAZIONI.map(d => d[1]);
  const s = scegli(voci, 'Dove deve finire la risposta?' +
    (attuale ? '\n(ora: ' + etichettaDestinazione(attuale) + ')' : ''), 'Usa questa');
  if (s === null) return null;
  return DESTINAZIONI[voci.indexOf(s)][0];
}

/** Le istruzioni sono più lunghe di una riga: si scrivono in TextEdit e si rilegge il file. */
function istruzioniInTextEdit(testoIniziale, nome) {
  const dir = $.NSTemporaryDirectory().js + 'gemini-prompt-' + Date.now();
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
  const f = dir + '/istruzioni-' + (nome || 'prompt').replace(/[^\w-]/g, '_') + '.txt';
  scrivi(f, testoIniziale || '');
  app.doShellScript('open -e ' + JSON.stringify(f));
  avviso('Ho aperto le istruzioni in TextEdit.\n\n' +
         'Scrivile, SALVA con ⌘S, poi torna qui e premi OK.', 'Scrivi le istruzioni');
  const t = leggi(f);
  return (t || '').replace(/\s+$/, '');
}

function nuovo(prompt, file) {
  const nome = chiedi('Come si chiama questo prompt?\n(è il nome che vedrai nell\'elenco)', '');
  if (nome === null || !nome.trim()) return;

  const istruzioni = istruzioniInTextEdit(
    'Scrivi qui cosa deve fare il modello con il testo selezionato.\n' +
    'Esempio: "Riscrivi il testo in modo più breve e diretto, mantenendo il significato. ' +
    'Restituisci SOLO il testo risultante."\n\n' +
    '(cancella queste righe e scrivi le tue)', nome);
  if (!istruzioni.trim()) { avviso('Nessuna istruzione scritta: non ho creato niente.'); return; }

  const dest = scegliDestinazione('sostituisci');
  if (dest === null) return;

  prompt.push({
    id: idDa(nome, prompt.map(p => p.id)),
    nome: nome.trim(),
    output: dest,
    system: istruzioni.split('\n'),
  });
  salva(file, prompt);
  avviso('Creato: ' + nome.trim() + '\n\nLo trovi nell\'elenco premendo ⌃⌥⌘P.');
}

function modifica(prompt, file, i) {
  const p = prompt[i];
  while (true) {
    const voci = [
      'Cambia il nome  (' + p.nome + ')',
      'Cambia le istruzioni',
      'Cambia dove finisce la risposta  (' + etichettaDestinazione(p.output) + ')',
      'Duplica',
      'Elimina',
      '← Indietro',
    ];
    const s = scegli(voci, 'Prompt: ' + p.nome, 'Apri');
    if (s === null || s === voci[5]) return;

    if (s === voci[0]) {
      const n = chiedi('Nuovo nome:', p.nome);
      if (n && n.trim()) { p.nome = n.trim(); salva(file, prompt); }

    } else if (s === voci[1]) {
      const t = istruzioniInTextEdit([].concat(p.system).join('\n'), p.nome);
      if (t.trim()) { p.system = t.split('\n'); salva(file, prompt); }

    } else if (s === voci[2]) {
      const d = scegliDestinazione(p.output);
      if (d) { p.output = d; salva(file, prompt); }

    } else if (s === voci[3]) {
      const copia = JSON.parse(JSON.stringify(p));
      copia.nome = p.nome + ' (copia)';
      copia.id = idDa(copia.nome, prompt.map(x => x.id));
      prompt.splice(i + 1, 0, copia);
      salva(file, prompt);
      avviso('Duplicato: ' + copia.nome);
      return;

    } else if (s === voci[4]) {
      if (conferma('Elimino «' + p.nome + '»?\n\nUna copia del file resta in prompt.json.backup.')) {
        prompt.splice(i, 1);
        salva(file, prompt);
        avviso('Eliminato.');
        return;
      }
    }
  }
}

function run(argv) {
  const file = argv[0];
  let prompt;
  try {
    prompt = JSON.parse(leggi(file));
    if (!Array.isArray(prompt)) throw new Error();
  } catch (e) {
    avviso('Non riesco a leggere i prompt.\n\nIl file ha un errore di sintassi:\n' + file +
           '\n\nSe hai un prompt.json.backup accanto, puoi recuperarlo da lì.', 'Errore');
    return '';
  }

  app.activate();
  while (true) {
    const voci = prompt.map(p => p.nome).concat(['➕  Nuovo prompt…']);
    const s = scegli(voci, 'Gestione dei prompt', 'Apri');
    if (s === null) return '';
    if (s === voci[voci.length - 1]) nuovo(prompt, file);
    else modifica(prompt, file, voci.indexOf(s));
  }
}
