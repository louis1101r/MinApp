# Kontekst: Træningsregistrering (webapp → kommende iPhone-app)

Du overtager et projekt fra en tidligere Claude-session. Læs hele dette dokument, før du gør noget. Tal dansk med brugeren, hold svarene korte, og forklar opsætning af Xcode og iPhone trin for trin. Brugeren er ikke udvikler.

## 1. Hvor ligger tingene

- **Kilde (sandheden):** `/Users/louisraben/Downloads/Træningsregistrering.html`. Én selvstændig HTML-fil (~81 KB, ~1300 linjer) med inline CSS og JS. Ingen build-trin, ingen afhængigheder, ingen netværkskald. Ikke et git-repo.
- **Seneste udgivne pakke:** `/Users/louisraben/Downloads/traeningsregistrering-v3.zip`, der indeholder den samme fil omdøbt til `index.html`.
- **Hosting:** Brugeren uploader selv zip'en til Netlify (træk-og-slip). Adresse: `https://rococo-toffee-de5b9d.netlify.app/`. Du har ikke adgang til Netlify. Efter ændringer: lav en ny zip med filen som `index.html` og send den til brugeren.
- Brugeren har lagt siden på iPhonens hjemmeskærm via Safari → "Føj til hjemmeskærm" og bruger den på iPhone.

## 2. Kodestil

- ES5-stil: `var`, `function`, strengsammensætning af HTML. Ingen frameworks. Hold den stil.
- Hver fane renderes ved at sætte `innerHTML` på `#view` via `render()`. `tab` er `"home" | "hist" | "set"`.
- Brugerindtastet tekst (egne øvelsesnavne og beskrivelser) skal altid gennem `esc()`. `nm(id)` giver et escapet øvelsesnavn.
- Ark og popups: `showSheet(html)` sætter indhold i `#sheet` og tilføjer klassen `.show`. `closeSwap()` er den generelle luk-funktion (fader ud på 220 ms, slår klik fra med det samme og rydder kun, hvis arket stadig er det samme). `sheetHead(title, closeLabel, closeFn)` laver toppen med træk-håndtag. Et swipe ned på `.draghandle` over 80 px lukker arket.
- `confirmModal(title, body, confirmLabel, fn)` erstatter `confirm()`, og `toast(msg)` erstatter `alert()`. Brug aldrig de indbyggede browserdialoger.

## 3. Datamodel (localStorage)

| Nøgle | Indhold |
|---|---|
| `treg` | Hovedobjektet `D` (JSON) |
| `treg_active` | Igangværende træning, eller tom streng |
| `treg_quick_w` | Ventende vægt fra en Genvej (`?w=`), eller tom streng |

`store.get/set` falder tilbage på et objekt i hukommelsen (`mem`), hvis localStorage kaster en fejl.

**`D` (v3):**
```
{
  v: 3,
  groups: { Bryst:[ids], Ryg:[...], Skulder:[...], Biceps:[...], Triceps:[...], Ben:[...], Mave:[...] },  // rækkefølgen betyder noget
  inc: { u: 2.5, l: 5 },                         // mindste vægtspring overkrop/underkrop
  ex: { id: { w: kg|null, sets: n, stall: n, wins: n } },   // progression per øvelse
  log: [ { name, groups:[TG], date:"dd.mm.yyyy", ts, readiness:1-5,
           entries:[ { ex:id, sets:[ {w, r, rir} ] } ] } ],
  deload: n,                                     // log.length ved sidste deload
  customEx: { "custom_<base36-tid>": { n, m, t, lo, hi, s, r, d } },
  favs: [ ["Bryst","Biceps"], ... ]
}
```
**Aktiv træning:** `{ name, groups, readiness, ex:[ { id, target:kg|null, sets:[ {w, r, rir, done} ] } ] }`. Værdierne i sættene er strenge fra inputfelterne.

**Migrering:** `migrate(d)` køres ved `load()`, `doImport()` og `wipe()`. Gammelt v2-format havde `prog:[{n, e:[ids]}]` (tre faste skabeloner) og `q` (rotationsindeks). Migreringen bygger `groups` ud fra skabelonernes øvelser (via `tgOf`), fylder tomme grupper med `DEFAULT_GROUPS`, sletter `prog`/`q` og fjerner ukendte id'er. Gamle logposter uden `groups` får grupper udledt af øvelserne via `logGroups()`. **Ændr aldrig formatet uden at udvide `migrate()`**, for brugeren har rigtige data på telefonen.

## 4. Øvelser

