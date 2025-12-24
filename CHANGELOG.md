# Changelog

All notable changes to PowerOfThree will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2024-12-24

### Added

- **Blocky Minecraft-Style Lifter**: Weightlifter character in completed snatch position
  - Centered on barbell with arms extended to touch the bar
  - Represents PowerOfThree successfully lifting heavy analytics workloads
  - Displays on auto-generated cube compile output
  - Built with Unicode block characters for consistent terminal rendering

- **ASCII Art Barbell Logo**: Olympic weightlifting barbell logo displaying on auto-generated cube output
  - Left plate: Hexagon labeled "Ecto Macro Elixir" (representing Elixir/Ecto)
  - Center bar: Realistic Olympic barbell with knurling pattern and collar clips
  - Right plate: 3D isometric cube labeled "CUBE" (representing Cube.js)
  - Full ANSI color support with cyan, yellow, and magenta highlighting
  - Official tagline: "Start with everything. Keep what performs. Pre-aggregate what matters."

- **Auto-Generated Cube Definitions**: Compile-time cube generation from Ecto schemas
  - Auto-generates dimensions for string, boolean, and timestamp fields
  - Auto-generates measures: `count` (always), `sum` and `count_distinct` for integers, `sum` for floats
  - System field `id` automatically skipped
  - Syntax-highlighted output showing copy-paste ready cube code
  - Smart field filtering and type inference

- **Time Dimension Support**: Comprehensive timestamp handling
  - All datetime/date/time Ecto types automatically become time dimensions
  - Proper `:time` type mapping in Cube.js
  - Support for all granularities: second, minute, hour, day, week, month, quarter, year
  - Metadata preservation for accurate YAML generation

- **Client-Side Timestamp Granularity**: Cube.js native granularity support
  - Generates simple time dimensions for `inserted_at` and `updated_at`
  - Granularity specified at query time (not dimension definition time)
  - Follows Cube.js best practices using `date_trunc` SQL function
  - Supports all 8 granularities: second, minute, hour, day, week, month, quarter, year
  - Cleaner API: 2 dimensions instead of 16 per schema
  - Works with all Ecto datetime types (`:naive_datetime`, `:naive_datetime_usec`, `:utc_datetime`, `:utc_datetime_usec`)

- **Comprehensive Test Coverage**:
  - 19 tests for time dimension auto-generation
  - Tests for all datetime field types (`:date`, `:time`, `:naive_datetime`, `:naive_datetime_usec`, `:utc_datetime`, `:utc_datetime_usec`)
  - Accessor function verification
  - YAML generation validation
  - Mixed field type scenarios
  - Total: 290 tests passing

- **Documentation**:
  - "Ten Minutes to PowerOfThree" quick-start guide
  - Auto-generation feature blog post
  - Workflow documentation: Scaffold → Refine → Own
  - Updated hex.pm docs with Quick Start section
  - Auto-generation blog post included in hex.pm extras
  - Key Features section highlighting auto-generation and client-side granularity

### Changed

- **BREAKING**: Switched from server-side to client-side timestamp granularity
  - No longer generates 16 granularity-specific dimensions (`inserted_at_day`, `updated_at_month`, etc.)
  - Now generates 2 simple time dimensions (`inserted_at`, `updated_at`)
  - Granularity specified at query time using Cube.js native support
- Changed auto-generation to only skip `id` field (generates `inserted_at`/`updated_at` as time dimensions)
- Enhanced dimension type inference with comprehensive Ecto type mapping

### Fixed

- Logo alignment and spacing for proper Olympic barbell aesthetics
- CUBE plate now displays with proper 3D isometric perspective
- Time dimension metadata correctly preserved through compilation
- Suppressed intrusion detection log noise (only logs when actual intrusions detected)

## [0.1.2] - 2024-12-XX

### Added
- Initial auto-generation support
- HTTP client for Cube.js queries
- Explorer DataFrame integration

---

*Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)*
