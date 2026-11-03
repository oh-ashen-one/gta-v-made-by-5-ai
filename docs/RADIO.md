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

The native radio loads `game/assets/audio/radio/tracks.json`, shuffles all five without replacement, prevents an immediate repeat across shuffle cycles, plays only in cars, follows pause, and fades out when leaving a car or disabling radio. The radio toggle is saved with game preferences and defaults on for older saves.

## Restore media on another machine

Use the owner's authorized Suno account and each source link above to download the already-unlocked MP3. Place it at the corresponding `res://` path in `tracks.json`. Verify its SHA-256 against that manifest, then run the normal Godot import. These MP3s are intentionally excluded from public source Git. A clone without restored music remains runnable with the radio silent; five-track acceptance requires the media.

Rights evidence: generated and downloaded while the account showed Pro. Suno's current paid-plan/ownership guidance states commercial-use rights for the owner's permitted paid downloads. This is not a blanket license for other artists' Suno songs or public raw-asset redistribution.

- https://help.suno.com/en/articles/9601665
- https://help.suno.com/en/articles/2416769
- https://suno.com/blog/suno-updates-tos
