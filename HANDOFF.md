# Astra-6 enhancements — IN PROGRESS

Owner: current Codex session with explicitly authorized builder/critic subagents. Branch `Astra-6-enhancements`, baseline main451c8eb (Week1 game639ef5c). Fixed2026-10-25 18:20:57–22:20:57UTC, final30min21:50:57. No main merge or extension. Task scope in loop/astra-6/TASK.md; machine state in RUN.json.

## Progress
- Baseline Week1 source tested281/281 headless. Real baseline29fixed views captured under sharedlease, in loop/astra-6/evidence/baseline-views; GPU shared with owner's Invincible game, not performance acceptance.
- Lower traffic: ambient112→48, physics14→7, roadparking97→51 while all20courtyard +3openingroadcars preserved. Real spawned protected vehicles and camera-cut recycling covered.
- Same unmodified headless downtowndrive: baseline445.4s/91.5waiting/0tows vs reducedtraffic314.0s/19.2waiting/0tows. Candidate usedone scriptedunstick; single-runcomparison, nothumanfeel proof. Fulljunctionreview stillobserved box/zebra stops.
- BayfrontCourier optional physical E activitybetweenheritagewaterfront andMBSEventPlaza; independentstoryobjective, save/load/legacy/NewGame/death integration. Allcurrentintegration296/296headlesschecks pass. Dedicatedrealwalk traversed1832m, JubileeandHelix withoutjump/teleport but exposedMBSnorthpromenadelip; physicalrampfix nowintegrated, fulldelivery+returntestpending.
- Heritage promenade30cmcurb seam repairedwith5visiblecollisionramps; normalspawn courierwalkprovednojump access.
- ExistingapprovedgranitePBRtexture wired tocentralplazas at600mmslabscale; no generationcredits, privateassetmanifestupdated. Runtimevisualcritique pending.
- Landmarkaccessbuilder working on physicallyprotectedMBSpublicSkyPark, liftreturn andsmallhelicopterlandingzone; notyetintegrated.

## Ownership
- traffic_builder in siblingastra6-traffic, branchAstra-6/traffic: completedinitialpiece+criticfixes; latesta50fff4 integrated. Noownedengineleft.
- downtown_builder in siblingastra6-activities branchAstra-6/downtown-activities: newcourierfiles/tests. Latest a89d3e5 integrated; waitingforMBSramptest.
- landmark_access_builder in siblingastra6-landmark-access branchAstra-6/landmark-access: newskypark_access, MBSgeometry, limitedskyparkplan. Northpromenaderamp297043d integrated; largerpiecepending.
- Parentowns main/coreGame/hud/player/sharedworld hooks andintegration. Independenttraffic/couriercritics reviewedsource: no confirmedproductionblocker; requestedbehavioraltests wereadded or remainexplicit.

## Remaining within window
Finishphysicalcourierroundtrip; integrateandtestsafeMBSroofaccess/flight; capturecurrentruntime downtown/bridge/flight views andfreshvisualcritique; verifylowertraffic rendereddriving; finalregressions/route/package/privateassets/push. Do not claimbaselineimagesasnewfeatureevidence. Keepallrequiredprivateassetsandreferencesuntracked. No purchases/newprovidergeneration.

## Safety
Renderonlythrough loop/render.sh(one_at_a_time outsideFIFO, sharedGPU_SLOT_DIR=/Users/midir/.cache/gpu-slot,render_gate,bounded_run), oneofoursatonce, globalmixedcap2. OtherInvincible/Bully/Veyr sessions untouched. ScopedQApaths only, neveruser save. Baselineworktree siblingastra6-baseline isdetachedread-only; stopdriversbeforeengines/TERM60sgrace; removeonlyown temporaryworktrees afterpreservingassets/pushedwork.
