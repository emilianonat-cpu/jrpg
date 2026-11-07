# SLAYME: scheletro del prototipo

Scheletro giocabile della fetta verticale descritta in `bibbia/prototipo.md`: la giornata che si ripete, la bacheca, i tre lavori più quello lasciato a metà, gli Eroi sul sentiero, la battaglia vista dal lato del mob, la casa, la notte e la fiducia del mentore salvata come sua "memoria". Grafica e testi sono **segnaposto**.

Motore: **Godot 4.7** (renderer Compatibility). Apri la cartella con Godot e premi F5.

## L'idea: nulla è dato per scontato

Il codice non contiene **nomi, testi, numeri o immagini**. Contiene solo ruoli e id.

| Cosa vuoi cambiare | Dove |
|---|---|
| Nomi di personaggi, luoghi, oggetti, titolo del gioco | `data/names.json` (es. `"mentor": "Novecento"`) |
| Tutti i testi (dialoghi, bacheca, registro di battaglia, menu) | `data/text/en.json` |
| Ogni numero (HP, danni, MP, orari, noia, soglie di fiducia, velocità) | `data/rules.json` |
| Mappa del Prato e della casa | `data/maps/meadow.json`, `data/maps/home.json` |
| Dialoghi (chi parla, in che ordine, scelte) | `data/dialogue/*.json` |
| Lavori del giorno, oggetti, variazioni giornaliere, orario | `data/tasks.json`, `data/items.json`, `data/days.json`, `data/schedule.json` |
| Schemi degli Eroi, azioni, verbi di Slayme, terreni | `data/heroes.json`, `data/hero_actions.json`, `data/battle.json`, `data/terrain.json` |
| Tasti e gamepad | `data/controls.json` |
| Immagini, fondali, cornici dei menu, suoni | pacchetti in `art/packs/` |

Nei testi si scrive `{name:mentor}` e il nome arriva da `names.json`: se domani il mentore si chiama in un altro modo, si cambia una riga. Lo stesso vale per gli Eroi (`hero_sword`, `hero_mage`, `hero_thief`), per Slayme (`protagonist`) e per tutti gli altri.

## L'arte a pacchetti

Il gioco non disegna niente: ogni sprite, fondale, cornice e suono è un **id** risolto dal pacchetto attivo (`art.pack` in `rules.json`).

- `art/packs/placeholder/` contiene tutti gli id usati, con forme e colori semplici, e il suo `manifest.json`.
- Per sostituire un'immagine: stesso nome di file nel pacchetto segnaposto, oppure un **nuovo pacchetto** (es. `art/packs/mob_a_mano/`) con un `manifest.json` che elenca **solo** gli id che cambia. Tutto il resto arriva dal segnaposto.
- Voci del manifest: `file`, `frames` (striscia orizzontale), `fps`, `centered`, `offset`; per le cornici `margin` e `padding` (9-slice).
- Un id mancante appare magenta (`missing`) e l'avviso compare nel log.
- `tools/make_placeholders.py` rigenera il pacchetto segnaposto (serve Pillow). È uno strumento di produzione, non codice del gioco.
- Pacchetti anche fuori dal progetto, senza reimportare: `user://art_packs/<nome>/manifest.json`.

## Struttura

```
core/        sistemi di base (autoload): Hooks, Rules, Content, Art, Controls, Clock, GameState
gameplay/    logica pura, senza grafica: DayState (la giornata), BattleModel (la battaglia)
scenes/      schermate: title, meadow (Prato), battle, home, night, end, ui (dialoghi, HUD)
data/        tutti i contenuti e le regole
art/packs/   pacchetti di arte e suoni
tests/       test automatico
tools/       strumenti di produzione (ignorati da Godot)
```

Flusso: `title` → `meadow` (06:00-17:00 al lavoro, poi si torna a casa a piedi passando dal cartello; alle 18:00 si va a casa comunque)  → `home` → `night` (salva la memoria) → `meadow`... finché il mentore arriva al gradino 3 di fiducia e fa la sua domanda → `end`.

