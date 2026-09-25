#!/bin/zsh
# Applica al testo selezionato uno dei prompt configurati, via Gemini.
# Riceve il testo su stdin (dall'azione rapida di macOS) e stampa su stdout ciò che
# deve sostituire la selezione.
#
#   gemini-selezione.sh --prompt <id>   applica quel prompt, senza chiedere
#   gemini-selezione.sh                 mostra l'elenco e fa scegliere
#
# Regola d'oro: in caso di QUALSIASI errore stampa il testo originale, così la selezione
# resta com'era invece di sparire, e mostra una notifica col motivo.
#
# I prompt stanno in prompt.json, accanto a questo script: si aggiungono lì, senza
# toccare Automator né le impostazioni di sistema.
#
# La chiave sta nel Portachiavi (servizio gemini-selezione), la mette install.sh.
# Uso manuale:  echo "ciao a tutti" | ./gemini-selezione.sh --prompt traduci-correggi

setopt pipefail
SERVICE="gemini-selezione"
BASE="${0:A:h}"
PROMPTS="${GEMINI_SELEZIONE_PROMPTS:-$BASE/prompt.json}"
MODEL_DEFAULT="${GEMINI_SELEZIONE_MODEL:-gemini-flash-lite-latest}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/in.txt"

fallisci() {
  cat "$TMP/in.txt"
  /usr/bin/osascript -e "display notification \"$1\" with title \"Gemini: selezione non modificata\"" >/dev/null 2>&1
  exit 0
}

[[ -s "$TMP/in.txt" ]] || exit 0
[[ -f "$PROMPTS" ]] || fallisci "Manca prompt.json: rilancia install.sh"

# --- gli script JXA su file: annidarli nei heredoc dentro $(...) è un campo minato ---

cat > "$TMP/scegli.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const testo = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  const prompt = JSON.parse(testo);
  // l'ultima voce apre il file dei prompt: è qui che uno si trova quando pensa
  // "mi servirebbe un altro prompt", non nel README
  const MODIFICA = '\u2699\uFE0E  Modifica i prompt…';
  const nomi = prompt.map(p => p.nome).concat([MODIFICA]);
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  app.activate();
  const scelta = app.chooseFromList(nomi, {
    withPrompt: 'Cosa faccio con il testo selezionato?',
    defaultItems: [nomi[0]],
    okButtonName: 'Applica',
  });
  if (scelta === false) return '';                      // annullato
  if (scelta[0] === MODIFICA) return '\u0000modifica';
  return prompt[nomi.indexOf(scelta[0])].id;
}
JS

cat > "$TMP/prepara.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const file = argv[0], id = argv[1], dir = argv[2];
  const read = f => $.NSString.stringWithContentsOfFileEncodingError(f, $.NSUTF8StringEncoding, null).js;
  const p = JSON.parse(read(file)).find(x => x.id === id);
  if (!p) throw new Error('non trovato');
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: [].concat(p.system).join('\n') }] },
    contents: [{ role: 'user', parts: [{ text: read(dir + '/in.txt') }] }],
    generationConfig: { thinkingConfig: { thinkingLevel: p.thinking || 'low' } }
  });
  $.NSString.alloc.initWithUTF8String(body)
    .writeToFileAtomicallyEncodingError(dir + '/body.json', true, $.NSUTF8StringEncoding, null);
  // una destinazione sconosciuta degrada a "finestra": non si sovrascrive mai una
  // selezione per colpa di un refuso nel file dei prompt
  const dest = ['sostituisci', 'finestra', 'appunti'].indexOf(p.output) >= 0 ? p.output : 'finestra';
  return [dest, p.modello || ''].join('\t');
}
JS

