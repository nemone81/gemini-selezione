#!/usr/bin/env bash
# Toglie tutto: azioni rapide, script, prompt e chiave dal Portachiavi.
set -euo pipefail
SERVICE="gemini-selezione"
PREFIX="$HOME/Library/Application Support/gemini-selezione"

for W in "Traduci o correggi con Gemini.workflow" "Scegli un prompt Gemini.workflow"; do
  rm -rf "$HOME/Library/Services/$W" && echo "tolta: $W"
done

if [[ -d "$PREFIX" ]]; then
  echo "I tuoi prompt sono in $PREFIX/prompt.json"
  read -rp "Cancello anche quelli? [s/N] " r
  [[ "$r" == [sS] ]] && rm -rf "$PREFIX" && echo "tolto: $PREFIX"
fi

/usr/bin/security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 \
  && echo "tolta: chiave dal Portachiavi" || true

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
echo "Fatto. La voce nelle scorciatoie sparisce al prossimo riavvio."
