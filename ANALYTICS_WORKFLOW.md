# Analytics Workflow with PowerOfThree

**A Type-Safe, Ergonomic Approach to Business Intelligence in Elixir**

https://github.com/borodark/power_of_three/blob/master/QUICK_REFERENCE.md

---

## TL;DR: The Elevator Pitch

`PowerOfThree` brings ergonomic approach to analytics in applications with type-safe workflow:

```elixir
# 1. Define your schema (you already have this)
defmodule MyApp.Customer do
  use Ecto.Schema
  use PowerOfThree  # ← Add one line

  schema "customer" do
    field :email, :string
    field :brand_code, :string
    timestamps()
  end

  cube :analytics do
    dimension :email
    dimension :brand_code, name: :brand
    measure :count
  end
end

# Have a coffee ... while deployments are settled.

# 2. Query with compile-time safety
dimensions = Customer.dimensions()  # Get all available dimensions
measures = Customer.measures()      # Get all available measures

# 3. Get DataFrames
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Measures.count()
  ],
  limit: 100
)
```

**The result?** The analytics with:
- ✅ Type safety from schema to DataFrame
- ✅ Compile-time column validation
- ✅ Automatic SQL generation
- ✅ Direct integration with Explorer/Nx ecosystem

---

## The Problem: Analytics in Traditional Apps

### Before PowerOfThree

When building analytics features in Elixir applications, you typically face several pain points:

**Pain #1: Manual SQL Everywhere**
```elixir
# Fragile, error-prone SQL strings
def sales_by_brand(conn) do
  Ecto.Adapters.SQL.query!(
    conn,
    """
    SELECT brand_code, COUNT(*) as total
    FROM orders
    WHERE status = 'completed'
    GROUP BY brand_code
    ORDER BY total DESC
    """,
    []
  )
end
```

**Pain #2: No Reusable Business Logic**
```elixir
# Same calculation duplicated across queries
"SUM(price * quantity * (1 - discount))"  # Revenue calculation #1
"SUM(price * quantity * (1 - discount))"  # Revenue calculation #2 (in another file)
"SUM(price * quantity * (1 - discount))"  # Revenue calculation #3 (in dashboard)
```

**Pain #3: No Type Safety**
```elixir
# Column names are strings - typos caught at runtime
result["totl_revenue"]  # Oops, typo!
# ** (KeyError) key "totl_revenue" not found
```

---

## The Solution: PowerOfThree Workflow

### Architecture: Three Layers Working Together

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Ecto Schema (Your existing models)                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Customer                                             │  │
│  │  - field :email, :string                              │  │
│  │  - field :brand_code, :string                         │  │
│  │  - timestamps()                                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────┘
                          │ use PowerOfThree
┌─────────────────────────▼───────────────────────────────────┐
│  Layer 2: Semantic Layer (Business logic as code)           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  cube :analytics do                                   │  │
│  │    dimension :email                                   │  │
│  │    dimension :brand_code, name: :brand                │  │
│  │                                                       │  │
│  │    measure :count                                     │  │
│  │    measure :email, name: :unique_users,               │  │
│  │            type: :count_distinct                      │  │
│  │  end                                                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  Generates:                                                 │
│  - Cube Defenition in analytics.yaml file                   │
│  - Customer.Dimensions.brand() → %DimensionRef{}            │
│  - Customer.Measures.count() → %MeasureRef{}                │
│  - Customer.df/1 → Query builder                            │
└───────────────┬─────────┬───────────────────────────────────┘
analytics.yaml  |         │ REST/JSON
┌───────────────▼─────────▼───────────────────────────────────┐
│  Layer 3: Query Execution                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  API Cube.js Semantic Layer                           │  │
│  │  ↓                                                    │  │
│  │  PostgreSQL/Snowflake/BigQuery                        │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  Returns: Explorer.DataFrame (columnar)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Complete Workflow Example

### Step 0: _Setup yorself a Cube Analitics Server or Cluster for greater good_

https://github.com/borodark/power-of-three-examples/blob/main/compose.yml


Solution for data analytics:
 - documentation: https://cube.dev/docs/product/data-modeling/reference/cube
 - Helm Charts https://github.com/gadsme/charts

How to use cube:
 - Start and connect cube cluster the source DB.
 - Define `cubes` as collections of `measures` aggregated along `dimensions`: DSL, yaml.
 - Drop cubes model yamls to the running clusters config space.
 - Decide how to refresh cube data
 - Profit!

#### Cube DEV environment