- `BUILTIN_EX`: 50 øvelser. `id → { n: navn, m: detaljeret muskel (Ryg, Bagskulder, Forlår, Lægge …), t: "u"|"l" (vælger vægtspring), lo/hi: rep-interval, s: standard antal sæt, r: pause i sekunder }`.
- `EXDESC`: `id → { s: udgangsstilling, u: udførelse, f: [fokuspunkter], x: [typiske fejl] }` for alle indbyggede øvelser. Egne øvelser har fritekst i `d`. Kun tekst: brugeren valgte bevidst ingen billeder/GIF'er (ophavsret).
- `EX = BUILTIN_EX + D.customEx` (sammenflettes i `migrate`).
- Træningsgrupper: `TG = [Bryst, Ryg, Skulder, Biceps, Triceps, Ben, Mave]`. `TGMAP` oversætter `m` til en træningsgruppe (Bagskulder→Skulder, Forlår/Baglår/Balder/Lægge→Ben). `tgOf(id)`.
- `BIG = [Bryst, Ryg, Ben]`. `SESSION_ORDER = [Ben, Bryst, Ryg, Skulder, Triceps, Biceps, Mave]` (store øvelser først).
- Egne øvelser oprettes med `openCreate(group, toSession)` → `doCreate()`. `t` udledes (`Ben` → `"l"`, ellers `"u"`). Øvelsen lægges nederst i gruppen og tilføjes eventuelt til den aktive træning.

## 5. Logikken

**Anbefaling (`recommend`)**
- `PAIRS = [[Bryst,Triceps],[Ryg,Biceps],[Ben],[Skulder,Mave]]`. Grupper uden øvelser springes over.
- Score per par = mindste tid siden nogen af dets grupper blev trænet (aldrig = uendelig). Det par med højest score vinder. Ved uafgjort vinder det første i `PAIRS`.
- Sidst trænet per gruppe kommer fra `lastTrained()` over `D.log`.

**Sammensætning (`pickFor(groups)`)**
- Grupperne sorteres efter `SESSION_ORDER`. Fra hver gruppe tages de første `capFor(g, n)` øvelser: 1 gruppe = alle; 2 grupper = 4 fra store og 3 fra små; 3 grupper = 3 fra store og 2 fra små. Dubletter fjernes.
- På forsiden vælger man 1–3 grupper med knapper (`togglePick`, `refreshPick` opdaterer kun den del, ikke hele siden). En kombination kan gemmes som favorit.

**Start af træning (`start` → `makeSessionEx(id, readiness)`)**
- Antal sæt = `max(2, st.sets − (readiness==1 ? 1 : 0))`.
- Målvægt = `rnd(st.w × readyMult, inc/2)`. `readyMult`: 1 Slidt 0,9 · 2 Træt 0,95 · 3 Normal 1 · 4 Frisk 1 · 5 Top 1,025.
- Ventende `treg_quick_w` sættes ind i første sæt.

