# MBS architectural reference research

Research date: **28 October 2026**. This package establishes source-backed constraints for the full requested interior. **It does not establish an exact complete as-built interior and does not certify the goal complete.** No game code, art, engine instance, account, purchase or Git mutation was made by this researcher.

## Strongest references and what they prove

The operator's [kiosk map](https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/sands-lifestyle/SandsLifeStyle_KioskMap.pdf) was visually inspected in Chrome. It provides a schematic of Shoppes L1/B1/B2/B2M and the joined Hotel L1 atrium. Its hotel panel shows the three tower lobbies connected along one spine and identifies selected retail/coach-bay lift links. It has no inspected metric scale, and the upper hotel floors are absent.

The official [hospitality floor-plan brochure](https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/meetings/packages-and-promotions/hospitality-meetings-package/Floor-Plan.pdf) was visually inspected at PDF pages2,8,10. The footer identifies **2018.11**. Page2 separates the hotel from the retail/entertainment complex across Bayfront Avenue, connected by underpasses/bridges. Page8 depicts roof programs, with the observation deck at the Tower3/north cantilever. Expo plans in this brochure are not hotel guestroom plans. Event-space areas printed on page8 are not a surveyed outline of every roof space.

The current [hotel factsheet](https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/company-information/media-centre/factsheets/amenities/marina-bay-sands-hotel.pdf) describes approximately1,850 rooms/suites across55floors, including775suites. The [corporate factsheet](https://www.marinabaysands.com/content/dam/singapore/marinabaysands/master/main/home/company-information/media-centre/factsheets/corporate/marina-bay-sands-corporate.pdf) says room refurbishment finished in May2025. Historical architectural descriptions of roughly2,600rooms must not become the current room inventory.

The operator [FAQ](https://www.marinabaysands.com/faq.html) distinguishes the public observation deck on Level56, a mezzanine leading to part of Level57, and SkyPark/pool/restaurants on Level57. It places the observation-deck box office at Tower3 B1. The [visitor page](https://www.marinabaysands.com/attractions/skypark-observation-deck.html) identifies the Tower3 driveway entrance. This resolves the apparent56/57 discrepancy; the levels should not be collapsed into a single public pool floor.

The [renovation FAQ](https://www.marinabaysands.com/faq/hotel-renovation.html) announces lobby/arrival works from6January2027 and roof/pool work fromMay2027. These are future changes relative to this research date. Do not apply those temporary closures or detours to the October2026 target accidentally.

## Source coverage limit

There is enough evidence to plan a recognizable connected ground atrium, selected underground retail links and the named roof programs. Publicly available sample [suite plans](https://www.marinabaysands.com/content/dam/marinabaysands/hotel/paiza-signature-suite/paiza-signature-suite-floorplan.pdf) concern individual configurations. Current [room pages](https://www.marinabaysands.com/hotel/rooms-suites/sands-signature-suite.html) explicitly warn that displayed layouts and furnishings can vary. Neither proves which room occupies every floor, the complete service/back-of-house arrangement, all shafts, wall thicknesses or level elevations.

Keep those fields **UNVERIFIED**, obtain current as-built evidence from an authorized source, and retain the full objective. Do not substitute a lobby, one furnished room, or55 repeated generic floors for the entire requested interior. `coverage.json` keeps every unresolved area visible.

## Existing implementation mismatches to address

- `skypark_access.gd` puts the public terrace at local x30..84 and the roof arrival at x79. Current world +x is south. The real public observation deck is at the north/Tower3 end; the legacy area is an authored gameplay terrace, not a verified real floorplate.
- `mbs.gd` attaches a Shoppes-style podium to hotel massing. The real hotel/retail separation includes Bayfront Avenue and specific cross-links.
- Solid tower/podium `col_box` volumes support exterior collision. They must become actual floor/wall/shell collision where interiors are opened; placing furnished rooms inside those solids will not make them traversable.
- The authored roof H marker is not established as a real MBS helipad by the inspected sources. Keep any gameplay convenience clearly distinguished from architectural evidence.

## Art and rights

`asset-candidates.json` records source-first checks of Fab, NVIDIA SimReady, ThreeJS Assets and Poly Haven. No asset was acquired. Candidate furniture does not establish a licensed or visually suitable MBS interior kit. Some Fab listings expose no readable license selection and some are UE-only; SimReady tree/license requests were inaccessible; ThreeJS downloads require a free account and prohibit raw-file redistribution. The current stylized candidates may fail the requested exterior-quality fit. These access/fit limits do not prove no suitable asset exists.

Official PDF/photographic material remains reference-only. The2018brochure expressly reserves reproduction rights. No third-party PDF or plan image is placed in public source. Direct terminal downloads timed out, but the Chrome PDF viewer loaded the plans and supported actual visual inspection; no local PDF hash is claimed. See `references.json` for exact source URLs and distinctions.
