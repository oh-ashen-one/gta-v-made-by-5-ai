# Private macOS signing follow-up

The raw Godot export launched through its native executable and passed the recorded UI/regression tests. A separate `codesign --verify --deep --strict` audit returned exit1 for an invalid inherited signature in the arm64 slice. Export preset `codesign=0` had not produced a valid project-level signature; the executable still carried template signature metadata.

Root copied the task-owned app and attempted local ad-hoc signing. The copies inside the FileProvider-backed Documents checkout repeatedly regained cosmetic `com.apple.FinderInfo` metadata and signing rejected it. No game process was launched from those failed copies. One diagnostic Python attempt also found that this macOS Python build exposes no `os.listxattr`; the reproducible helper uses the native `xattr` CLI instead.

The successful copy was staged at `/private/tmp/orchard-wave02-signed-be6a8aa/Orchard Reach.app`. The helper removed only `com.apple.FinderInfo` from that copy. It explicitly preserves quarantine, provenance, ACLs and every other security-related attribute. No global configuration, account, identity, hook trust or OS permission control changed.

`private-signing.json` records the before/after inventories, source unchanged check, identical PCK hash, local ad-hoc signature, strict verification exit0 and archive hash. The valid bundle uses `com.ashenone.orchardreach`, `Signature=adhoc`, no TeamIdentifier, and a sealed resource list. The archive is `game/build/mac/OrchardReach-wave02-private.zip`,393884658bytes, SHA256 `377447ff855c91da8746c23a67cc4877c22b34e32eadf64c420a6c1b56c006e8`.

This is local integrity signing. It is not Developer ID signing, notarization, Finder/Gatekeeper launch proof, asset-rights clearance or public-release authorization. Launch and route verification of the signed archive are separate evidence. The running raw final-r3 soak app was never modified; its source/bundle identity remains unchanged.

CPU/disk copy/sign/archive activity ran approximately15:01:45–15:03:45UTC during the shared-slot workload. Resource review must retain that qualification. The repeated combat hitches occurred earlier and cannot be attributed to this later activity.
