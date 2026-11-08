# Research: moving Cube's Node part to Elixir

**Written:** 2026-11-08, from the Cube/Arrow session. **Status:** research only; nothing
decided. **Measured on:** the composite `cube-stream-integ` (Cube 1.8.20 plus the
stream PRs d/e/f), line counts excluding tests.

## 1. What "the Node part" is

| Package | LOC | What it does | Port? |
|---|---:|---|---|
| `cubejs-schema-compiler` / `compiler` | 10.5k | loads YAML/JS models, transpiles member SQL, builds the cube evaluator and join graph | **yes**, YAML only |
| `cubejs-schema-compiler` / `adapter` | 14.4k | legacy SQL planner (`BaseQuery`) + 30 dialect subclasses | **no**: Tesseract replaced it (§2) |
| rest of schema-compiler | 17.3k | compilers for views, access policies, hierarchies, Jinja/Python models | partly |
| `cubejs-api-gateway` | 7.7k | REST/GraphQL/WS, query normalisation, auth, `/v1/meta`, `/v1/load`, `/v1/sql` | **yes**, REST + SQL first |
| `cubejs-query-orchestrator` | 7.1k | query queue, result cache, pre-aggregation build/refresh, Cube Store queue | **yes**; OTP's home ground |
| `cubejs-server-core` | 6.4k | compiler API per tenant, context, refresh scheduler | **yes** |
| `cubejs-backend-shared` | 5.4k | env config, helpers | as needed |
| `cubejs-base-driver` + postgres + cubestore drivers | 4.4k | driver contract, Postgres, Cube Store | Postgrex; Cube Store over its existing protocol |
| `cubejs-server` | 1.2k | CLI and HTTP server boot | Phoenix/Bandit app |

The Rust side stays Rust: cubesql (Postgres and Arrow Native wire, DataFusion rewrite),
Tesseract (`rust/cube/cubesqlplanner`, 104k LOC), `cubeorchestrator` (result transform),
Cube Store. The port is the ~40k lines that sit **between** them.

## 2. The finding that sets the shape: Tesseract is host-agnostic already

- Tesseract is the default SQL planner (`CUBEJS_TESSERACT_SQL_PLANNER`, repo CLAUDE.md);
  `BaseQuery` and its dialects are the deprecated fallback. Porting the 14k-line legacy
  planner would port dead code.
- Tesseract reads the model through `cube_bridge` (2.1k LOC of traits:
  `CubeDefinition`, `MeasureDefinition`, `MemberSql`, `JoinGraph`, `Evaluator`,
  `SqlTemplatesRender`, `DriverTools`...). Those objects are reached through
  `cubenativeutils`, which is generic over an `InnerTypes` trait
  (`NativeContext`, `NativeObject`, `NativeStruct`, `NativeFunction`, `NativeString`).
- **`cubesqlplanner/src` has zero `neon::` uses.** The only host implementation is
  `cubenativeutils/src/wrappers/neon` — **1,767 lines**. A Rustler implementation of
  the same traits lets Tesseract run inside the BEAM, with Elixir structs and funs
  standing in for the JS cube objects.
- That turns "port the planner" (impossible to keep up with) into "port one adapter of
  ~2k lines and keep tracking upstream Tesseract unchanged".

The second seam is cubesql's `TransportService` trait (`meta`, `sql`, `load`,
`load_stream`, `pre_aggregation_matches`, `can_switch_user_for_session`,
`log_load_state`). Today `@cubejs-backend/native` implements it by calling JS; cubesqld
ships an `HttpTransport` against Cube's REST API, but its `sql()` is `todo!()` and it has
no streaming, so it is a smoke-test path, not a product one. An Elixir host implements
the trait in Rust over Rustler calls into Elixir, like `native` does over Neon.

## 3. Target shape

