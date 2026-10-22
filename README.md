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

## Datakilder

Saphe har **ingen offentlig API**, men Saphe bruger kortdata fra **HERE** til fartgrænser på alle danske veje.
Appen henter derfor de samme data direkte fra HERE:

- **HERE (standard)**: HERE Routing API v8 med `spans=speedLimit`. Appen beder om en kort rute (ca. 1,5 km)
  i kørselsretningen med fartgrænsen for hvert stykke og følger den lokalt. En ny rute hentes kun ved sving,
  eller når ruten er ved at være kørt, typisk ét kald pr. 1–2 km. Antal kald pr. måned vises under Indstillinger
  og har et loft (standard 5.000), så du ikke overskrider HERE's gratiskvote. Tjek den aktuelle kvote på platform.here.com.
- **OpenStreetMap** bruges automatisk, hvis HERE fejler, ikke kender grænsen eller kvoten er brugt.
  Den kan også vælges alene.
- **Saphe** er en plads til Saphe's egne data (`SapheSpeedLimitProvider.swift`), hvis de en dag åbner en API.

**HERE API-nøgle:** opret en gratis konto på [platform.here.com](https://platform.here.com) og gå til
Access Manager → Apps → Register new app → Credentials → API Keys. Indtast nøglen i appen under Indstillinger → Datakilde.

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
| `Providers/` | Datakilder: HERE (rute-lookahead, flexible polyline), OpenStreetMap (cache og vejmatching), Saphe-plads |
| `Services/AnnouncementPolicy.swift` | Hvornår der annonceres/advares (ren logik, unit-testet) |
| `Services/Announcer.swift` | Tale (dansk stemme), advarselstone, dæmpning af anden lyd |
| `Services/LocationService.swift` | GPS i baggrunden |
| `Services/SpeedMonitor.swift` | Binder det hele sammen |
| `Views/` | SwiftUI: skilt, fart, indstillinger |

> Appen er et hjælpemiddel. Følg altid den skiltede fartgrænse.
