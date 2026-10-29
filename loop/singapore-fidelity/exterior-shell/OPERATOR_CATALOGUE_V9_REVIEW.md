# Catalogue-based MBS inventory proposal v9

**Status: proposal; not adopted into game inventory or a playable build.** This corrects the predecessor's invented taxonomy while keeping every old ID/history record. It does not claim that the reconstructed mix or room positions are surveyed.

## Source-grounded corrections

The [LVS21October2026 presentation](https://s28.q4cdn.com/640198178/files/content_files/LVS-3Q-2026-Presentation-Deck.pdf), slide25/PDFpage25, reports **1,844 keys including775 suites**. The old1,850 was an exact normalization of rounded marketing language. All1,850 old IDs remain in the legacy map; six non-suite normalization placeholders are explicitly superseded, with their entire original records retained. No operator room number was known for those IDs, and no surveyed physical room is asserted to have been deleted.

The [operator's June2025 completion article](https://www.marinabaysands.com/expo-and-convention/gallery/event-highlights/2025/06/hotel-room-renovations-and-jin-ting-wan.html) describes about370 Paiza accommodations, mostly suites. The proposal chooses370 exactly as a reconstruction:50Club rooms and320 varied suites. The remaining1,474 Sands keys comprise1,019 rooms/studios and455 suites. Per-type counts and variant frequencies are **unknown**, so every proposed count is labeled reconstruction. These counts were chosen before physical allocation and are not an optimizer's all-small-suite workaround.

Current category pages, linked individually in the JSON catalogue, govern areas, bedrooms and amenities. Examples of material corrections include Sands Bay80m² inTower3; Sands Premier95m²/1bedroom inTowers1–2 and130m²/2bedrooms inTower3; Paiza Bay75m² inTower3; Paiza Grand140/210m² and Paiza Signature140/210m² by bedroom count; Marina160m²; and Chairman520m²/3bedrooms versus630m²/4bedrooms. The old generic Signature140 reference for every suite is not retained as a factual requirement.

## Reconstructed mix

| Collection | Category / variant | Proposed keys | Published average area |
|---|---|---:|---:|
| Sands | Premier Room |894|45m²|
| Sands | Premier Studio |125|70m²|
| Paiza | Club Room |50|55m²|
| Sands | Bay Suite |90|80m²|
| Sands | Premier1-bedroom /2-bedroom |165 /45|95 /130m²|
| Sands | Family1-bedroom /2-bedroom, each with kids' room |25 /30|85 /145m²|
| Sands | Signature |100|140m²|
| Paiza | Bay |29|75m²|
| Paiza | Premier1-bedroom /2-bedroom |80 /25|110 /160m²|
| Paiza | Grand1-bedroom /2-bedroom |40 /10|140 /210m²|
| Paiza | Signature1-bedroom /2-bedroom |50 /15|140 /210m²|
| Paiza | Family |15|175m²|
| Paiza Royal | Harbour /Marina |6 /10|160 /160m²|
| Paiza Royal | Skyline /Merlion /Straits |8 /6 /5|200 /260 /300m²|
| Paiza Royal | Horizon /Presidential |4 /13|330 /360m²|
| Paiza Royal | Chairman3-bedroom /4-bedroom |2 /2|520 /630m²|

The programme retains distinct living/dining/wardrobe/bath spaces, family kitchenettes and bunk rooms, appropriate media/bar/kitchen/pool/golf variants, and the larger residences' gym/spa/pantry programmes. A golf/media/pool variant is selected only where its actual category offers it. Paiza Signature's entertainment den uses foosball; the former random assignment of billiards to hundreds of generic Paiza units is archived, not called an operator fact. Game rules may permit exploration, but complimentary services/booking entitlements are not gameplay implementation claims.

## Zoning and unknowns

Current explicit tower restrictions are stored for each supported category. The operator places Paiza/Royal on high floors, but no exact per-key floor schedule is claimed. Historical2024 phase figures (Towers1–2 versusTower3) are planning evidence, not automatically a current tower inventory. Room placement is intentionally null until a perimeter-based source-envelope allocator proves complete coverage and real facade-facing windows. Bedrooms and living zones must get the appropriate actual exterior frontage; internal bathrooms/media/storage can use deeper space. No invented interior windows, source-envelope enlargement or furniture scaling is authorized.

The room/studio/suite classification follows the marketed category names; the operator does not publish a complete per-type financial key ledger. Family pages describe an advertised1-/2-bedroom unit plus a separate kids' room. The proposed sleeping-space interpretation is explicit and should be independently checked against each applicable floorplan before factory adoption. Common architectural basics in the programme list are reconstruction; distinctive amenities must remain source-backed. External resort facilities such as The Play Den are not cloned into every guest unit.

## Verification and review request

`audit_catalogue_inventory_v9.py` passed5,924 coverage/schema checks:1,844active keys,775suites, all1,850legacy IDs, six explicit placeholders,26catalogue variants, exact source binding and named programme propagation. This is **not independent fact verification**, native room construction or gameplay acceptance.

Independent critique should verify the current detailed category facts (including locale redirects and bedroom-specific areas), the370collection interpretation, suite classification assumptions, all zoning claims, larger-residence representation, legacy-ID migration and complete programme coverage. Then the allocator must prove every active key fits actual source geometry with real windows, full furnishings and reachable circulation. The old inventory, minimum-fit candidates, wrong table interpretation and failed perimeter variants remain history.