```
          Postgres wire / Arrow Native          REST /v1/{meta,load,sql}
                     │                                   │
   ┌─────────────────┴───── BEAM node ───────────────────┴──────────┐
   │ cubesql (Rust NIF/port)  ◄─TransportService─►  Gateway (Elixir)│
   │ Tesseract (Rust NIF)     ◄─cube_bridge via Rustler InnerTypes─►│
   │                                    Model compiler (Elixir)     │
   │ Orchestrator (Elixir): queue, cache, pre-agg refresh, per-tenant│
   └──────────┬──────────────────────────────────────┬──────────────┘
          Postgrex                       Cube Store (HTTP/WS, streamed frames)
```

- **Model compiler.** YAML models only (no JS model files: those need a JS engine).
  `{CUBE}` / `{other_cube.member}` references become Elixir funs returning SQL strings,
  which is what `MemberSql` asks for. power_of_three's `cube_schema.ex` already holds
  cube definitions in Elixir; it becomes a source of the same structs. Jinja-templated
  models are a later milestone (kung_phoo's hand-ported Nunjucks, K4, is the precedent).
- **Orchestrator.** One GenServer per data source queue, ETS result cache, a
  `Task.Supervisor` for pre-aggregation builds, the refresh scheduler as a timer
  process. Supervised restart is where OTP buys the most over Node's in-process queue.
- **Streaming.** The Arrow path built in PRs (d)-(f) carries over: Cube Store frames →
  cubesql `arrowChunk` → client, with backpressure through the transport. In a BEAM
  host the frame can go to an Elixir consumer without a socket hop at all.
- **Drivers.** Postgrex for Postgres; Cube Store through the existing protocol. Other
  databases stay out (§6).

## 4. How to keep it honest (from kung_phoo)

The kg's closest precedent is kung_phoo, the Elixir port of promptfoo
(`doc:kung_phoo/PLAN.md`, decisions K1-K23): "dump fixtures first, then make them
pass"; goldens recorded from the upstream Node program only; a drop-in contract as the
interface; PropCheck generators for JS-shaped values; a `mix check` gate. Applied here:

1. **Goldens from Node Cube.** For the trader_bench and race_bench models: `/v1/meta`
   JSON, `/v1/sql` output per query, `/v1/load` results, and the cubesql SQL-API results
   (the 7 Arrow IPC baselines in `pt_ref` already exist; all 7 matched on the FreeBSD
   build today).
2. **SQL equality first, rows second.** Tesseract is shared, so the Elixir host must
   produce byte-identical SQL for the same model and query; any diff is a bridge bug,
   localisable to one `cube_bridge` method.
3. **Cache keys.** Cube keys caches and pre-aggregation tables on `JSON.stringify`-shaped
   values; kung_phoo needed `KungPhoo.JS.stringify` (K5) for exactly this. Reuse it, or
   pre-aggregation table names will not match a Node Cube sharing the same Cube Store.

## 5. Milestones

| # | Deliverable | Gate |
|---|---|---|
| M0 | Spike: Rustler `InnerTypes` for `cubenativeutils`; Tesseract builds as a NIF and plans one query from a hand-built Elixir cube | SQL equals Node's for one query |
| M1 | YAML model compiler → `cube_bridge` objects; `/v1/meta` and `/v1/sql` | meta and SQL goldens for both models |
| M2 | `/v1/load` over Postgrex with an ETS cache; no pre-aggregations | load goldens |
| M3 | `TransportService` over Rustler; cubesql in the BEAM node | the 7-query Arrow check SAME |
| M4 | Orchestrator: queue, Cube Store pre-aggregation builds, refresh scheduler | rollups for the asus `trader_store` panel build and refresh |
| M5 | Streamed Arrow frames into Elixir consumers without a socket hop | stream bench vs Node path (14.6 s off / 4.2 s on, 1.35M rows) |

M0 is the go/no-go: about the size of the Neon adapter, and it settles the two real
unknowns (§7).

### M0, first half: done 2026-11-08 — Tesseract without JS gives Node's SQL

Tesseract's own tests carry a pure-Rust model host (`src/test_fixtures`, 12.7k LOC:
`MockSchema::from_yaml`, mock `cube_bridge` objects, mock Postgres/Cube Store driver
tools). The spike (`cube-stream-integ` branch `spike/tesseract-host`, commit
`58bd78f1c7`, `tests/node_parity.rs`) fed it:

