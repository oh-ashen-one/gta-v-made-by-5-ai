# Orchard car radio — 2026-11-03

Five original instrumental styles generated through the owner-authorized signed-in Suno Chrome session. Five generation requests produced two alternatives each; one complete track from each request was downloaded and installed. These are technical selections, not a claim of subjective listening approval. The export UI showed Pro and the download allowance changed from 26 to 21. No subscription or extra credits were purchased, and no track was published.

| Track | Style | Duration | Source |
|---|---|---|---|
| Bayfront Afterglow | nu-disco / tropical house | 3:34 | [Suno](https://suno.com/song/c0b43ac5-b7ec-481d-9b0b-4fc4d195438d) |
| Expressway Blue | liquid drum and bass | 3:15 | [Suno](https://suno.com/song/48a1fdc1-ec22-4824-865d-0d33089187ef) |
| Kopi Cruise | neo-soul / jazz-hop | 3:26 | [Suno](https://suno.com/song/7459c1c8-96b0-4166-b46a-e0d0dd40546d) |
| Neon Causeway | synthwave | 3:23 | [Suno](https://suno.com/song/3cb2f4d8-773e-4e08-8531-7406e5524cef) |
| East Coast Run | indie surf-funk rock | 2:41 | [Suno](https://suno.com/song/1964d290-6e9a-44a0-be8b-0ef570c370a2) |

All prompts requested original instrumental music around three minutes, immediate driving momentum, contrasting musical sections, a clean spacious mix with room for engine audio, and no spoken words, sirens or imitation of a named artist. The five briefs were tropical nu-disco at 116 BPM, liquid drum and bass at 172 BPM, Rhodes/trumpet jazz-hop at 92 BPM, analog synthwave at 104 BPM, and clean guitar surf-funk rock at 128 BPM.

The native radio loads `game/assets/audio/radio/tracks.json`, shuffles all ten without replacement, prevents an immediate repeat across shuffle cycles, plays only in cars, follows pause, and fades out when leaving a car or disabling radio. The radio toggle is saved with game preferences and defaults on for older saves.

## Restore media on another machine

Use the owner's authorized Suno account and each source link above to download the already-unlocked MP3. Place it at the corresponding `res://` path in `tracks.json`. Verify its SHA-256 against that manifest, then run the normal Godot import. These MP3s are intentionally excluded from public source Git. A clone without restored music remains runnable with the radio silent; five-track acceptance requires the media.

Rights evidence: generated and downloaded while the account showed Pro. Suno's current paid-plan/ownership guidance states commercial-use rights for the owner's permitted paid downloads. This is not a blanket license for other artists' Suno songs or public raw-asset redistribution.

- https://help.suno.com/en/articles/9601665
- https://help.suno.com/en/articles/2416769
- https://suno.com/blog/suno-updates-tos


## Vocal expansion — afternoon playtest

The original five instrumentals remain installed. Five additional original vocal songs were generated and downloaded through the same authorized Suno Pro account, taking the download allowance from 21 to 16. Six generation submissions were used: the first EDM submission retained the preceding lyric draft, so it was replaced with a submission whose lyrics were verified before generation. Only the corrected EDM version is installed. No purchase, subscription change or public publishing action was made. Selection is based on requested style, lyrics and complete media; subjective listening acceptance remains with the owner.

| Track | Style | Duration | Source |
|---|---|---|---|
| Night Shift | UK drill, British rap vocals | 1:57 | [Suno](https://suno.com/song/8c4998fd-011d-4c68-98f1-69578d0b47bb) |
| Electric Blue | Vocal progressive-house EDM | 3:21 | [Suno](https://suno.com/song/d4f9529f-2156-4106-984f-5b7758d49f82) |
| Gold in the Rain | Soulful hip-hop, gospel choir, original rap | 2:49 | [Suno](https://suno.com/song/1dd1b41b-8a20-4417-a69a-a1470cb46c91) |
| Starlight Taxi | Korean-English K-pop vocals | 1:44 | [Suno](https://suno.com/song/b3b7a1a0-dd87-49f4-bea3-23d01078426b) |
| Moonlight Darling | 1950s doo-wop, crooner and harmonies | 2:22 | [Suno](https://suno.com/song/75dc5e9f-2135-4cdb-96ff-7b6e2191fc04) |

All new lyrics are original. The hip-hop brief uses soul-inspired textures, gospel choir, brass, piano and introspective verses with an original voice. MP3s remain private ignored runtime assets; acquisition URLs, duration and SHA-256 are in the versioned manifest. Restore each owner download to its manifest path, then run the Godot import step.
