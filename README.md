# gemini-selezione

Azioni rapide di macOS che applicano un prompt al **testo selezionato**, in qualsiasi app.

| Scorciatoia | Cosa fa |
| --- | --- |
| **⌃⌥⌘T** | traduce o corregge: italiano → inglese, inglese → corretto |
| **⌃⌥⌘P** | mostra l'elenco dei prompt e ti fa scegliere |

Si trovano anche nel menu contestuale: tasto destro → Servizi.

Niente app da tenere aperta, niente icona nella barra dei menu, e **nessun permesso di
Accessibilità**: sono Azioni Rapide di macOS, quindi è il sistema a passare la selezione.

## Installazione

```bash
git clone https://github.com/nemone81/gemini-selezione.git
cd gemini-selezione
./install.sh
```

L'installazione chiede la tua **chiave API di Google Gemini**, che si crea gratis in un minuto
su [aistudio.google.com/apikey](https://aistudio.google.com/apikey). Il piano gratuito basta
abbondantemente per questo uso.

La chiave finisce nel **Portachiavi** di login (servizio `gemini-selezione`), passata a
`security` via stdin: non finisce in un file, né fra gli argomenti di un comando, né nel repo.
Puoi anche passarla da fuori:

```bash
GEMINI_API_KEY=... ./install.sh
GEMINI_OP_REF='op://<vault>/<item>/<campo>' ./install.sh   # da 1Password
```

Per togliere tutto: `./disinstalla.sh`

## I prompt

Stanno in `~/Library/Application Support/gemini-selezione/prompt.json`. Per aggiungerne uno
scrivi lì: compare nell'elenco al volo, senza toccare Automator né le impostazioni di sistema.

```json
{
  "id": "formale",
  "nome": "Rendi formale (italiano)",
  "output": "sostituisci",
  "system": ["Riscrivi il testo alzando il registro...", "Restituisci SOLO il testo."]
}
```

| Campo | |
| --- | --- |
| `id` | nome interno, quello che passa `--prompt` |
| `nome` | come compare nell'elenco |
| `system` | le istruzioni: una stringa, o un elenco di righe |
| `output` | `sostituisci` · `finestra` · `appunti` |
| `modello` | facoltativo, per usare un modello diverso su quel prompt |
| `thinking` | facoltativo: `low` (default), `medium`, `high` |

**`output` è la decisione che conta**, più delle istruzioni. «Traduci» vuole la sostituzione sul
posto; «scrivi un'email da questi dati» vuole una finestra da rileggere e correggere. Una
modalità sola renderebbe fastidiosa metà dei prompt.

- `sostituisci` — il testo selezionato viene sostituito. **L'originale finisce negli appunti**,
  così una sostituzione sbagliata resta recuperabile con ⌘V anche dove l'annulla non funziona.
- `finestra` — la risposta si apre in TextEdit, la selezione resta intatta.
- `appunti` — la risposta va negli appunti con una notifica, la selezione resta intatta.

Un `output` scritto male degrada a `finestra`: un refuso nel file dei prompt non deve poter
sovrascrivere quello che avevi selezionato.

Di serie ce ne sono sette: traduci o correggi, traduci in italiano, rendi più scorrevole, rendi
formale, riassumi in punti, scrivi un'email con questi dati, spiega questo testo. Sono scritti
per l'italiano: se lavori in un'altra lingua, riscrivili, è un file di testo.

`install.sh` **non sovrascrive** un `prompt.json` già presente: i prompt che aggiungi
sopravvivono agli aggiornamenti.

## Come funziona

| Pezzo | Dove |
| --- | --- |
| `gemini-selezione.sh`, `prompt.json` | `~/Library/Application Support/gemini-selezione/` |
| le due Azioni Rapide | `~/Library/Services/` (Automator, "Esegui script shell", l'output sostituisce la selezione) |
| le scorciatoie | `defaults write pbs NSServicesStatus` |

- Il selettore è `choose from list`, il dialogo nativo di macOS: nessuna interfaccia da
  scrivere, nessuna finestra da disegnare.
- Modello: `gemini-flash-lite-latest`, ragionamento `low`. Circa un secondo. Flash pieno ci mette
  il doppio con qualità equivalente su questi compiti.
- **In caso di errore** (rete, chiave, quota, prompt inesistente) lo script restituisce il testo
  originale e mostra una notifica col motivo: la selezione non sparisce mai. Vale anche se
  annulli l'elenco.
- Il testo va al modello come messaggio utente e le istruzioni come system prompt: un testo che
  contiene «ignora le istruzioni precedenti» viene tradotto, non eseguito.

## Cosa esce dal tuo Mac

Il testo selezionato e il prompt scelto vanno all'API di Google Gemini con la tua chiave, e
nient'altro. Non c'è un server di mezzo: lo script parla direttamente con Google. Vale la pena
ricordarlo: **quello che selezioni viene mandato a Google**, quindi niente password, niente
chiavi, e occhio ai documenti riservati.

## Da riga di comando

```bash
S="$HOME/Library/Application Support/gemini-selezione/gemini-selezione.sh"
echo "ciao a tutti" | "$S" --prompt traduci-correggi
echo "testo lungo"  | "$S"                            # mostra l'elenco
```

## Scorciatoie diverse

```bash
GEMINI_SELEZIONE_SHORTCUT='@^~t' GEMINI_SELEZIONE_SHORTCUT_SCEGLI='@^~p' ./install.sh
```

`@`=⌘ `^`=⌃ `~`=⌥ `$`=⇧

Se una scorciatoia non risponde, usa una volta la voce dal menu contestuale: macOS a volte
registra il tasto solo dopo il primo utilizzo.

## Licenza

MIT.