cat > "$TMP/leggi.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const dir = argv[0], http = argv[1], dest = argv[2];
  const read = f => $.NSString.stringWithContentsOfFileEncodingError(dir + '/' + f, $.NSUTF8StringEncoding, null).js;
  let r;
  try { r = JSON.parse(read('out.json')); } catch (e) { throw new Error('HTTP ' + http + ': risposta non valida'); }
  if (r.error) throw new Error('HTTP ' + http + ': ' + r.error.message);
  const parts = (((r.candidates || [])[0] || {}).content || {}).parts || [];
  let out = parts.filter(p => !p.thought && p.text).map(p => p.text).join('');
  if (!out.trim()) throw new Error('Risposta vuota da Gemini');
  if (dest === 'sostituisci') {
    // Ripristina gli spazi/a capo di coda della selezione originale, che il modello toglie.
    const tail = read('in.txt').match(/\s*$/)[0];
    out = out.replace(/\s+$/, '') + tail;
  }
  $.NSString.alloc.initWithUTF8String(out)
    .writeToFileAtomicallyEncodingError(dir + '/res.txt', true, $.NSUTF8StringEncoding, null);
  return '';
}
JS

# --- quale prompt ---
ID=""
[[ "$1" == "--prompt" && -n "$2" ]] && ID="$2"

# Senza un id si chiede. `choose from list` è il dialogo nativo di macOS: nessuna
# interfaccia da scrivere, e se l'utente annulla la selezione resta intatta.
if [[ -z "$ID" ]]; then
  ID="$(/usr/bin/osascript -l JavaScript "$TMP/scegli.js" "$PROMPTS" 2>"$TMP/err.txt")" \
    || fallisci "prompt.json non è leggibile: controlla la sintassi in $PROMPTS"
  [[ -n "$ID" ]] || { cat "$TMP/in.txt"; exit 0; }   # annullato: selezione intatta
  if [[ "$ID" == $'\0modifica' ]]; then
    /usr/bin/open "$PROMPTS" 2>/dev/null || /usr/bin/open -e "$PROMPTS"
    cat "$TMP/in.txt"                                 # selezione intatta
    exit 0
  fi
fi

# --- prepara la richiesta, e scopri dove va la risposta ---
META="$(/usr/bin/osascript -l JavaScript "$TMP/prepara.js" "$PROMPTS" "$ID" "$TMP" 2>"$TMP/err.txt")" \
  || fallisci "Prompt '$ID' non trovato in prompt.json"
DEST="${META%%	*}"
MODEL="${META##*	}"
[[ -n "$MODEL" ]] || MODEL="$MODEL_DEFAULT"

KEY="$(/usr/bin/security find-generic-password -s "$SERVICE" -w 2>/dev/null)" \
  || fallisci "Chiave non trovata nel Portachiavi: rilancia install.sh"

# curl usa il portachiavi di sistema: funziona anche dietro proxy con ispezione TLS.
# La chiave passa via header da stdin (-H @-), mai come argomento visibile in ps.
HTTP=$(printf 'x-goog-api-key: %s\n' "$KEY" | /usr/bin/curl -sS --max-time 60 \
  -H @- -H 'Content-Type: application/json' --data-binary "@$TMP/body.json" \
  -o "$TMP/out.json" -w '%{http_code}' \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" 2>"$TMP/err.txt") \
  || fallisci "Rete: $(head -c 120 "$TMP/err.txt")"

/usr/bin/osascript -l JavaScript "$TMP/leggi.js" "$TMP" "$HTTP" "$DEST" >/dev/null 2>"$TMP/err.txt" \
  || fallisci "$(sed -E 's/^.*Error: //' "$TMP/err.txt" | head -c 150 | tr -d '"\\')"

# --- dove finisce la risposta ---
# È la decisione che rende usabili prompt diversi fra loro: "traduci" vuole la
# sostituzione sul posto, "scrivi un'email" vuole una finestra da rileggere.
case "$DEST" in
  sostituisci)
    # l'originale finisce negli appunti: una sostituzione sbagliata resta recuperabile
    /usr/bin/pbcopy < "$TMP/in.txt"
    cat "$TMP/res.txt"
    ;;
  appunti)
    /usr/bin/pbcopy < "$TMP/res.txt"
    /usr/bin/osascript -e 'display notification "Risposta negli appunti" with title "Gemini"' >/dev/null 2>&1
    cat "$TMP/in.txt"
    ;;
  finestra)
    F="$(mktemp -t gemini).txt"
    cp "$TMP/res.txt" "$F"
    /usr/bin/open -e "$F"
    cat "$TMP/in.txt"
    ;;
esac
