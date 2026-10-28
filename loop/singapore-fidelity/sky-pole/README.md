# Overhead cloud projection correction — source stage

The actual rendered helicopter capture `heli-world-rendered-r1/captures/03_look_up.png` was inspected. Its white clouds stretch into radial spokes around the overhead camera direction. This is a sky-field projection defect exposed by free upward look, separate from aircraft camera motion.

Only the existing original procedural shader was revised. No sky asset, provider, texture, animation or global lighting setting was acquired or changed.

## Change

The old normalized azimuth direction sampled an almost full noise ring even very close to the pole, while the radial cloud distance remained nonzero. Its radial self-shadow probes and azimuth brightness also depended on that direction. The existing epsilon shifts the exact mathematical normalize-zero ray slightly off true zenith; it does not remove the visible pinching over normal near-vertical pixels.

Inside the declared upper cap, the new projection uses:

- `q = d.xz + vec2(1e-5)`, `s = length(q)`;
- `w = smoothstep(0, 0.4, s)`;
- cloud direction `w * normalize(q)`, with the exact zero ray explicitly defined;
- the same continuous direction for cloud coordinates and all radial up/down self-shadow samples;
- azimuth lighting interpolated toward its isotropic `0.5` limit with the same weight.

The cap is `d.y > 0 && length(d.xz + vec2(1e-5)) < 0.4`, approximately the upper 23.6 degrees of the dome. Outside it, the original direct-sky calculations remain selected. Sun direction, scattering, colors, cloud density/noise, exposure and uniform values are unchanged.

For `0 < s < R`, the weighted direction is `q * (3s/R² - 2s²/R³)`. It tends to zero quadratically and has a finite zero derivative at the shifted pole. At the cap boundary its value and first derivative join the original azimuth mapping because `w(R)=1` and `w'(R)=0`. Cloud coordinates and radial shading offsets therefore converge together rather than leaving a hidden directional shading ring. Azimuth lighting has the same finite limit. True zenith remains continuous despite the tiny retained legacy epsilon bias.

## CPU equation study

Run at background priority:

```sh
/usr/sbin/taskpolicy -b /usr/bin/nice -n 10 python3 loop/singapore-fidelity/sky-pole/measure.py
```

`measure.py` is an explicit CPU transcription of the projection and existing procedural density/shading equations. It is **not a shader compiler or GPU test**. Source and input-capture hashes bind `equation-study.json` for independent inspection.

| Opposing rays' distance from true zenith | Old cloud-coordinate separation | New separation |
| --- | ---: | ---: |
| 1.5 degrees | 4.19842384 | 0.05158845 |
| 0.1 degree | 4.19751743 | 0.00023906 |
| 0.001 degree | 3.36735381 | 0.00000003583 |

All sampled field, density, radial-shadow, light and azimuth values are finite after the change. The shifted exact normalize-zero ray is now defined as the central cloud sample and azimuth `0.5`. The study also compares 384 lower-angle samples outside the cap; their complete CPU field/shading values are exactly unchanged. Sixty-four approaches to the cap boundary from 1e-6 inside also converge to the legacy field/shading, with a maximum difference of 1.06614561624e-09. These are mathematical/source checks, not runtime pass counts.

Before shader SHA256: `daf5b419a7026eed3bd5b0e62ce1b3006a5b35b0e4cf15cce7ddb40a2d282c84`.

After shader SHA256: `75e46d5f8fe9f303930b685fba49c8fd9a1fb4610c3ded91198e5471c0ac8b78`.

## Remaining verification

- Godot shader parsing/compilation and actual rendered output are unverified.
- Parent must compare matching horizon, intermediate-pitch and near-vertical gameplay captures, including transition through the cap.
- Direct sky values outside the cap are preserved; **whole ground screenshots are not certified identical**. The project convolves this same sky for ambient/reflection lighting, so corrected overhead radiance can alter indirect illumination. Compare the actual ground/exposure result before accepting it. A separate legacy-only cubemap was deliberately not introduced because it would leave different visible and reflected clouds.
- Keep the failed post-reload walking gate and broader Singapore/MBS requirements separate. This shader does not resolve those tasks or establish performance acceptance.

No engines, GPU work, UI controls, process changes or Git commands were used by this worker. The owner's running game was left untouched.

The inert `wiki-suggestion.json` contains a durable fact for the parent to file with `wiki-suggest` at integration/task end. No wiki page or other repository was edited or published by this child.

## Independent equation review

The original capture critic independently re-reviewed the shader and reproduced the opposing-ray convergence. It found no remaining source-level pole singularity or cap-boundary discontinuity. This is code/math approval only. The CPU light/density study uses a fixed representative horizontal sun input; it neither reproduces the actual scene LIGHT0 vector nor computes final GPU COLOR. Lower-angle direct-equation preservation does not prove bit-identical ground images because the sky also drives ambient and reflection convolution. Matched actual near-vertical, cap-transition, horizon and ground renders remain required.

