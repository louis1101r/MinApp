# MinApp: opsætning og arbejdsgang

## Maskine og begrænsninger
- Intel MacBook Pro på macOS Sequoia 15.8. Kan ikke opgradere til macOS 26, derfor ingen lokal Xcode.
- Homebrew virker ikke (understøtter ikke Intel). Kun Apples Command Line Tools, git og gh (installeret manuelt i /usr/local/bin).
- Du kan IKKE bygge, køre simulator eller type-checke Swift lokalt. Vær ekstra omhyggelig med at koden kompilerer.
- Brug ikke swift-lsp: den mangler iOS SDK og melder falske fejl.

## Build
- Projektet genereres med XcodeGen ud fra project.yml. Der er intet .xcodeproj i repoet.
- GitHub Actions (.github/workflows/build.yml) bygger på runner macos-26 med Xcode 26.6, uden code signing, og uploader MinApp.ipa som artifact.
- Repo: github.com/louis1101r/MinApp (offentligt, main-branch).
- Arbejdsgang: ret kode → commit → push → gh run watch → ved fejl: gh run view --log-failed, ret og push igen, indtil grønt.
- Ren logik (MinApp/Catalog*.swift, Values.swift, Logic.swift, Backup.swift) har kun Foundation og kan testes lokalt: `tools/logic-tests/run.sh` (progression, migrate v2/v3/v4, 3.000-træningers ydelse, og at webappen kan læse en v4-backup). Kør den før push, når logikken ændres.

## Installation på iPhone
- iPhone kører iOS 26.6.2.
- Den usignerede .ipa installeres med SideStore og et gratis Apple ID. LocalDevVPN skal være tændt.
- Gratis Apple ID: max 3 aktive app-ID'er (SideStore bruger 1, MinApp + widget bruger 2) og max 10 nye app-ID'er pr. uge.
- Tilføj derfor IKKE nye targets/extensions uden at spørge mig først, og ændr ikke bundle ids.
- Bundle ids: com.louis.MinApp og com.louis.MinApp.MinAppWidget (widget-id skal starte med app-id).
- Apps udløber efter 7 dage uden fornyelse i SideStore.
- Brug ikke funktioner, der kræver betalt Apple Developer-konto, fx push-notifikationer, iCloud/CloudKit eller HealthKit.

## Appen
- Målet er en træningsapp til styrke og hypertrofi. Brugeren har 5+ års erfaring og træner 3 til 6 gange om ugen.
- Nuværende version er kun en test: én knap starter en 5-minutters countdown som Live Activity i Dynamic Island. Det virker på telefonen.
- Live Activities kører lokalt med Text(timerInterval:), ingen push.
- Widget og app deler data via App Group.

## Reference
- `docs/webapp.html`: den oprindelige webapp. Sandheden for datamodel, øvelser og progressionslogik.
- `docs/traeningsapp-kontekst.md`: beskrivelse af webappen. Afsnit 8 er forældet (ingen Xcode/simulator); opsætningen i denne fil gælder.
- `MinApp/Catalog+Builtin.swift` er genereret fra `docs/webapp.html` og skal ikke rettes i hånden.
- Datamodel v4: to profiler (Louis og makker). Backupformatet er webappens v3 for Louis + feltet `buddy`. Ændres formatet, skal `Backup.parse` udvides og testene opdateres.

## Kommunikation
- Svar på dansk, kort og direkte.
