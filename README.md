# Fartgrænse – lydannoncering af fartgrænser (iOS)

En iPhone-app der kører i baggrunden og siger den aktuelle fartgrænse højt i
AirPods, bilens højttaler (Bluetooth/CarPlay) eller telefonen.

## Funktioner

- **Annoncering ved skift**: "Fartgrænse 80", når du kører ind på en vej med en anden grænse.
  En ny grænse skal ses to gange i træk, før den bliver annonceret, så GPS-hop ved kryds ikke giver falske skift.
- **Gentagelse med faste mellemrum**: hvert 1, 2, 5, 10 eller 15 min ("Fartgrænsen er 80").
- **Advarsel ved for høj fart**: tone plus "For hurtigt. Grænsen er 50.", når farten er over
  grænsen + tolerance (standard 3 km/t) i mindst 2 sekunder. Advarslen gentages (standard hvert 20. sek)
  så længe du kører for stærkt. De første 5 sekunder efter et skift til lavere grænse er der ingen advarsel.
- **Kører i baggrunden** med skærmen slukket (baggrundstilstand for lokalitet og lyd).
- **Musik/podcast dæmpes** kun mens der tales og kommer tilbage til fuld lydstyrke bagefter.
- Retningsbestemte grænser (`maxspeed:forward/backward`), ensrettede veje og zoneværdier som `DK:urban` håndteres.

## Om Saphe-data

Saphe har **ingen offentlig API** til deres fartgrænsedata. Deres data findes kun i Saphe Link-appen
(Premium) og i deres samarbejder. Derfor:

- Appen bruger **OpenStreetMap** (via Overpass API) som standard. Det er gratis og dækker Danmark godt,
  men vejstykker kan mangle grænse eller være forældede.
- Der er en klar **Saphe-datakilde** (`SapheSpeedLimitProvider.swift`). Hvis du får partneradgang hos Saphe,
  skal kun request/response i den fil tilpasses deres rigtige API. Endpoint og nøgle sættes under Indstillinger.

Datakilder er udskiftelige via protokollen `SpeedLimitProvider`, så en kommerciel kilde
(fx HERE eller TomTom) også kan sættes ind.

## Byg og kør

Kræver en Mac med Xcode 15 eller nyere og iOS 17 eller nyere på telefonen.

```sh
brew install xcodegen
xcodegen generate
open SpeedAnnounce.xcodeproj
```

Vælg dit Apple-team under *Signing & Capabilities* og kør på din iPhone. Tryk **Start kørsel** og giv adgang til
lokalitet. Vælg "Tillad altid", hvis appen også skal kunne fortsætte efter længere tid i baggrunden.

Tests: `xcodebuild test -scheme SpeedAnnounce -destination 'platform=iOS Simulator,name=iPhone 15'`
(kører også automatisk i GitHub Actions).

## Struktur

| Mappe | Indhold |
|---|---|
| `Providers/` | Datakilder: OpenStreetMap (med cache og vejmatching), Saphe-plads, `maxspeed`-parser |
| `Services/AnnouncementPolicy.swift` | Hvornår der annonceres/advares (ren logik, unit-testet) |
| `Services/Announcer.swift` | Tale (dansk stemme), advarselstone, dæmpning af anden lyd |
| `Services/LocationService.swift` | GPS i baggrunden |
| `Services/SpeedMonitor.swift` | Binder det hele sammen |
| `Views/` | SwiftUI: skilt, fart, indstillinger |

> Appen er et hjælpemiddel. Følg altid den skiltede fartgrænse.
