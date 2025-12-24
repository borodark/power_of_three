# Changelog

All notable changes to PowerOfThree will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **ASCII Art Barbell Logo**: Olympic weightlifting barbell logo displaying on auto-generated cube output
  - Left plate: Hexagon labeled "Ecto Macro Elixir" (representing Elixir/Ecto)
  - Center bar: Realistic Olympic barbell with knurling pattern and collar clips
  - Right plate: 3D isometric cube labeled "CUBE" (representing Cube.js)
  - Full ANSI color support with cyan, yellow, and magenta highlighting
  - Official tagline: "Start with everything. Keep what performs. Pre-aggregate what matters."

- **Auto-Generated Cube Definitions**: Compile-time cube generation from Ecto schemas
  - Auto-generates dimensions for string, boolean, and timestamp fields
  - Auto-generates measures: `count` (always), `sum` and `count_distinct` for integers, `sum` for floats
  - System fields (`id`, `inserted_at`, `updated_at`) automatically skipped
  - Syntax-highlighted output showing copy-paste ready cube code
  - Smart field filtering and type inference

- **Time Dimension Support**: Comprehensive timestamp handling
  - All datetime/date/time Ecto types automatically become time dimensions
  - Proper `:time` type mapping in Cube.js
  - Support for all granularities: second, minute, hour, day, week, month, quarter, year
  - Granularity specified at query time for maximum flexibility
  - Metadata preservation for accurate YAML generation

- **Comprehensive Test Coverage**:
  - 19 new tests for time dimension auto-generation
  - Tests for all datetime field types (`:date`, `:time`, `:naive_datetime`, `:naive_datetime_usec`, `:utc_datetime`, `:utc_datetime_usec`)
  - Accessor function verification
  - YAML generation validation
  - Mixed field type scenarios
  - Total: 290 tests passing

- **Documentation**:
  - "Ten Minutes to PowerOfThree" quick-start guide
  - Auto-generation feature blog post
  - Workflow documentation: Scaffold → Refine → Own

### Changed

- Improved cube auto-generation to skip system timestamps by default
- Enhanced dimension type inference with comprehensive Ecto type mapping

### Fixed

- Logo alignment and spacing for proper Olympic barbell aesthetics
- CUBE plate now displays with proper 3D isometric perspective
- Time dimension metadata correctly preserved through compilation

## [0.1.2] - 2024-12-XX

### Added
- Initial auto-generation support
- HTTP client for Cube.js queries
- Explorer DataFrame integration

---

*Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)*