**Under træning**
- `tick(i,j)`: udfylder tomme felter (vægt = mål, reps = `hi`, i tanken = 2), markerer sættet færdigt, vibrerer 15 ms, kopierer vægten til næste sæt og starter hviletimeren med øvelsens `r`.
- Timer: `rest(sec)`, `restEnd`, `adjustRest(±15)`, `stopTimer()`. Vibrerer `[200,100,200]` når den er færdig. Den kører kun, mens siden er åben.
- Øvelser kan byttes (`openSwap` → `doSwap`, der også erstatter id'et i alle gruppelister), tilføjes (`openPicker("session")`) eller fjernes (`removeFromSession`, bekræftelse hvis der er logget noget).

**Afslutning og progression (`finish`)** per øvelse, kun sæt med vægt og reps > 0, "i tanken" = 2 hvis tom. `step` = `D.inc.u` eller `D.inc.l`:
- alle sæt ≥ `hi` og sidste sæts i tanken ≥ 3 → vægt = `rnd(top + 2·step, step/2)`, `stall = 0`, `wins++`
- alle sæt ≥ `hi` → vægt = `rnd(top + step)`, `wins++`
- laveste reps ≥ `lo` → samme vægt, `stall = 0`
- ellers `stall++`. Ved `stall ≥ 2`: vægt = `rnd(top × 0,9)`, nulstil `stall`/`wins`, sæt = standard. Ellers samme vægt.
- `wins ≥ 3` og sæt < standard + 2 og dagsform ≥ 4 → +1 sæt, `wins = 0`.
- Logposten får `groups` = grupperne for øvelser med loggede sæt (ellers `active.groups`).
- Slutskærmen tæller vægtene op fra gammel til ny (`animateAdjCounters`).

**Deload:** banneret vises når `log.length − deload ≥ 18` eller ≥ 3 øvelser har `stall ≥ 1`. `doDeload()` sætter alle vægte til ×0,9 og nulstiller.

**1RM:** `e1rm(w, r, rir) = w × (1 + (r + rir) / 30)` (Epley med i tanken lagt til).

**Udvikling**
- `exStats(id)` giver rækker `{date, best, e1, top, vol, sets}`.
- `volChart()`: søjler for de seneste 12 træningers samlede volumen. Den nyeste er blå.
- `spark()`: minikurve af 1RM for de seneste 12 logninger per øvelse. Farven følger ændringen fra første til sidste logning (±0,5 %).
- `openStats(id)`: stor graf `chartSVG(rows, key)` med vælgeren `setMetric("e1" | "top" | "vol")`, ring om den bedste værdi, og en tabel.

**Genvej / `?w=`:** `applyQuickParam()` læser `?w=72,5`. Er der en aktiv træning, sættes vægten i det første sæt, der ikke er færdigt. Ellers gemmes den i `treg_quick_w`. Til sidst fjernes parameteren med `history.replaceState`.

## 6. Design

- Svejtsisk minimalisme: sort/hvid, blå accent `#0033CC`, rød `#B00020`, skarpe hjørner, 2 px sorte streger, tal med fast bredde, max-bredde 540 px, mobil først, klikflader ≥ 44 px.
- CSS-variabler i `:root` (`--bg --ink --on-ink --muted --line --hair --blue --red --wash`) med mørkt tema via `prefers-color-scheme`. `syncThemeColor()` opdaterer `theme-color`.
- Animationer: fade mellem faner (`go`), ark glider op, knapper skalerer ved tryk, "pop" på gruppeknapper, fremdriftsbjælke, timeren glider ind, grafer tegnes frem med `clip-path` (`.drawin`, `.rise`). `prefers-reduced-motion` slår alt fra.

## 7. Hvad brugeren har besluttet og lært

- Et **låseskærm-widget, hvor man skriver et tal**, findes ikke. Det kan hverken en webapp eller en rigtig app (widgets og Live Activities kan kun have knapper, ikke tekstfelter).
- Genvejen `?w=` er sat op i Genveje-appen, men iOS åbner den i **Safari**, og en app på hjemmeskærmen har sit **eget lager, adskilt fra Safari**. Tallet når derfor sandsynligvis ikke hjemmeskærm-appen. (En tidligere påstand om, at de deler data, var forkert og er rettet over for brugeren.)
- Brugeren valgte: frit valg af muskelgrupper, kun tekstbeskrivelser og egne øvelser. Alt det er bygget og testet.
- **Idéliste der ikke er lavet endnu** (brugeren bad kun om forslag): vis "sidst: 75 × 7" ved hver øvelse; ret/slet gamle træninger (mangler i dag, så en tastefejl ødelægger graf og progression); synkronisering online; backup som fil; offline-understøttelse og app-ikon; +/− knapper; hold skærmen tændt; opvarmning og skivelommeregner; sæt per muskelgruppe per uge; kropsvægt til pull-ups/dips; noter per øvelse; fejr rekorder; fortryd-knap; træningens varighed. Top 3: "sidst"-tal, ret/slet træninger, synkronisering.

## 8. Næste skridt: rigtig iPhone-app ("vej 2")

- **Kun til brugerens egen telefon**, ingen App Store. Gratis Apple-ID i Xcode (Personal Team): appen skal installeres igen hver 7. dag. Brugerens iCloud+-abonnement tæller **ikke** som udviklerkonto. iCloud/CloudKit-synkronisering kræver det betalte program (99 USD om året).
- **Mac'en:** macOS 15.7, kun Command Line Tools, **Xcode var ikke installeret endnu**, ~33 GB fri plads (stramt). Brugeren fandt først appen "Apple Developer" i stedet for Xcode. Tjek først med `xcode-select -p` og `ls /Applications | grep -i xcode`.
- **Det brugeren selv skal gøre:** installere Xcode og iOS-platformen, logge ind med Apple-ID under Xcode → Settings → Accounts, slå Udviklertilstand til på iPhonen, forbinde med kabel og "Stol på", og efter første installation stole på udvikleren under Indstillinger → Generelt → VPN og enhedsadministration.
- **Plan:** SwiftUI-app der spejler datamodellen og progressionslogikken ovenfor **præcis**, plus:
  - Live Activity med dagens træning, næste sæt og pause-nedtælling på låseskærm og Dynamic Island (kræver iPhone 14 Pro+), med knapper som "✓ sæt færdigt" og "+15 sek"
  - lokale notifikationer når pausen er slut
  - widgets
  - import af JSON fra webappens "Kopiér backup" (formatet i afsnit 3, både v2 og v3)
  - backup som fil, som brugeren kan lægge i iCloud Drive
- Byg i trin: træning, timer, Live Activity og notifikationer først; derefter grafer og resten. Test i iOS-simulatoren før telefonen.
- Et alternativ blev tilbudt, men ikke valgt: webappen kunne starte Ur-appens timer via en Genvej og dermed få nedtælling i Dynamic Island uden en rigtig app.

## 9. Test

- Claudes indbyggede browser åbner lokale filer som en forhåndsvisning, hvor **localStorage kaster SecurityError**. Appen bruger så `mem` og starter forfra ved hver genindlæsning. Det er ikke en fejl i appen.
- Mørkt tema kan ikke emuleres for lokale filer, `?w=` når ikke frem, og skærmbilleder kan blive sorte, hvis panelet er skjult. Brug `find`, `read_page` og `javascript_tool` til at verificere.
- Tjek altid konsollen for fejl og test i mobilbredde (375 px).