## Parent-run actual rendered A/B helper

`game/src/systems/fidelity_tests/sky_pole_review.gd/.tscn` instantiates the real `main.tscn` exactly once. It pauses the SceneTree and gameplay, freezes production-node callbacks, hides the HUD, clears bindings only inside this QA process and keeps the mouse visible. It does not call save/load or start another test controller.

The same actual world and fixed camera poses are captured for the old shader and frozen candidate. Baseline source is loaded into `Shader.new()`; both phases duplicate the production sky/material, explicitly reapply all ten actual scene uniform values and preserve the production radiance/sky settings. Warmup is four seconds and at least 48 rendered frames per sky, then one second and at least 16 frames after each camera change. Actual warmup durations/counts are recorded; they are not a proof that all radiance/TAA history has converged.

Five disclosed fixtures produce ten PNGs: an eye-height opening-sidewalk view just ahead of the frozen actor, an elevated horizon view, two views through the cap boundary at 62°/72° elevation and a near-vertical 88.5° view. These are lighting fixtures, not native player-camera, animation, flight, traversal or control evidence. Both phases use the same instance; camera transforms, actual pixels and world-node counts are compared. Render-time shader motion/TAA can still vary despite paused gameplay.

Parent prepares the immutable baseline under a new owned run directory and runs the scene through the normal shared lease/gate wrapper. For example:

```sh
bash loop/singapore-fidelity/run_engine.sh sky-pole-review-r1 300 \
  /private/tmp/singapore-fidelity/sky-pole-review-r1 -- \
  res://src/systems/fidelity_tests/sky_pole_review.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/sky-pole-review-r1/session \
  --qa-render-size=1280x720 \
  --sky-pole-output=/private/tmp/singapore-fidelity/sky-pole-review-r1/captures \
  --sky-pole-baseline=/private/tmp/singapore-fidelity/sky-pole-review-r1/baseline.gdshader \
  --sky-pole-baseline-ref=5ec183a
```

Default expected source hashes are the before/after hashes above; explicit `--sky-pole-baseline-sha256=` and `--sky-pole-candidate-sha256=` options support another deliberately identified source pair. Equal hashes, wrong identities, unsafe/symlink paths, an existing report/save, conflicting controllers and save-path overrides are refused. No image/report is overwritten. All output and baseline paths must stay within a normalized `/private/tmp/singapore-fidelity/sky-pole-review-*/` run.

An internal monotonic 120-second limit begins **after** synchronous production-world startup. The root wrapper remains responsible for a total process deadline. Headless use exits 2 with `rendered=false`, no world instantiation and no visual-success claim. Successful PNG writes mean only that acquisition completed; shader correctness, final image quality, radiance convergence, frame rate, human play and the broader Singapore/MBS goal remain unaccepted until parent inspection.

The report records actual timestamps, source/code/PNG hashes, camera poses, viewport and image dimensions, uniform/sky settings, warmups and explicit scope limits. No engine or GPU run was performed by the helper's author. Parsing and runtime behavior are pending root verification.

## Actual A/B R1 failure and uniform-default correction

Root ran the first rendered helper. It exited1 at setup check5, with no fatal engine errors, zero images and`rendered=false`. Its actual report contains only three nonnull material values: `zenith_color`, `cloud_coverage` and `horizon_cool`. The other seven entries were unset material overrides, not evidence that their declared shader defaults were absent or that the sky had passed/fail visual review. The failed report remains under the original private run directory.

The helper now reflects **every** material uniform with [`Shader.get_shader_uniform_list(false)`](https://docs.godotengine.org/en/stable/classes/class_shader.html#class-shader-method-get-shader-uniform-list). For each actual Shader RID it queries [`RenderingServer.shader_get_parameter_default`](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-shader-get-parameter-default), records that default and uses it whenever the material override is null. No unknown/null value is skipped or replaced by a guessed constant. The complete ten-uniform contract, finite supported values, interface, declared defaults and effective starting values must match. Then all effective values are explicitly applied to each phase and compared again. The report distinguishes material overrides from renderer-provided defaults. Any unresolved field still fails before capture.

`helper-r1-diagnosis.json` binds this source correction to the actual failed report and records the revised helper hash. A new run directory is required for the rerun; R1 evidence is not overwritten. No engine was launched by this worker.

Root separately observed that the actual helicopter R2 upward view still has radial white cloud streaks, despite57/57 control gates. The frozen shader remains75e46d5f; mathematical continuity is not accepted visual success. Matched real A/B frames and a fresh visual critic remain required before accepting or revising that shader.
