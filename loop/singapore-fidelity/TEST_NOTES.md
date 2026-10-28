# Test corrections and retained failures

- HelicopterR2:46/50, four first-step checks sampled only0.25s. Retainedearlydisplacement inR5 andobserveda full1s withstronger>2m criteria; no locomotioncodechange.
- HelicopterR3/R4: repair/reboard fixture was hovering1.18maboveroof, so physicalexitrefusalwascorrect. R5retainsnegativehealthyhoverrefusal, actualShiftsetdownandpositiveE;65/65.
- CoreR1:139480mscoldworldbuild, then90-secondTimerexpiredwhenonly2442ms ofactualsuite timehadpassed (46checks). A newlycreatedTimerconsumedtheworld's accumulatedfirst-frame delta. Guardnowusesactualmonotonicelapsed, retains90sdeadline andhasper-framebackup. Thisdoesnotclearcoldstartup/performance; rawfailurekept.
- Fullworldheadless33/33; firstactualrender56/57, onlypost-loadwalkingfailure. State/floor/exactsave/loadpassed. Motion/input/contactdiagnosticpending; no thresholdweakening orproductionworkaroundwithoutcause.

None ofthese fixtures proveswholeSingaporeaccuracyorentireMBScompletion.
