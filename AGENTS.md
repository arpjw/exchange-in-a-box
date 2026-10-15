# Exchange in a Box agent notes

- Keep `lib/Book`, `Engine`, `Risk`, `Journal`, and research modules deterministic. Time, IO, and concurrency belong at adapters and binaries.
- Run `dune runtest` after focused changes. Run `bash scripts/stress.sh` before calling a milestone verified. Reproduce any failing seed, fix the cause, add a regression check, and rerun the gate.
- Treat all model results and scenario outputs as synthetic. State which claims are mechanical invariants, which are simulation observations, and which remain hypotheses. Do not infer trading profitability or empirical market fit.
- The tracked paper artifact is `paper/exchange_in_a_box.pdf`. Its LaTeX source remains local at `paper/exchange_in_a_box.tex` and is intentionally ignored by Git. Edit that existing source in place, compile it in the Codex editor, export the PDF, and inspect its rendering before committing a paper update. Never delete the local source to satisfy a clean Git status.
- The current journal persists `Engine` commands and books only. `Risk` account state and `Gateway` workers are in memory. Preserve this distinction in code and documentation until durable risk recovery is implemented and tested.
- Keep the project free of broker or live-exchange order entry. The router and experiments operate on synthetic or offline state.
- After changing pure core code or the tracked PDF, run `bash scripts/build-web.sh` and commit the updated `web/public/bridge.bc.js` or `web/public/paper.pdf`. The static Vercel site serves only `web/public`; browser view state is JavaScript, while market transitions remain in OCaml. Run `node scripts/test-web.cjs` and verify the UI in a browser for web changes.