- the trader model (`posteriors.yaml`, `race_results.yaml`, unchanged);
- `sqlTemplates()` dumped from Node's `PostgresQuery` (174 templates) and
  `CubeStoreQuery` (159) as JSON data;
- 7 REST queries, compared with Node Cube's `/v1/sql` for the same model (the FreeBSD
  build on mac-247): 5 answered from the `by_symbol_hour` rollup (Cube Store dialect),
  2 missing it (Postgres dialect: week granularity with time-zone conversion, `ILIKE`,
  `notEquals` with `IS NULL`, `$n` params reused).

**Result: 7/7 byte-identical SQL.** What the host had to do itself, i.e. what an Elixir
host owns:

1. **Pre-aggregation table names.** Tesseract emits `{cube}__{pre_agg}__usage_{n}`;
   the host substitutes the table (`dev_pre_aggregations.posteriors_by_symbol_hour` in
   dev mode, versioned names in production — the orchestrator's job).
2. **REST query normalisation:** the default `LIMIT 10000`, the `order` map to a list.
   Default ordering came out of Tesseract unaided.
3. **Parameter formatting.** One gap: Node binds Postgres date params as
   `2026-10-01T00:00:00.000Z` (`BaseQuery.timestampFormat`, `[Z]`); the mock's UTC
   `in_db_time_zone` returns them without `Z`. Only the bound values differ, not the SQL.
   Driver tools are code, not data, and must follow Node's per-dialect behaviour; the
   goldens catch the gaps.

Templates turned out to be pure data (Jinja strings, minijinja on the Rust side), so a
dialect for the Elixir host is a JSON file plus a small `DriverTools` port (the
mock's is 312 lines for Postgres + Cube Store).

### M1: started 2026-11-08 — see tesseract_ex `docs/M1.md`

Compiled models on a planner thread each (1.7 ms per query); a golden harvester that
plans in-process through Node's own compiler (equal to live `/v1/sql`); over
Tesseract's 91 Node-compilable fixture models and 5,412 generated queries, **82.5%
agree and 96.1% produce equal SQL**. Everything left is in the borrowed test host:
date-param formatting (739), interval spelling (112), multi-stage column order (87),
reference resolution (7), and 14 models Node's compiler rejects. Next: the owned model
crate, gated on that comparison.

### M0, second half: done 2026-11-08 — the same SQL from Elixir

`learn_erl/tesseract_ex` (local repo, commit `ec6cc2e`): a Rustler NIF
(`TesseractEx.Native.plan/4`, dirty CPU) over `cubesqlplanner` with a new
`host-fixtures` cargo feature that builds the test model host as a library
(`cube-stream-integ` `96a298840d`: the feature, `pub mod test_fixtures`, one
test-only builder ungated). The host's jobs are Elixir (`TesseractEx.sql/4`: REST
normalisation, pre-aggregation naming by regex).

- **7/7 SQL equal to Node Cube** from `mix test` (`test/parity_test.exs`); params equal
  except the `Z` gap above.
- A malformed query returns `{:error, _}`: the test host panics on bad input, so the
  NIF catches the unwind.
- **3.4 ms per call**, including re-parsing the YAML model and 333 templates on every
  call; a real host parses the model once per compile.
- Nothing calls back into Erlang during planning, so the callback-threading risk (§7)
  is avoided on this path, not solved: models whose member SQL is JS code stay out.

**What M0 does not show:** the test host is test code (it panics on bad input, and its
YAML reader may lag Cube's compiler on features the trader model doesn't use: views,
access policies, multi-stage measures, custom granularities); the param formatting gap;
production pre-aggregation names (versioned, from the orchestrator). M1 replaces the
mock host with an owned one (or hardens it upstream) and widens the goldens to
Tesseract's own YAML fixtures, compared against Node.

## 6. Out of scope, deliberately

The legacy `BaseQuery` planner; JS model files; GraphQL; the Playground/dev UI; the 30
non-Postgres drivers; Cube Cloud features. Each can come later behind the same seams.

## 7. Risks and unknowns

- **Callback threading.** Tesseract calls back into the host synchronously while
  planning (member SQL, templates). Neon does this on the JS thread. Under Rustler the
  planner must run on a dirty scheduler and call Elixir funs; a NIF cannot call back into
  Erlang synchronously, so either the model is pre-materialised into Rust-side values
  before planning (preferred: member SQL from YAML is data, not code) or the planner runs
  in a thread that messages an Elixir process and blocks. M0 decides.
- **Upstream churn.** `cube_bridge` traits change with Tesseract releases; the adapter
  must track them. Small surface, but continuous work.
- **Tracking the JS semantics we keep.** Query normalisation, time-dimension and
  granularity rules, and security-context handling live in the gateway and compiler; the
  goldens are the guard.
- **Mixed fleets.** A Node Cube and an Elixir Cube sharing one Cube Store must agree on
  pre-aggregation table names and partition keys (§4.3).

## 8. Gaps: what this plan underplans (reviewed 2026-11-08, after M0)

M0 proved the easiest seam. Ranked by risk, what the milestones above give a line or
nothing:

1. **SQL API push-down needs a small JS evaluator.** cubesql sends member expressions as
   `{cubeParams, sql}` (`wrapper.rs` `SqlFunctionExpr`, `PatchMeasureDef`), and Node turns
   `sql` into a JS function (`api-gateway/src/member-expression-security.ts`,
   `Function(...cubeParams, ...)`). The syntax is restricted, so an Elixir parser is
   feasible, but no milestone has it. M0 tested REST queries only; Postgres-wire queries
   that push down, including the 7-query Arrow check, take this path.
2. **Pre-aggregations are one row (M4) and most of the work.** Versioned table names
   (hashes of SQL, structure version and refresh-key result, computed exactly as JS
   does, or Node and Elixir hosts cannot share a Cube Store); partitions and build
   ranges; refresh-key evaluation; incremental refresh; loading rows from Postgres into
   Cube Store with indexes. Recent Cube also uses Cube Store as its queue and cache
   (cachestore); §3's ETS cache breaks as soon as Node and Elixir share a Cube Store.
3. **The model host is borrowed test code with no owner.** M0 runs on
   `src/test_fixtures` (12.7k LOC), which upstream changes freely. M1 must choose:
   (a) own a Rust model crate (copied, or upstreamed as a feature) tracking the
   `cube_bridge` traits; or (b) a Rustler `InnerTypes` over Elixir data, the §2 idea,
   which brings the callback-threading problem (§7) back for anything that isn't plain
   data. Whether upstream would take a `host-fixtures`-style feature is unexplored.
4. **The model compiler is more than YAML loading.** Jinja and Python in YAML; views
   (join paths, includes/excludes, prefixes); `extends`; `FILTER_PARAMS` and
   `COMPILE_CONTEXT`; access policies; segments; `case` dimensions; multi-stage and
   rolling-window measures; custom granularities; Cube's validation and its error
   messages. Nothing measures how much is needed; the trader model touches almost none.
5. **`/v1/meta` is unspecified.** cubesql builds its schema from `meta()`; the JSON must
   match Cube's client models field for field. No milestone has meta goldens beyond M1's
   mention.
6. **cubesql inside the BEAM is an open architecture choice.** cubesql runs its own
   tokio runtime and listeners. As a NIF, a panic takes down the VM and each `load` into
   Elixir is a message round-trip; as a separate process (cubesqld talking to Elixir over
   a socket) it is safer but needs a new transport. §3 says "Rustler calls" and stops.
7. **Results to Arrow.** cubesql wants record batches. Postgrex returns rows to convert in
   Elixir, or queries run in Rust (tokio-postgres). Type mapping (numerics,
   time-zoned timestamps) decides whether the equivalence checks pass.
8. **Config hooks.** Node's config is JS functions: `checkAuth` and JWT,
   `contextToAppId` with per-tenant compiler caches, `queryRewrite`,
   `scheduledRefreshContexts`. The Elixir surface is not designed.
9. **Per-dialect driver tools.** The `Z` gap (M0) shows each dialect's `DriverTools` must
   follow Node's code, not the test mock.
10. **Goldens and drift.** Seven goldens. Missing: a harvester that runs Node Cube over
    Tesseract's YAML fixtures and Cube's test models, recording `/v1/sql` and `/v1/meta`;
    a rebase cadence as Tesseract moves.
11. **The product question.** The trader needs a few daily-panel rollups, not a full Cube.
    Not weighed: the smallest useful ex_cube — an Elixir model, Tesseract for SQL, run
    directly against Postgres (Postgrex) and Cube Store (its HTTP API), skipping cubesql
    and the orchestrator; a power_of_three backend. Weeks from the spike, against months
    for the full path.

**Recommendation:** make 11 the next milestone; settle 3 now as (a), owning the Rust
model crate; treat 1, 2 and 6 as their own research before committing to the full port.

## 9. Rust or Elixir: what goes where (2026-11-08)

The rule: **rows stay in Rust, next to the store; decisions, names and schedules live
in Elixir.** Rust owns everything whose cost scales with rows. Elixir owns everything
whose size scales with the model, the tenants and time. The boundary is crossed once per
compile, per query or per batch, never per row or per member.

### 9.1 The evidence for the rule

| Measurement | Where | Number |
|---|---|---|
| Rows as Arrow vs as Elixir terms (Postgrex), 5M rows | our stream bench | 14.9 s vs 35.1 s |
| same, 100k-row rollup | conv bench | 183-204 ms vs 378-523 ms |
| Node row materialisation (passthrough off vs on), 1.35M rows | stream mode | 14.6 s vs 4.2 s |
| Term lists vs binaries across a NIF | exmc research log 2026-02-09 | O(elements) vs O(bytes) |
| One coarse NIF call vs ~50 fine ones, with more serialising | exmc D58 (negative result) | the coarse call was 0.4-0.8x as fast |
| Process wrapping in Elixir | exmc EXPERIMENT_RESULTS | invisible above ~100 µs of work |
| Tesseract call from Elixir (release build) | `node_parity_timing` | model parse 0.39 ms, templates 1.28 ms, plan 1.34 ms |

What follows from it:
- **Row decoding is the cost.** Elixir loses 2x by decoding rows into terms; Node
  loses 3.5x the same way.
- **Pay for parsing static inputs once.** Half of today's 3.4 ms planning call is
  re-parsing the model and templates. They belong in Rust as a resource built once per
  compile; a query then costs ~1.3 ms of planning.
- **Make each crossing coarse, and pass binaries.** D58 lost both ways: per-op calls
  cost too much, and so did one call that serialised a lot. Arrow IPC and JSON binaries
  cost O(bytes). Refcounted binaries above 64 bytes pass between BEAM processes without
  a copy.

### 9.2 Rust: close to the data

| Part | Why Rust | Today in Cube |
|---|---|---|
| Result path, Cube Store → client | Arrow frames go through as bytes; Elixir consumers take IPC binaries into Explorer/Nx without making rows | PRs (d)-(f): `arrowChunk` passthrough |
| `/v1/load` JSON from Arrow | per-row formatting | Cube already moved this out of JS: `rust/cube/cubeorchestrator` `query_result_transform.rs` |
| **Pre-aggregation loader**, source → Cube Store | the biggest serialise/deserialise sink in a refresh: for Postgres, Cube pulls rows through Node as JS objects, re-encodes them as CSV (`CubeStoreDriver.importStream`, `csv-write-stream`) and uploads that. A Rust loader streams Postgres `COPY` out into Cube Store's import, never as values; Elixir sends the job and receives progress | JS |
| cubesql (Postgres wire, Arrow Native, DataFusion rewrite) | parses and rewrites per query; holds the client sockets | Rust |
| Tesseract planning **with the model held in Rust** | called per member during planning (`cube_bridge`, `DriverTools`): fine-grained calls that must not cross (D58) | Rust, model in JS (Neon) |
| Member-expression parsing for SQL push-down (§8.1) | arrives from cubesql (Rust) and feeds the model's member SQL (Rust): parsing it in Elixir would be a Rust → Elixir → Rust trip | JS (`Function(...)`) |
| Per-dialect driver tools | called inside planning | JS |
| Aggregation itself | in the store: Cube Store's rollups compute the per-pair moment sums (zed plan §5); the 90×90 matrix maths on top is small and lives in Elixir | — |

### 9.3 Elixir: the model, the policy, the schedule

| Part | Why Elixir | Replaces |
|---|---|---|
| **Model DSL** (`cube :posteriors do measure :count ... end`) | macros check references at compile time (`@before_compile`, as in zed's DSL), derive cubes from Ecto schemas (power_of_three already does), and generate repeated cubes with ordinary code; output is one model IR, sent to Rust as a single binary per compile | YAML plus Jinja/Python templating, runtime Joi validation |
| **Query DSL** | Ecto-style macros compile to the REST query map, with defaults normalised at compile time | the api-gateway's runtime normalisation |
| `/v1/meta` | derived from the IR; sent to cubesql once per compile as JSON | schema-compiler's meta |
| Gateway, auth, security context, `queryRewrite`, `contextToAppId` | config hooks become functions and behaviours, not JS callbacks | cube.js config |
| **Orchestrator** | queue, dedup, refresh scheduler, partition and build-range planning, retries, supervision; each tenant's compiled model a Rust resource owned by a GenServer; refresh workers spread over the fleet's BEAM nodes. Data never passes through it | query-orchestrator, server-core |
| Pre-aggregation names and versions | small inputs, but the hashes must match `JSON.stringify` (kung_phoo's `JS.stringify`, K5) so Node and Elixir can share a Cube Store | JS |
| Dialect template sets | JSON data (M0); loaded and versioned by Elixir, handed to Rust once | per-dialect `sqlTemplates()` |
| Consumers (the trader's panel reads) | Arrow binaries in, Nx/Explorer maths | — |

### 9.4 Boundary rules

1. **Once per compile:** the model IR, dialect templates and meta go to Rust as
   binaries, and come back as a resource handle. Tesseract's `cube_bridge` returns `Rc`
   (80 sites), so the compiled model cannot be `Send` and cannot be a `ResourceArc`;
   instead it lives on a thread of its own and the resource holds a channel to it
   (tesseract_ex M1 step 1: 1.7 ms per query, threads exit with the last reference).
2. **Once per query:** a JSON query in; SQL, params and pre-aggregation usages out
   (about 1.3 ms of planning, on a dirty CPU scheduler, with the unwind caught).
3. **Once per batch:** Arrow IPC binaries, never lists of row terms.
4. **Crash isolation by lifetime.** Short, pure calls (planning) run as NIFs.
   Long-running Rust (cubesql's listeners, loaders) runs as OS processes or ports that
   Elixir supervises, so a Rust panic does not take the node down (§8.6).

This answers part of §8.6: cubesql runs as a separate process, with the transport per
query.

## 10. Where it pays

For the trader store (zed `specs/asus-data-jails-plan.md`): the `cube` jail would run a
BEAM release instead of Node 22 plus `index.node`, so one runtime on asus, supervised;
the trader's reads of the daily panel (D19-D21) could come over distribution or in-node
instead of Arrow Native over TCP. It does not change the D15 conclusion that Cube buys no
latency for sizing: what it removes is a runtime, not a hop that matters.

## 11. Today's evidence this rests on

- Native FreeBSD Cube on mac-247: `cubestored` + Node 22 + FreeBSD-built `index.node`,
  7/7 queries SAME against the Linux baselines (posterior_hour 178,258 rows ...
  race_assertions 1,345,325). Workaround needed: `CUBESTORE_SELECT_WORKERS=0`; the
  worker pool's ipc-channel handshake panics on FreeBSD (`respawn.rs:140`, sending an
  `IpcSender` over the socket). Open bug, separate from this research.
