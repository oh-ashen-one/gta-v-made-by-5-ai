# Preliminary packaged candidate R1

Export succeeded and local ad-hoc signature strict verification succeeded; exact PCK unchanged by signing. This candidate predates final test/QA fixes. Headless packaged regression293/296, three failures preserved. Source suite296/296. All3 failures contain source-text assertions against compiled GDScript (characters-T2 near_hide; perf-T readback/probe/blur; perf-T reseed caps). Independent test builder is replacing these with runtime behavioral checks, not silently skipping them. Final package and actual visual launch still pending.
