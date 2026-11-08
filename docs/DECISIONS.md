# Decisions: the Arrow path from Cube Store to Elixir

This log records why the path that carries a Cube result to power_of_three is
shaped the way it is: the Arrow Native client here, and the changes to Cube in
the `borodark/cube` fork that it reads through. It is the only decision log for
this work; the eXMC logs elsewhere on the fleet are unrelated.

Each entry is `## N. Title` followed by bullets: Decision, Rationale,
Alternatives, Assumption (what must stay true for the decision to hold), Status,
and the commits or PRs that carry it. An entry is never rewritten when it stops
holding; it is marked **[SUPERSEDED by N]** or **[EVOLVED]** and a later entry
says what replaced it.

## 1. Speak Cube's Arrow Native protocol directly, and delete ADBC
- Decision: power_of_three talks to Cube's Arrow Native port over `:gen_tcp`
  (`packet: 4`) with its own codec, and the ADBC transport is removed rather
  than kept as a fallback.
- Rationale: ADBC was four layers (C driver, NIF, Elixir binding, Explorer) to
  carry Arrow IPC bytes from a socket to a frame; the protocol is a handshake,
  auth, a query and schema/batch/complete/error frames, each payload a
  self-contained IPC stream. About 8x faster at 26k rows than the best ADBC path.
- Alternatives: ex_arrow's ADBC layer (forwards only five options, so the Cube
  driver can't be told where Cube is); keeping ADBC as a second transport.
- Assumption: the Arrow Native protocol stays small and versioned (it now has
  protocol version 2, with an optional user).
- Status: in force. Blog: "The Line Nobody Printed" (October 2026).

## 2. Narrow the Arrow Native PR to the endpoint; no result cache
- Decision: replace cube-js/cube#10297 (105 commits, 9,126 lines: endpoint,
  result cache, matcher, direct mode, Docker/CI changes, a large recipe) with
  `feature/arrow-native-endpoint`: the endpoint alone, reusing the SQL API's
  auth and query path, with no cache.
- Rationale: the #10297 review found the cache keyed on SQL text and database
  only, shared by all connections, so it could return one security context's
  rows to another; and asked for a focused PR. Caching, if proposed again, is a
  separate PR keyed on the security context.
