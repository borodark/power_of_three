# Power-of-Three Repository - Terminology and Port Updates

**Date:** 2024-12-27
**Status:** Complete

## Summary

Updated the Power-of-Three repository to reflect correct terminology and port configuration aligned with the Cube.js ADBC Server implementation.

## Changes Made

### 1. Port Updates: 4445 → 8120

Changed all references from the old default port **4445** to the new default port **8120** to match Cube.js ADBC Server configuration.

### 2. Module Attribute Updates

- **Old:** `@arrow_port 4445` / `@cube_port 4445`
- **New:** `@cube_adbc_port 8120`

This provides consistent naming across all test files and aligns with the ADBC (Arrow Database Connectivity) specification.

### 3. Environment Variable Updates

- **Old:** `CUBEJS_ARROW_PORT`
- **New:** `CUBEJS_ADBC_PORT`

### 4. Terminology Updates

Updated terminology throughout to clarify the architecture:

#### Protocol Terminology
- **Old:** "Arrow Native" or "Arrow IPC"
- **New:** "ADBC(Arrow Native)"

This makes it clear that we're using the ADBC standard protocol with Arrow Native format.

## Files Updated

### Elixir Source Code

1. **`lib/power_of_three/cube_connection.ex`**
   - Updated all port defaults: 4445 → 8120
   - Updated documentation comments to reference port 8120
   - Lines updated: 14, 56, 74, 83

### Test Files

2. **`test/power_of_three/comprehensive_performance_test.exs`**
   - Module attribute: `@cube_port` → `@cube_adbc_port`
   - Port value: 4445 → 8120
   - Environment variable: `CUBEJS_ARROW_PORT` → `CUBEJS_ADBC_PORT`
   - All references updated throughout the file

3. **`test/power_of_three/http_vs_arrow_performance_test.exs`**
   - Module attribute: `@arrow_port` → `@cube_adbc_port`
   - Port value: 4445 → 8120
   - All references updated throughout the file

4. **`test/power_of_three/mandata_captate_test.exs`**
   - Module attribute: `@arrow_port` → `@cube_adbc_port`
   - Port value: 4445 → 8120
   - Terminology: "Arrow IPC" → "ADBC(Arrow Native)"
   - Comments and output messages updated

5. **`test/power_of_three/cubestore_metastore_test.exs`**
   - Module attribute: `@cube_port` → `@cube_adbc_port`
   - Port value: 4445 → 8120
   - Comments: "Arrow IPC port" → "ADBC port"

6. **`test/power_of_three/preagg_routing_test.exs`**
   - Module attribute: `@cube_port` → `@cube_adbc_port`
   - Port value: 4445 → 8120
   - Environment variable: `CUBEJS_ARROW_PORT=4445` → `CUBEJS_ADBC_PORT=8120`
   - Comments: "Arrow IPC" → "ADBC(Arrow Native)"

### Documentation Files

7. **`IMPLEMENTATION_PLAN.md`**
   - Updated port reference: 4445 → 8120

8. **`CUBE_SERVICE_MANAGEMENT.md`**
   - Port: 4445 → 8120
   - Environment variable: `CUBEJS_ARROW_PORT` → `CUBEJS_ADBC_PORT`
   - Terminology: "Arrow Native protocol" → "ADBC(Arrow Native) protocol"
   - Updated service health checks and commands
   - Updated troubleshooting port references

9. **`PHASE3_INTEGRATION_TEST_RESULTS.md`**
   - Port: 4445 → 8120
   - Service description: "Arrow Native protocol server" → "ADBC(Arrow Native) protocol server"
   - Configuration examples updated

## Architecture Clarification

### Before
The terminology was inconsistent:
- Mixed use of `@arrow_port` and `@cube_port`
- "Arrow Native" and "Arrow IPC" used interchangeably
- Port 4445 was inconsistent with Cube.js ADBC Server

### After
The architecture is now clear and consistent:

