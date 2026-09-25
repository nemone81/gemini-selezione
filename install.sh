#!/usr/bin/env bash
# Installa due azioni rapide di macOS sul testo selezionato:
#
#   ⌃⌥⌘T   "Traduci o correggi con Gemini"  → applica subito il prompt traduci-correggi
#   ⌃⌥⌘P   "Scegli un prompt Gemini"        → mostra l'elenco e fa scegliere
#
# I prompt stanno in prompt.json: se ne aggiungono lì, senza toccare Automator né le
# impostazioni di sistema. Un prompt nuovo compare nell'elenco al volo.
#
# Idempotente, senza sudo. La chiave Gemini finisce nel Portachiavi di login (servizio
# gemini-selezione), passata a `security` via stdin: non finisce in file, argomenti o repo.
# Uso:
#   ./install.sh                                                # chiede la chiave, o riusa quella già salvata
#   GEMINI_API_KEY=... ./install.sh                             # oppure dall'ambiente
#   GEMINI_OP_REF='op://<vault>/<item>/<campo>' ./install.sh    # oppure da 1Password

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="gemini-selezione"
PREFIX="$HOME/Library/Application Support/gemini-selezione"
SHORTCUT_T="${GEMINI_SELEZIONE_SHORTCUT:-@^~t}"        # @=⌘ ^=⌃ ~=⌥ $=⇧
SHORTCUT_P="${GEMINI_SELEZIONE_SHORTCUT_SCEGLI:-@^~p}"

# 1. Chiave nel Portachiavi.
#    Si prende da 1Password, dall'ambiente, o la si chiede. Mai da un file nel repo.
if [[ -z "${GEMINI_API_KEY:-}" && -n "${GEMINI_OP_REF:-}" ]]; then
  GEMINI_API_KEY="$(op read "$GEMINI_OP_REF")"
fi

if [[ -z "${GEMINI_API_KEY:-}" ]] && ! /usr/bin/security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo
  echo "Serve una chiave API di Google Gemini. Si crea gratis in un minuto:"
  echo "  https://aistudio.google.com/apikey"
  echo
  # -s: non si vede mentre la incolli, e non resta nella cronologia della shell
  read -rsp "Incolla qui la chiave (non verrà mostrata): " GEMINI_API_KEY
  echo
  [[ -n "$GEMINI_API_KEY" ]] || { echo "!! Nessuna chiave inserita" >&2; exit 1; }
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo "==> Salvo la chiave nel Portachiavi ($SERVICE)"
  printf 'add-generic-password -U -a %s -s %s -l "Gemini API (azioni rapide sul testo selezionato)" -w %s\n' \
    "$USER" "$SERVICE" "$GEMINI_API_KEY" | /usr/bin/security -i >/dev/null
else
  echo "==> Riuso la chiave già nel Portachiavi ($SERVICE)"
fi

# 2. Script e prompt in posizione stabile, indipendente dal repo.
echo "==> Installo script e prompt in: $PREFIX"
mkdir -p "$PREFIX"
install -m 755 "$HERE/gemini-selezione.sh" "$PREFIX/gemini-selezione.sh"
install -m 644 "$HERE/gestisci-prompt.js" "$PREFIX/gestisci-prompt.js"

# I prompt NON si sovrascrivono: chi ne ha aggiunti non deve perderli a ogni reinstallazione.
if [[ -f "$PREFIX/prompt.json" ]]; then
  echo "    prompt.json già presente: lasciato com'è (i tuoi prompt restano)"
  echo "    nuovi prompt di serie in: $HERE/prompt.json"
else
  install -m 644 "$HERE/prompt.json" "$PREFIX/prompt.json"
fi

# 3. Azioni rapide.
echo "==> Installo le azioni rapide in ~/Library/Services"
mkdir -p "$HOME/Library/Services"
for W in "Traduci o correggi con Gemini.workflow" "Scegli un prompt Gemini.workflow"; do
  rm -rf "$HOME/Library/Services/$W"
  cp -R "$HERE/$W" "$HOME/Library/Services/"
done

# 4. Scorciatoie (Impostazioni → Tastiera → Abbreviazioni → Servizi).
echo "==> Scorciatoie: $SHORTCUT_T (traduci) · $SHORTCUT_P (scegli)"
scorciatoia() {
  defaults write pbs NSServicesStatus -dict-add "\"(null) - $1 - runWorkflowAsService\"" \
    "{enabled_context_menu = 1; enabled_services_menu = 1; key_equivalent = \"$2\";}"
}
scorciatoia "Traduci o correggi con Gemini" "$SHORTCUT_T"
scorciatoia "Scegli un prompt Gemini" "$SHORTCUT_P"
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

# 5. Prova end-to-end: il prompt esplicito, che è quello che non deve mai rompersi.
out="$(printf 'ciao' | "$PREFIX/gemini-selezione.sh" --prompt traduci-correggi)"
if [[ "$out" != "ciao" ]]; then
  echo "OK  prova: 'ciao' → '$out'"
else
  echo "!! La prova ha restituito il testo originale." >&2
  echo "   Di solito è la chiave: rilancia ./install.sh e incollane una valida." >&2
  echo "   Altrimenti guarda rete, quota, o il Centro Notifiche per il messaggio esatto." >&2
  exit 1
fi

echo
echo "Pronto. Seleziona del testo in qualsiasi app e premi:"
echo "  ⌃⌥⌘T   traduci o correggi"
echo "  ⌃⌥⌘P   scegli un prompt"
echo
echo "Se una scorciatoia non risponde, aprila una volta dal menu contestuale"
echo "(tasto destro → Servizi): macOS a volte registra il tasto solo dopo il primo uso."
