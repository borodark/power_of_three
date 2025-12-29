# Changelog

## [0.1.4] - 2025-12-26

### Added

#### Features
- **SQL Keyword Collision Detection** - Automatically detects and warns when `sql_table` names collide with SQL keywords (e.g., "order", "user", "group"). Provides actionable suggestions to use schema-qualified names (`public.order`) to prevent SQL errors.
  - New functions: `is_sql_keyword?/1`, `is_schema_qualified?/1`, `validate_sql_table/2`
  - Tracks 50+ SQL keywords and Cube.js reserved keywords
  - Helpful warning messages with solutions

#### Testing
- **HTTP vs Arrow Performance Test Suite** (809 lines)
  - 11 comprehensive test scenarios
  - Query sizes from 200 to 50K rows
  - Column widths from 2 to 8 columns
  - Cache performance validation
  - **Result:** Arrow IPC is 25-66x faster than HTTP API

- **Pre-aggregation Routing Tests** (399 lines)
  - Validates query rewriting logic
  - Tests granularity matching (day, month, year)
  - Pre-aggregation selection verification

- **Real-world Cube Tests** (430 lines)
  - Comprehensive tests for mandata_captate cube
  - Time dimension query patterns
  - Aggregation and filter combinations

- **SQL Keyword Safety Tests** (237 lines)
  - Validates keyword collision detection
  - Tests schema-qualified name handling
  - Warning message verification

- **CubeStore Metastore Tests** (240 lines)
  - Metastore integration validation
  - Pre-aggregation discovery tests

- **Comprehensive Performance Tests** (376 lines)
  - End-to-end performance benchmarking
  - Query generation and execution timing
  - Cache warm-up and iteration testing

**Total Test Coverage Increase:** +2,491 lines (625% increase)

#### Documentation
- **cache_performance_impact.md** (251 lines)
  - Documents dramatic Arrow IPC performance improvements
  - Cache impact analysis: 3-89x speedup
  - Arrow vs HTTP comparison: 25-66x faster
  - Detailed benchmark tables for all test scenarios

- **PREAGG_GRANULARITY_IMPACT.md** (179 lines)
  - Pre-aggregation granularity performance study
  - Day vs month vs year granularity comparison
  - Query routing logic documentation

- **LARGE_SCALE_TEST_RESULTS.md** (208 lines)
  - 50K+ row query performance benchmarks
  - Network overhead analysis
  - Caching strategy recommendations

- **MANDATA_CAPTATE_TEST_RESULTS.md** (238 lines)
  - Real-world cube query results
  - Time dimension patterns
  - Production query benchmarks

- **TEST_CLEANUP_SUMMARY.md** (182 lines)
  - Test suite organization guide
  - Test coverage summary
  - Testing best practices

#### Presentations
- **v0.1.3-release-talk.md** (806 lines)
  - Complete presentation deck for v0.1.3 release
  - Architecture diagrams and performance comparisons
  - Live demo scenarios

- **v0.1.3-talking-points.md** (701 lines)
  - Detailed talking points and technical deep-dives
  - Q&A preparation material

**Total Documentation Added:** +2,565 lines

### Changed
- Enhanced `lib/power_of_three.ex` with SQL keyword validation (+180 lines)
- Improved default value handling for auto-generation
- Enhanced test helper utilities
- Updated getting started guide

### Fixed
- Better handling of nil Ecto.Schema fields in auto-generation
- Improved default value sensibility
- Enhanced auto-generation with `from` option

### Performance
**Arrow IPC vs HTTP API (with cache):**
- Small queries (200 rows): **25.5x faster** (2ms vs 51ms)
- Medium queries (1,827 rows): **66x faster** (1ms vs 66ms)
- Large queries (50K rows): **25x faster** (46ms vs 1,149ms)

**Cache Impact on Arrow IPC:**
- Average speedup: **30.6x faster**
- Best case: **89x faster** (89ms → 1ms)
- Range: 3-89x improvement across all query types

### Statistics
```
27 files changed
5,291 insertions(+)
104 deletions(-)
```

---

## [0.1.3] - 2024-12-XX

### Fixed
- Excluded ADBC dependency from hex.publish package
- Fixed test coverage configuration

---

For complete release notes, see [RELEASE_v0.1.4.md](./RELEASE_v0.1.4.md)