- Alternatives: fixing the cache key inside #10297; Arrow Flight SQL instead of
  a custom protocol (raised in the review; open in #10296).
- Assumption: the SQL API's planner and auth are the right single path for every
  transport, so a fix there reaches Postgres and Arrow clients alike.
- Status: in force. Commits a6d58f2934, ee892f458a.

## 3. The runnable recipe lives with power_of_three, not in Cube
- Decision: the arrow-ipc recipe (start scripts, models) stays in
  power-of-three-examples; the Cube endpoint PR carries none.
- Rationale: the review asked for minimal recipes; the example's purpose is
  the Elixir client.
- Status: in force.

## 4. Fix Cube's Postgres endpoint for Postgrex upstream, in separate PRs
- Decision: make Postgrex work against cubesql by fixing cubesql (type
  information in `pg_type`, outer joins without equi-join keys, errors sent
  before Sync, TCP_NODELAY), each as its own upstream PR, rather than working
  around them in the client.
- Rationale: each defect affects every client that behaves like Postgrex; a
  workaround in one client hides it from the others.
- Alternatives: a Postgrex-specific bootstrap shim in power_of_three.
- Status: open upstream: cube-js/cube#12478 with cube-js/arrow-datafusion#232
  (merge order: #12478, #232, then a pin update), plus
  `fix/pg-error-before-sync`, `perf/cubesql-pg-nodelay`,
  `fix/cubesql-outer-joins-without-keys`.

## 5. Measure before changing the conversion path; order the work 1, 4, 3
- Decision: of the four items found by the 1.35M-row race_bench rollup
  (1 a buffered fallback for streamed queries on Cube Store, 2 a truncation
  notice, 3 streaming from Cube Store, 4 Arrow passthrough), do 1 first (it
  fixes a bug alone), then 4, then 3; and measure 4 before building it.
- Rationale: 4 helps one-shot queries today and 3 reuses it.
- Status: **[EVOLVED]** the measurement found a larger cost than the conversion
  (entry 6), and 1 was superseded by 3 (entry 10).

## 6. Compact each batch on the Arrow Native endpoint
- Decision: the endpoint sends each slice of a result with only its own rows'
  buffers.
- Rationale: every slice carried the whole result's buffers: 2,446 MB on the
  wire for the 1.35M-row rollup, 117 MB after. This, not the value conversion,
  was most of the one-shot time (18.2 s to 5.4 s with passthrough as well).
- Status: in force. Commit ee892f458a.

## 7. Cross Arrow versions by IPC, not FFI
- Decision: Cube Store (arrow 54), the orchestrator (arrow 58) and cubesql
  (arrow 13, forked DataFusion) exchange results as IPC bytes; cubesql decodes
  them with its own arrow.
- Rationale: IPC is the stable contract between versions; FFI ties memory
  layouts and lifetimes across three crates' versions.
- Alternatives: FFI (held in reserve); moving cubesql off arrow 13 (would
  remove the bridge, a much larger project).
- Assumption: arrow 13 reads what newer writers produce. It does not for some
  types (Decimal256, dictionaries, timestamps with a time zone): those frames
  fall back to the orchestrator's values.
- Status: in force.

## 8. Arrow passthrough behind a flag, equal to the old path by construction
- Decision: `CUBESQL_ARROW_PASSTHROUGH` (default off) lets cubesql build its
  batch from Cube Store's Arrow; the batch must equal what the JSON/text path
  builds from the same rows, value for value, including its parse rules
  (text semantics: `"1.5"` into an integer column is NULL with a warning,
  integers keep every digit).
- Rationale: a performance change must not change results; the equivalence
  tests compare both paths per source and target type. They caught integers
  past 2^53 losing precision through an f64 fast path.
- Alternatives: on by default (question 2 for the maintainers in #10296).
- Status: in force. Commits on `perf/arrow-passthrough` (one-shot) and
  `feat/sql-api-arrow-stream` (stream).

## 9. Stream from Cube Store as self-contained IPC frames, by opt-in
- Decision: `HttpQuery` gains `stream: bool = false`; a client that sets it
  gets the result as several `HttpQueryResultArrow` frames, each a
  self-contained IPC stream, the last with `is_last`. Frames are about 8 MB
  (the first 4,096 rows, then adaptive), at most two in flight per query; the
  permit is released when the WebSocket writer drops the frame.
- Rationale: the schema already defined `is_last` ("clients should implement
  it"); opt-in keeps old drivers working, and an old Cube Store simply sends one
  frame. Backpressure bounds Cube Store's memory per query to two frames.
- Status: in force. `feat/cubestore-stream-frames` (2ef738ae81).

## 10. A started stream is never resent; the fallback is retired
- Decision: the driver keeps a streamed message registered until `is_last`; on
  reconnect a stream that has already delivered frames fails with a
  ConnectionError instead of being resent. The external queue gets
  `streamSkipQueue`, which replaces item 1's buffered fallback.
- Rationale: a resent stream would deliver frames twice. The fallback buffered
  the whole result in Cube's memory, which is the problem
  streaming exists to remove.
- Status: in force. `feat/cubestore-driver-stream` (fb1af11b86). Item 1
  (21e9eb86e3) was never pushed. **[SUPERSEDES 5's item 1]**

## 11. The router still collects; router streaming is deferred
- Decision: only the HTTP layer streams; the Cube Store router still collects
  the workers' result before the first frame is sent.
- Rationale: the select path goes through the result cache as rows
  (`QueryResult::Frame`) and `route_select` collects; a final sort materializes
  anyway. Streaming the router is a separate change.
- Consequence: at 1.35M rows about 3.2 s of 4.2 s is before the first batch.
- Status: open; the next gain on large sorted results.

## 12. No cancel message to Cube Store
- Decision: a reader that stops early destroys its stream and later frames are
  dropped; Cube Store is not told to stop.
- Rationale: the protocol has no cancel; adding one is its own change.
- Status: known limit.

## 13. power_of_three streams lazily; ex_arrow for batches, optional
- Decision: `CubeNativeClient.stream/2` returns a lazy stream of IPC payloads
  read from the socket as consumed; `stream_record_batches/2` decodes each
  with ex_arrow. A server error raises and leaves the client usable; a stream
  stopped early, or a broken connection, closes the client. ex_arrow is an
  optional dependency, used for `ExArrow.RecordBatch` only.
- Rationale: TCP holds the server back while the reader is busy, so a large
  result is never held whole; unread frames would otherwise be read by the next
  query as its own (the pool bug of entry 1's blog).
- Alternatives: Explorer per batch (still available via `load_ipc_stream`);
  ex_arrow's DataFrame bridge (re-serialises to IPC, the reason entry 1 left
  ex_arrow out).
- Status: in force. power_of_three `feature/native-stream` (0439013).
  **[EVOLVED]** entry 1 chose Explorer and no ex_arrow; batches are now the
  unit, and ex_arrow reads them without the bridge.

## 14. Verify end to end, not only against mocks
- Decision: a change to the result path is done when the real stack returns
  the same results as stock Cube for the trader and race queries, both with the
  flag on and off, not when unit tests pass.
- Rationale: PR (e)'s unit test mocked `getRawData()` as rows; on a native
  result it is a handle, so stream mode without passthrough returned 0 rows.
  Only the end-to-end comparison found it. The mock now behaves like the real
  result.
- Status: in force. Results 2026-11-08: all 7 queries SAME on and off; 1.35M
  rows in 14.6 s (off) and 4.2 s (on).

## 15. Cube stays off the trader's risk path; the record comes first
- Decision: the paper trader's Risk tab (pymc/exmc/docs/PLAN_RISK_UX.md, R2)
  does not read correlations, panels or moment sums from Cube. Its nightly
  daily-closes job runs in the trader's own jail, as the plan says, and the
  numbers are computed in memory. Cube's role is rolling up durable tables off
  the trading path: profit by instrument from fills, posterior and equity
  history, S60-versus-blend drift, replay panels.
- Rationale: trading must keep running when super-io is down, and Cube runs
  there with its data under /tmp; about 90 instruments plus 14 factor proxies
  on daily closes is a few hundred kilobytes a night, so moment sums in a
  rollup answer a scale the trader does not have. The Risk tab is advise-only:
  with any outside store down it shows its data age and never blocks a trade.
- Alternatives: jobs 1-3 of the first assessment (a daily returns panel,
  per-pair moment sums, cross-sectional sums served by Cube to the live path).
- Assumption: the universe stays near 100 instruments for the live path; the
  instrument discovery screen (about 2,229 symbols over 840 days, ~15 MB) stays
  a batch job.
- Open (the user's decisions): Postgres and Cube on asus at all; whether live
  sizing moves to daily returns; a tick sink; a staleness threshold for
  sizing; shrinkage in the live held-book matrix.
- Status: recommended 2026-11-08, from the trader session's answers.

## 16. The missing tables: fills with prices, and adjusted daily closes
- Decision: the first tables worth keeping are a record of fills with their
  prices, and daily closes adjusted for splits, keyed by session date with the
  boundary per asset class (US close for equities, 17:00 New York for FX, UTC
  for crypto; NYSE sessions for cross-asset panels).
- Rationale: the order ledger has no fill prices, so live P&L cannot be
  attributed per instrument; unadjusted Alpaca bars put log returns up to 2.3
  into the data on split days (NVDA, AVGO, NFLX, LCID), and the replay had to
  splice in adjusted closes. These are what a rollup would be built from.
- Staleness, recommended: a daily panel is stale when it lacks the last
  completed session plus a few hours' grace (22:00 New York for US equities,
  18:00 New York for FX); every number shows its age.
- Status: recommended; owned by the trader session.

## 17. Postgres and Cube run on asus, in jails (the user, 2026-11-08)
- Decision: a `pg` jail (PostgreSQL 16) and a `cube` jail (Cube Store and Cube)
  on asus, beside the trader jail, on their own ZFS datasets and on CPUs apart
  from the trader's cores and their SMT siblings. Plan:
  zed `specs/asus-data-jails-plan.md`.
- Rationale: the shop keeps trading with super-io down; a store the trader
  reads must live where the trader lives.
- **[EVOLVED]** 15: Cube was kept off the risk path because it ran on
  super-io under /tmp. On asus it can serve the daily panel to live sizing;
  trading still never blocks on it (entry 21).

## 18. FreeBSD native, no Linux userland (the user, 2026-11-08)
- Decision: Cube Store and `@cubejs-backend/native` are compiled for FreeBSD
  15 (on mac-247, same release as asus); Node and Postgres from pkg.
- Alternatives: the Linux builds under asus's `linux_base-rl9` (index.node
  needs glibc 2.34 and would load; cubestored needs 2.39 and would need a
  Rocky 9 rebuild). Rejected by the user.
- Assumption: Cube Store and cubesql build on FreeBSD with their pinned
  toolchains (nightly-2025-08-01, 1.98.1). Unverified until the builds pass.

## 19. Live sizing moves to daily returns (the user, 2026-11-08)
- Decision: the correlation and volatility inputs to live sizing come from a
  daily, session-aligned returns panel, not from the 60-second positional
  windows.
- Rationale: the documented practice is daily at the fastest; the positional
  windows have no timestamps and mix frequencies after a restart.
- Owner: the trader session.

## 20. A tick sink and a fills record (the user, 2026-11-08)
- Decision: MarketFeed's accepted quotes are written to `ticks`, and fills with
  their prices to `fills`, in the `pg` jail; batched, and spooled locally when
  Postgres is away so trading never waits on it.
- Rationale: nothing seen or paid was kept; per-instrument P&L could not be
  attributed (entry 16).
- Owner: the trader session.

## 21. A staleness threshold for sizing (the user, 2026-11-08)
- Decision: sizing treats the daily panel as stale when it lacks the last
  completed session plus a grace period (recommended 22:00 New York for US
  equities, 18:00 New York for FX), and shows the panel's age.
- Open: what sizing does with a stale panel (no size-ups, or the in-memory
  fallback) is not yet stated.
- Owner: the trader session.

## 22. Shrinkage in the live held-book matrix (the user, 2026-11-08)
- Decision: the held-book correlation used by sizing is shrunk, not plain
  Pearson. The Risk tab's structured blend (0.4 S60 + 0.6 factor-implied,
  next-60-day RMSE 0.204 against 0.240 for S60) is the validated candidate;
  Ledoit-Wolf exists in `Exmc.Trading.Portfolio.Covariance`. Duplicate flags
  keep using the sample correlation (the blend shrinks true duplicates).
- Owner: the trader session.