```
┌────────────────────────────────────────────────┐
│     PowerOfThree Elixir Application            │
│                                                 │
│  - Uses @cube_adbc_port module attribute       │
│  - Connects to Cube ADBC Server via ADBC       │
│  - Default port: 8120                          │
└────────────────┬───────────────────────────────┘
                 │
                 │ ADBC(Arrow Native) protocol
                 │
┌────────────────▼───────────────────────────────┐
│      Cube.js ADBC Server (cubesqld)            │
│                                                 │
│  - Implements ADBC protocol specification      │
│  - Uses Arrow Native format for data transfer  │
│  - Default port: 8120                          │
│  - Environment: CUBEJS_ADBC_PORT=8120          │
└────────────────────────────────────────────────┘
```

## Key Terminology

| Component | Description |
|-----------|-------------|
| **Cube ADBC Server** | Cube.js server implementing ADBC protocol (binary: cubesqld) |
| **ADBC(Arrow Native)** | Protocol using ADBC specification with Arrow Native format |
| **@cube_adbc_port** | Module attribute for ADBC server port (default: 8120) |
| **CUBEJS_ADBC_PORT** | Environment variable for server port (default: 8120) |

## Module Attribute Naming Convention

All test files now use consistent naming:

```elixir
# Configuration
@cube_driver_path Path.join(:code.priv_dir(:adbc), "lib/libadbc_driver_cube.so")
@cube_host "localhost"
@cube_adbc_port 8120  # ADBC port
@cube_token "test"
```

## Connection Examples

### Before
```elixir
@arrow_port 4445
@cube_port 4445

case :gen_tcp.connect(String.to_charlist(@cube_host), @arrow_port, [:binary], 1000) do
  ...
end

"adbc.cube.port": Integer.to_string(@cube_port)
```

### After
```elixir
@cube_adbc_port 8120

case :gen_tcp.connect(String.to_charlist(@cube_host), @cube_adbc_port, [:binary], 1000) do
  ...
end

"adbc.cube.port": Integer.to_string(@cube_adbc_port)
```

## Testing

All tests have been updated and should continue to work with the new port and terminology:

```bash
# Run comprehensive performance tests
cd ~/projects/learn_erl/power-of-three
mix test test/power_of_three/comprehensive_performance_test.exs

# Run HTTP vs ADBC comparison tests
mix test test/power_of_three/http_vs_arrow_performance_test.exs

# Run pre-aggregation routing tests
mix test test/power_of_three/preagg_routing_test.exs

# Run all tests
mix test
```

## Compatibility

- **Backward Compatibility:** Code will work with explicit port configuration
- **Default Behavior:** Now uses port 8120 by default
- **Documentation:** All updated to reflect new terminology
- **Environment Variables:** Use CUBEJS_ADBC_PORT instead of CUBEJS_ARROW_PORT

## Benefits

1. **Consistency:** Matches Cube.js repository port configuration (8120)
2. **Clarity:** Clear naming with `@cube_adbc_port` module attribute
3. **Standards Compliance:** Aligns with Apache Arrow ADBC specification terminology
4. **Accuracy:** "ADBC(Arrow Native)" correctly describes the protocol implementation

## Migration Guide

If you have existing code or configurations:

1. **Update module attributes:**
   - Change `@arrow_port` → `@cube_adbc_port`
   - Change `@cube_port` → `@cube_adbc_port`
   - Update port value: `4445` → `8120`

2. **Update environment variables:**
   - Change `CUBEJS_ARROW_PORT` → `CUBEJS_ADBC_PORT`

3. **Update terminology (documentation):**
   - "Arrow Native" → "ADBC(Arrow Native)"
   - "Arrow IPC" → "ADBC(Arrow Native)"

4. **Binary name unchanged:**
   - Server binary is still `cubesqld` (no change needed)

## Verification

Run this command to verify all references are updated:

```bash
cd ~/projects/learn_erl/power-of-three
grep -r "4445\|CUBEJS_ARROW_PORT\|@arrow_port\|@cube_port[^_]" . \
  --include="*.ex" --include="*.exs" --include="*.md" \
  2>/dev/null | grep -v "_build\|deps/"
```

Expected output: *(empty - all references updated)*

---

**Status:** ✅ Complete
**Next Steps:** Continue development with consistent terminology and port configuration
