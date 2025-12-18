# Cube Service Management Guide

## Overview

The PowerOfThree `df/2` functionality requires three services to be running:
1. **PostgreSQL** - Data storage (port 7432)
2. **Cube API** - Cube.js server (port 4008)
3. **cubesqld** - Arrow Native protocol server (port 4445)

All scripts are located in: `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/`

---

## Starting Services

### 1. Start Cube API Server

```bash
cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
./start-cube-api.sh
```

**Features:**
- Automatically starts PostgreSQL via docker-compose if not running
- Runs on port 4008
- **Logs:** `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/cube-api.log`

**To monitor logs:**
```bash
tail -f ~/projects/learn_erl/cube/examples/recipes/arrow-ipc/cube-api.log
```

### 2. Start cubesqld Server

**Important:** Must start Cube API first!

```bash
cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
./start-cubesqld.sh
```

**Features:**
- Provides Arrow Native protocol on port 4445
- Provides PostgreSQL protocol on port 4444
- **Logs:** Output to terminal (stdout)

**To run in background with logs:**
```bash
cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
./start-cubesqld.sh 2>&1 | tee cubesqld.log &
```

**To monitor logs:**
```bash
tail -f ~/projects/learn_erl/cube/examples/recipes/arrow-ipc/cubesqld.log
```

---

## Stopping Services

### Stop cubesqld
```bash
# If running in foreground: Ctrl+C
# If running in background:
kill $(lsof -ti:4445)
```

### Stop Cube API
```bash
# If running in foreground: Ctrl+C
# If running in background:
kill $(lsof -ti:4008)
```

### Stop PostgreSQL
```bash
cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
docker-compose down
```

---

## Service Health Check

```bash
# Check all services at once
lsof -i :7432,4008,4445 | grep LISTEN
```

Expected output:
```
postgres  <pid> io    5u  IPv4 ... TCP *:7432 (LISTEN)
node      <pid> io   21u  IPv4 ... TCP *:4008 (LISTEN)
cubesqld  <pid> io    9u  IPv4 ... TCP *:4445 (LISTEN)
```

---

## Testing the Connection

### From Elixir (power-of-three-examples)

```elixir
# Start IEx
cd ~/projects/learn_erl/power-of-three-examples
iex -S mix

# Test ADBC connection
{:ok, result} = ExamplesOfPoT.CubeQuery.query("SELECT 1 as test")

# List available cubes
{:ok, cubes} = ExamplesOfPoT.CubeQuery.list_cubes()

# Query a cube
ExamplesOfPoT.CubeQuery.query_cube!(
  cube: "of_customers",
  dimensions: ["brand"],
  measures: ["count"],
  limit: 10
)
```

---

## Connection Configuration

### For PowerOfThree

Based on `~/projects/learn_erl/power-of-three-examples/config/config.exs`:

```elixir
config :your_app, Adbc.CubePool,
  pool_size: 10,
  host: "localhost",
  port: 4445,          # Arrow Native protocol
  token: "test",
  username: "username",
  password: "password"
```

### Environment Variables (from .env)

Located in `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/.env`:

```bash
PORT=4008                       # Cube API port
CUBEJS_DB_TYPE=postgres
CUBEJS_DB_PORT=7432            # PostgreSQL port
CUBEJS_DB_NAME=pot_examples_dev
CUBEJS_DB_USER=postgres
CUBEJS_DB_PASS=postgres
CUBEJS_DB_HOST=localhost
CUBEJS_ARROW_PORT=4445         # Arrow Native port
CUBESQL_CUBE_TOKEN=test        # Authentication token
```

---

## Quick Start Script

Create `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/start-all.sh`:

```bash
#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Starting Cube API..."
./start-cube-api.sh 2>&1 | tee cube-api.log &
CUBE_API_PID=$!

echo "Waiting for Cube API to start..."
sleep 5

echo "Starting cubesqld..."
./start-cubesqld.sh 2>&1 | tee cubesqld.log &
CUBESQLD_PID=$!

echo ""
echo "Services started:"
echo "  Cube API PID: $CUBE_API_PID (logs: $SCRIPT_DIR/cube-api.log)"
echo "  cubesqld PID: $CUBESQLD_PID (logs: $SCRIPT_DIR/cubesqld.log)"
echo ""
echo "To monitor logs:"
echo "  tail -f $SCRIPT_DIR/cube-api.log"
echo "  tail -f $SCRIPT_DIR/cubesqld.log"
echo ""
echo "To stop:"
echo "  kill $CUBE_API_PID $CUBESQLD_PID"
```

Make it executable:
```bash
chmod +x ~/projects/learn_erl/cube/examples/recipes/arrow-ipc/start-all.sh
```

---

## Log Locations Summary

| Service | Log Location | Command to Monitor |
|---------|-------------|-------------------|
| Cube API | `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/cube-api.log` | `tail -f cube-api.log` |
| cubesqld | `~/projects/learn_erl/cube/examples/recipes/arrow-ipc/cubesqld.log` (if redirected) | `tail -f cubesqld.log` |
| PostgreSQL | Docker logs | `docker logs -f <container_id>` |

---

## Troubleshooting

### Port Already in Use
```bash
# Find and kill process on specific port
lsof -ti:4445 | xargs kill -9
```

### PostgreSQL Not Running
```bash
cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
docker-compose up -d postgres
```

### Check PostgreSQL Connection
```bash
psql -h localhost -p 7432 -U postgres -d pot_examples_dev
```

### Cube API Not Responding
```bash
curl http://localhost:4008/cubejs-api/v1/meta
```

### cubesqld Connection Test
```bash
# Via psql (PostgreSQL protocol)
psql -h 127.0.0.1 -p 4444 -U root

# Via ADBC (from Python)
cd ~/projects/learn_erl/adbc/python/adbc_driver_cube
source venv/bin/activate
python quick_test.py
```