## Hook: ogni meccanica si può cambiare a runtime

Regola di progetto: ogni valore passa da `Hooks`, così lo Strumento (e lo sciopero) potranno cambiare le regole senza riscrivere le meccaniche.

```gdscript
Rules.set_override("battle.slime.max_hp", 1)                        # cambia una regola
Hooks.add_filter("rule:world.encounter_radius", func(v, ctx): return 0)  # incontri a zero
Hooks.add_filter("name", func(n, ctx): return "???" if ctx.id == "mentor" else n)
Hooks.on("day.started", func(ctx): print("giorno ", ctx.day))
```

Filtri disponibili: `rule:<chiave>`, `text`, `name`, `table:<file>`, `art.id`, `clock.advance`, `trust.gain`, `day.variation`, `memory.write`, `memory.read`, `dialogue.line`, `screen.next`, `meadow.interact`, `battle.damage`, `battle.flee`, `battle.target`, `battle.condition`, `battle.boredom`.
Eventi: `game.new`, `day.started`, `day.ended`, `task.completed`, `trust.changed`, `heroes.appeared`, `slime.incident`, `pot.broken`, `colleague.incident`, `meadow.go_home`, `meadow.ready`, `home.ready`, `screen.entered`, `rules.changed`, `art.pack_changed`, `battle.created` (per aggiungere verbi nuovi a `verb_handlers`), `battle.planned`, `battle.round_end`, `schedule.<evento>` (per eventi nuovi in `schedule.json`), `prototype.end`.

In più `user://rules_override.json` (stessa forma di `rules.json`) cambia le regole senza toccare il progetto.

## Due modi di vedere il Prato

`world.mode` in `rules.json`:
- **`screens`** (predefinito, il prototipo da provare): schermate fisse definite in `data/locations.json` (la Pozza, il Sentiero, il Vecchio albero, il Campo). Si indica un oggetto e Slayme ci scivola sopra. Spostarsi da una schermata all'altra costa tempo. Gli Eroi attraversano alcune schermate agli orari del `route` in `heroes.json`. Gli infortuni del giorno sono pianificati in `days.json` (`incidents`): il numero sulla bacheca è il loro conteggio, e se Slayme ha un infortunio "prende il posto" di uno di quelli.
- **`free`**: il Prato top-down esplorabile dello scheletro (`data/maps/meadow.json`), lasciato com'era.

## Comandi

Mouse oppure tastiera/gamepad.

- **Mouse:** passa sopra un oggetto per vederlo, clic sinistro per usarlo, clic destro per sputare ciò che si ha dentro. Clic per far avanzare i dialoghi e scegliere i verbi in battaglia.
- **Tastiera:** frecce o WASD per scegliere l'oggetto (o il verbo); Z, Invio o Spazio per usarlo o andare avanti; X o Esc per sputare.
- Gamepad: croce per scegliere, A per usare, B per sputare.

## Esportare per Windows

Il preset "Windows Desktop" (eseguibile unico, pck incorporato) è in `export_presets.cfg` e include i file `data/*.json` e i manifest dei pacchetti, che Godot da solo non esporterebbe. Servono i template di esportazione di Godot 4.7.2 (Editor → Gestisci template di esportazione), poi Progetto → Esporta. L'eseguibile finisce in `build/windows/`.

## Test

```
godot --headless --import
godot --headless res://tests/smoke_test.tscn
```

Controlla registro delle regole, hook, nomi, pacchetto arte, lavori, battaglia (difendersi e fuggire, nascondersi fino alla noia, fango, previsioni, MP), fiducia e memoria, poi gioca da solo una giornata intera fino al mattino dopo. Esce con codice 0 se tutto passa.

## Cosa è segnaposto o manca

- Tutti i testi, i numeri di bilanciamento e la grafica.
- Manca l'audio oltre a campanella, fanfara e colpo.
- Fuori dal prototipo per scelta: lo Strumento, l'ottimizzazione, lo sciopero, il secondo atto, i finali.