For crafting Cubes here is the docker: [compose.yaml](https://github.com/borodark/power-of-three-examples/blob/main/compose.yml)

##### Deployment Overview

Four types of containers:
  - API
  - Refresh Workers
  - Cubestore Router
  - Cubestore Workers

[![Logical deployment](https://ucarecdn.com/b4695d0a-46a9-4552-93f8-71309de51a43/)](https://cube.dev/docs/product/deployment)

Two need the analytics source DB connections: API and Refresh Workers.

Router needs a shared space with Store Workers: S3 is recommended.

Skip https://cube.dev/docs/product/caching/getting-started-pre-aggregations for now...


### Step 1: Define Your Schema (5 minutes)

You already have Ecto schemas. Just add `use PowerOfThree` and define your analytics cube:

```elixir
defmodule MyApp.Customer do
  use Ecto.Schema
  use PowerOfThree

  schema "customer" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :brand_code, :string
    field :market_code, :string
    field :birthday_month, :integer
    field :birthday_day, :integer
    timestamps()
  end

  cube :of_customers,
    sql_table: "customer",
    description: "Customer analytics" do

    # Simple dimensions (one field)
    dimension :email, description: "Customer email"
    dimension :brand_code, name: :brand, description: "Brand"
    dimension :market_code, name: :market, description: "Market"

    # Composite dimension (multiple fields)
    dimension [:brand_code, :market_code],
      name: :brand_market,
      primary_key: true

    # Calculated dimension (SQL expression)
    dimension [:birthday_month, :birthday_day],
      name: :zodiac,
      type: :string,
      sql: """
      CASE
        WHEN (birthday_month = 1 AND birthday_day >= 20) OR
             (birthday_month = 2 AND birthday_day <= 18)
        THEN 'Aquarius'
        WHEN (birthday_month = 2 AND birthday_day >= 19) OR
             (birthday_month = 3 AND birthday_day <= 20)
        THEN 'Pisces'
        -- ... more zodiac signs
        ELSE 'Unknown'
      END
      """

    # Measures
    measure :count, description: "Total customers"

    measure :email,
      name: :unique_emails,
      type: :count_distinct,
      description: "Unique email addresses"

    measure :email,
      name: :aquarius_customers,
      type: :count_distinct,
      description: "Customers born under Aquarius",
      filters: [
        %{sql: "(birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)"}
      ]

    # Time dimensions (automatic)
    time_dimensions()  # Adds inserted_at, updated_at
  end
end
```

**What happens?** Run `mix compile` and `PowerOfThree` generates:
- ✅ Cube.js configs in `model/cubes/` to be shared with the staging environment first
- ✅ `Customer.Dimensions` module with accessor functions
- ✅ `Customer.Measures` module with accessor functions
- ✅ `Customer.df/1` function for DataFrame queries
- ✅ Type-safe structs: `%DimensionRef{}`, `%MeasureRef{}`

---

### Step 2: Explore Your Data Model (30 seconds)

PowerOfThree provides two accessor patterns for maximum ergonomics:

#### Pattern 1: Direct Module Access (compile-time checked)

```elixir
# Fast, autocomplete-friendly
brand = Customer.Dimensions.brand()
# => %PowerOfThree.DimensionRef{
#      name: :brand,
#      type: :string,
#      sql: "brand_code",
#      module: MyApp.Customer,
#      ...
#    }

count = Customer.Measures.count()
# => %PowerOfThree.MeasureRef{
#      name: "count",
#      type: :count,
#      module: MyApp.Customer,
#      ...
#    }
```

#### Pattern 2: List Access (runtime introspection)

```elixir
# Perfect for building dynamic UIs
dimensions = Customer.dimensions()
# => [
#      %DimensionRef{name: :brand, ...},
#      %DimensionRef{name: :market, ...},
#      %DimensionRef{name: :zodiac, ...},
#      ...
#    ]
```

**Why two patterns?**
- **Module access**: Type-safe, fast, for code you write
- **List access**: Dynamic, for UIs users interact with

---

### Step 3: Build Queries with Type Safety

PowerOfThree generates SQL automatically from type-safe references:

```elixir
# Simple aggregation
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Measures.count()
  ],
  limit: 10
)
```

#### Advanced Queries

```elixir
# Multiple dimensions and measures
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Dimensions.market(),
    Customer.Dimensions.zodiac(),
    Customer.Measures.count(),
    Customer.Measures.unique_emails()
  ],
  where: "zodiac != 'Unknown'",
  order_by: [{4, :desc}, {1, :asc}],  # Order by count DESC, brand ASC
  limit: 20,
  offset: 10
)
```

---

### Step 4: Work with DataFrames

Results come back as `Explorer.DataFrame`:

```elixir
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Dimensions.zodiac(),
    Customer.Measures.count()
  ],
  limit: 5
)

#you get a DataFrame:
df
# =>
# +------------+-----------+---------------------+
# |   brand    |  zodiac   | measure(customer.count) |
# +============+===========+=====================+
# | Nike       | Aquarius  | 1215                |
# | Adidas     | Pisces    | 1188                |
# | Puma       | Leo       | 1208                |
# | Reebok     | Scorpio   | 1082                |
# | NewBalance | Cancer    | 1242                |
# +------------+-----------+---------------------+

# Use Explorer functions
Explorer.DataFrame.filter(df, zodiac == "Aquarius")
Explorer.DataFrame.group_by(df, "brand")
Explorer.DataFrame.to_csv(df, "output.csv")

# Or convert for other tools
Explorer.DataFrame.to_rows(df)  # List of maps
Explorer.DataFrame.to_series(df) # Map of series
```

#### Integration with Nx (Machine Learning)

```elixir
# DataFrames integrate with Nx for ML
{:ok, df} = Customer.df(columns: [...])

# Convert to Nx tensors
tensor = df
  |> Explorer.DataFrame.select(["measure(customer.count)"])
  |> Explorer.Series.to_tensor()

# Use with Scholar, Axon, etc.
Scholar.Stats.mean(tensor)
```

Learn https://cube.dev/docs/product/caching/getting-started-pre-aggregations ...

---

## The Ergonomics Win: Before vs. After

### Scenario: Sales Dashboard

**Before PowerOfThree** (Traditional approach):

```elixir
defmodule MyApp.Analytics do
  import Ecto.Query

  # Fragile SQL strings, no reuse
  def sales_by_brand(repo, filters) do
    query = """
    SELECT
      brand_code,
      COUNT(*) as order_count,
      SUM(total_amount) as revenue
    FROM orders
    WHERE status = 'completed'
      #{build_filter_clause(filters)}
    GROUP BY brand_code
    ORDER BY revenue DESC
    LIMIT 100
    """

    {:ok, result} = repo.query(query)

    # Manual transformation to columnar
    brands = Enum.map(result.rows, &Enum.at(&1, 0))
    counts = Enum.map(result.rows, &Enum.at(&1, 1))
    revenues = Enum.map(result.rows, &Enum.at(&1, 2))

    %{brands: brands, counts: counts, revenues: revenues}
  end

  # Same logic, different query - no reuse!
  def sales_by_brand_and_region(repo, filters) do
    # Duplicate SUM(total_amount) calculation
    # Duplicate status filtering
    # ...
  end

  defp build_filter_clause(filters) do
    # String manipulation nightmare
    # No validation, typos caught at runtime
  end
end
```

**After PowerOfThree** (Semantic layer approach):

```elixir
defmodule MyApp.Order do
  use Ecto.Schema
  use PowerOfThree

  schema "orders" do
    field :brand_code, :string
    field :region_code, :string
    field :status, :string
    field :total_amount, :integer
    timestamps()
  end

  cube :sales do
    dimension :brand_code, name: :brand
    dimension :region_code, name: :region

    # Business logic defined ONCE
    measure :count
    measure :total_amount,
      name: :revenue,
      type: :sum

    # Filtered measures - reusable!
    measure :total_amount,
      name: :completed_revenue,
      type: :sum,
      filters: [%{sql: "status = 'completed'"}]
  end
end

# Clean, reusable queries
defmodule MyApp.Analytics do
  def sales_by_brand(filters) do
    Order.df(
      columns: [
        Order.Dimensions.brand(),
        Order.Measures.count(),
        Order.Measures.completed_revenue()
      ],
      where: build_filter(filters),  # Type-safe filter building
      order_by: [{3, :desc}],
      limit: 100
    )
  end

  def sales_by_brand_and_region(filters) do
    # Same measures, different dimensions
    # Business logic reused automatically!
    Order.df(
      columns: [
        Order.Dimensions.brand(),
        Order.Dimensions.region(),
        Order.Measures.count(),
        Order.Measures.completed_revenue()
      ],
      where: build_filter(filters),
      order_by: [{4, :desc}],
      limit: 100
    )
  end

  defp build_filter(%{brands: brands, date_range: {from, to}}) do
    # Type-safe, validated filters
    [
      "brand_code IN (#{Enum.join(brands, ",")})",
      "created_at BETWEEN '#{from}' AND '#{to}'"
    ]
    |> Enum.join(" AND ")
  end
end
```

**The difference:**
- ✅ Business logic defined once, reused everywhere
- ✅ Type-safe column references
- ✅ Returns Explorer DataFrames ready for ML

---

## Value Proposition: Why PowerOfThree?

### For Elixir Developers

**Problem You're Solving:**
"I need analytics in my Phoenix app, but SQL is getting messy and I can't reuse business logic."

**PowerOfThree Answer:**
```elixir
# Define once
cube :analytics do
  measure :revenue, type: :sum, sql: :total_amount
end

# Use everywhere - same calculation, guaranteed
dashboard_query = Customer.df(columns: [Customer.Measures.revenue()])
report_query = Customer.df(columns: [..., Customer.Measures.revenue()])
api_query = Customer.df(columns: [Customer.Measures.revenue(), ...])
```

**Value:**
- ✅ Single source of truth for business metrics
- ✅ Type-safe queries catch errors at compile time
- ✅ Automatic SQL generation (no more string building)
- ✅ Works with your existing Ecto schemas

---

### For Data Teams

**Problem You're Solving:**
"Business logic is scattered across SQL queries in 50 different files. When a calculation changes, we miss updates."

**PowerOfThree Answer:**
```elixir
# Centralized semantic layer
cube :sales do
  measure :revenue,
    type: :sum,
    sql: "price * quantity * (1 - discount)",
    description: "Net revenue after discounts"
end

# Change it once, all queries update
# No grep-ing through codebases
# No missed updates causing inconsistencies
```

**Value:**
- ✅ Centralized business logic
- ✅ Self-documenting (descriptions in code)
- ✅ Version controlled with application code
- ✅ Testable (unit test your metrics)

---

### For Platform Teams

**Problem You're Solving:**
"We need to support multiple data warehouses (PostgreSQL, Snowflake, BigQuery) without rewriting queries."

**PowerOfThree Answer:**
```elixir
# Same code, multiple backends
cube :analytics, sql_table: "customers" do
  dimension :region
  measure :count
end

# Cube.js handles the dialect differences
# PostgreSQL: SELECT region, COUNT(*) FROM customers ...
# Snowflake: SELECT region, COUNT(*) FROM customers ...
# BigQuery: SELECT region, COUNT(*) FROM customers ...
```

**Value:**
- ✅ Database-agnostic queries
- ✅ Cube.js handles dialect differences
- ✅ Easy to migrate between warehouses
- ✅ Support multiple sources simultaneously

---

## Migration Guide

### From Raw SQL Queries

**Step 1:** Keep existing queries working:
```elixir
# Old code still works
def legacy_report(conn) do
  Ecto.Adapters.SQL.query!(conn, "SELECT brand, COUNT(*) ...")
end
```

**Step 2:** Add PowerOfThree schemas alongside:
```elixir
# New schema with cube
defmodule MyApp.Customer do
  use Ecto.Schema
  use PowerOfThree

  # ... schema definition ...

  cube :analytics do
    # Start simple - just basic dimensions/measures
    dimension :brand_code
    measure :count
  end
end
```

**Step 3:** Migrate one query at a time:
```elixir
# Replace legacy query with PowerOfThree
def new_report do
  Customer.df(
    columns: [
      Customer.Dimensions.brand_code(),
      Customer.Measures.count()
    ]
  )
end
```

**Step 4:** Deprecate old queries:
```elixir
@deprecated "Use new_report/0 instead"
def legacy_report(conn), do: new_report()
```

---

## Conclusion

PowerOfThree brings three critical benefits to Elixir analytics:

1. **Ergonomics**: Type-safe queries, automatic SQL generation, reusable business logic

**Start simple:**
```elixir
use PowerOfThree

cube :my_cube do
  dimension :some_field
  measure :count
end
```

**Scale up:**
- Add calculated dimensions
- Define filtered measures
- Build dynamic dashboards
- Integrate with ML pipelines
- Start pre-aggregation: https://cube.dev/docs/product/caching/getting-started-pre-aggregations

**The result?** Ergonomic analytics that feels native to Elixir. Yes, _Macros are involved_!

---

## Resources

- **Explorer**: [hexdocs.pm/explorer](https://hexdocs.pm/explorer)
- **Documentation**: [_use ^3_](https://github.com/borodark/power_of_three/blob/master/QUICK_REFERENCE.md)
- **Examples**: [power-of-three-examples](https://github.com/borodark/power-of-three-examples/)
- **Cube.js Docs**: [cube docs](https://cube.dev/docs/product/data-modeling/reference/cube)
- **Condensed version of the source data** [Pre-aggregations](https://cube.dev/docs/product/caching/getting-started-pre-aggregations) ...

---

*"In Codice Claudiano confidimus!"*
