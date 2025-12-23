# Ten Minutes to PowerOfThree

> **Start with everything. Keep what performs. Pre-aggregate what matters.**

This guide will get you from zero to productive analytics in 10 minutes. By the end, you'll understand how PowerOfThree brings type-safe, ergonomic analytics to your Elixir application using Cube.js's semantic layer.

## What You'll Build

A working analytics setup that:
- Defines reusable business metrics in your Ecto schemas
- Generates type-safe accessor functions at compile time
- Queries your data with Explorer DataFrames
- Integrates with Cube.js for performance and pre-aggregations

## Prerequisites

You'll need:
- An existing Elixir application with Ecto schemas
- A running Cube.js instance ([setup guide](https://github.com/borodark/power-of-three-examples/blob/main/compose.yml))
- Basic familiarity with Ecto and SQL

> **Note**: For Cube.js cluster setup, see the [ANALYTICS_WORKFLOW.md](../ANALYTICS_WORKFLOW.md#step-0-setup-yorself-a-cube-analitics-server-or-cluster-for-great-good) guide.

## Installation (1 minute)

Add PowerOfThree to your `mix.exs`:

```elixir
def deps do
  [
    {:power_of_3, "~> 0.1.2"},
    {:explorer, "~> 0.11.1"},  # For DataFrames
    {:req, "~> 0.5"}           # For HTTP queries
  ]
end
```

Run:
```bash
mix deps.get
```

## Your First Cube (2 minutes)

Let's start with a simple e-commerce schema:

```elixir
defmodule MyApp.Order do
  use Ecto.Schema
  use PowerOfThree  # ← Add this line

  schema "orders" do
    field :customer_email, :string
    field :total_amount, :float
    field :status, :string
    field :item_count, :integer
    timestamps()
  end

  # Define your analytics cube
  cube :orders, sql_table: "orders" do
    # Dimensions - what you group by
    dimension :customer_email
    dimension :status

    # Measures - what you aggregate
    measure :count                           # COUNT(*)
    measure :total_amount,                   # SUM(total_amount)
      type: :sum,
      name: :revenue
  end
end
```

**Compile and see the magic:**

```bash
mix compile
```

PowerOfThree generates:
- ✅ `model/cubes/orders.yaml` - Cube.js configuration
- ✅ `Order.Dimensions` module with accessor functions
- ✅ `Order.Measures` module with accessor functions
- ✅ `Order.df/1` function for querying

## Your First Query (1 minute)

Open `iex -S mix` and run:

```elixir
# Get revenue by status
{:ok, df} = MyApp.Order.df(
  columns: [
    MyApp.Order.Dimensions.status(),
    MyApp.Order.Measures.revenue()
  ]
)

# Print results
Explorer.DataFrame.print(df)
```

**Output:**
```
+------------+--------------------+
| status     | orders.revenue     |
+============+====================+
| completed  | 45230.50           |
| pending    | 12450.00           |
| cancelled  | 2100.75            |
+------------+--------------------+
```

🎉 You just ran your first analytics query!

## Understanding What Happened (2 minutes)

### 1. The Semantic Layer

When you defined the cube, PowerOfThree:

```elixir
cube :orders, sql_table: "orders" do
  dimension :status
  measure :total_amount, type: :sum, name: :revenue
end
```

This creates a **semantic layer** - a reusable definition of your business metrics. The `revenue` calculation is now centralized. Use it everywhere:

```elixir
# Dashboard
Order.df(columns: [Order.Measures.revenue()])

# Report
Order.df(columns: [Order.Dimensions.status(), Order.Measures.revenue()])

# API endpoint
Order.df(columns: [..., Order.Measures.revenue()])
```

Same calculation, guaranteed consistency.

### 2. Type-Safe References

PowerOfThree generates accessor modules at compile time:

```elixir
Order.Dimensions.status()      # Returns %DimensionRef{}
Order.Measures.revenue()       # Returns %MeasureRef{}
```

Typos are caught at compile time:

```elixir
Order.Measures.revenu()  # ← Compiler error!
# ** (UndefinedFunctionError) function Order.Measures.revenu/0 is undefined
```

### 3. Explorer DataFrames

Results come back as `Explorer.DataFrame` - ready for analysis, visualization, or ML:

```elixir
{:ok, df} = Order.df(columns: [...])

# Filter
df |> Explorer.DataFrame.filter(status == "completed")

# Sort
df |> Explorer.DataFrame.sort_by(desc: revenue)

# Export
df |> Explorer.DataFrame.to_csv("report.csv")
```

## Auto-Generation Shortcut (1 minute)

Don't want to define every field manually? Use auto-generation:

```elixir
defmodule MyApp.Product do
  use Ecto.Schema
  use PowerOfThree

  schema "products" do
    field :name, :string
    field :sku, :string
    field :price, :float
    field :quantity, :integer
    timestamps()
  end

  # Just this - no block!
  cube :products, sql_table: "products"
end
```

Run `mix compile` and see the generated code:

```elixir
# Auto-generated cube definition (copy-paste ready):

cube :products,
  sql_table: "products" do

  dimension(:name)
  dimension(:sku)
  dimension(:inserted_at)
  dimension(:updated_at)

  measure(:count)
  measure(:quantity, type: :sum, name: :quantity_sum)
  measure(:quantity, type: :count_distinct, name: :quantity_distinct)
  measure(:price, type: :sum, name: :price_sum)
end
```

**The workflow:**
1. Start with auto-generation
2. Copy the output
3. Paste into your schema
4. Delete what you don't need
5. Add business logic

## Advanced Queries (2 minutes)

### Filtering

```elixir
{:ok, df} = Order.df(
  columns: [
    Order.Dimensions.status(),
    Order.Measures.revenue()
  ],
  where: "status = 'completed' AND total_amount > 100"
)
```

### Ordering

```elixir
{:ok, df} = Order.df(
  columns: [
    Order.Dimensions.customer_email(),
    Order.Measures.revenue()
  ],
  order_by: [{2, :desc}],  # Order by revenue descending
  limit: 10
)
```

### Complex Analysis

```elixir
{:ok, df} = Order.df(
  columns: [
    Order.Dimensions.status(),
    Order.Dimensions.customer_email(),
    Order.Measures.count(),
    Order.Measures.revenue()
  ],
  where: "inserted_at >= '2024-01-01'",
  order_by: [{4, :desc}, {1, :asc}],
  limit: 100
)
```

## Filtered Measures (1 minute)

Define measures with built-in filters for specific use cases:

```elixir
cube :orders, sql_table: "orders" do
  dimension :status

  measure :count

  # Total revenue (all orders)
  measure :total_amount,
    type: :sum,
    name: :total_revenue

  # Completed revenue only
  measure :total_amount,
    type: :sum,
    name: :completed_revenue,
    filters: [%{sql: "status = 'completed'"}]

  # Large orders revenue (>$100)
  measure :total_amount,
    type: :sum,
    name: :large_order_revenue,
    filters: [%{sql: "total_amount > 100"}]
end
```

Now query with precision:

```elixir
# Get all three metrics at once
{:ok, df} = Order.df(
  columns: [
    Order.Dimensions.status(),
    Order.Measures.total_revenue(),
    Order.Measures.completed_revenue(),
    Order.Measures.large_order_revenue()
  ]
)
```

## Dynamic Queries (Bonus)

Build queries dynamically based on user input:

```elixir
def dashboard_query(selected_dimensions, selected_measures) do
  # Get all available options
  all_dimensions = Order.dimensions()
  all_measures = Order.measures()

  # Filter to user selection
  dimensions = Enum.filter(all_dimensions, fn d ->
    d.name in selected_dimensions
  end)

  measures = Enum.filter(all_measures, fn m ->
    m.name in selected_measures
  end)

  # Query
  Order.df(columns: dimensions ++ measures)
end

# Usage
dashboard_query(
  [:status, :customer_email],    # User picked these dimensions
  [:count, :revenue]              # User picked these measures
)
```

Perfect for building interactive dashboards!

## What's Really Happening? (Understanding Cube.js)

PowerOfThree is a bridge between your Elixir application and Cube.js:

```
┌─────────────────────────────────────────────┐
│  Your Elixir App                            │
│  ┌───────────────────────────────────────┐  │
│  │  Ecto Schema + PowerOfThree           │  │
│  │                                       │  │
│  │  cube :orders do                      │  │
│  │    dimension :status                  │  │
│  │    measure :revenue, type: :sum       │  │
│  │  end                                  │  │
│  └───────────────┬───────────────────────┘  │
│                  │                           │
│         mix compile (generates YAML)         │
│                  │                           │
└──────────────────┼───────────────────────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │  orders.yaml        │
         │  (Cube config)      │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  Cube.js Cluster    │
         │  (Semantic Layer)   │
         │                     │
         │  • Validates query  │
         │  • Generates SQL    │
         │  • Caches results   │
         │  • Pre-aggregates   │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  Your Database      │
         │  (PostgreSQL, etc)  │
         └─────────────────────┘
```

### The Real Power: Pre-Aggregations

Once your cubes are defined, Cube.js can:

1. **Cache query results** - Turn expensive queries into instant lookups
2. **Pre-aggregate data** - Pre-calculate common aggregations
3. **Incrementally refresh** - Update only new data
4. **Scale independently** - Add Cube workers without touching your DB

As the [Analytics Workflow](../ANALYTICS_WORKFLOW.md#step-4-work-with-dataframes) reminds us:

> Realize that it was all for [caching](https://cube.dev/docs/product/caching) and [pre-aggregations](https://cube.dev/docs/product/caching/getting-started-pre-aggregations).

The cube definitions you create today become the performance optimizations that scale tomorrow.

## Complete Example: Customer Analytics

Putting it all together:

```elixir
defmodule MyApp.Customer do
  use Ecto.Schema
  use PowerOfThree

  schema "customers" do
    field :email, :string
    field :name, :string
    field :status, :string
    field :plan, :string
    field :lifetime_value, :float
    timestamps()
  end

  cube :customers,
    sql_table: "customers",
    description: "Customer analytics and metrics" do

    # Dimensions
    dimension :status, description: "Customer status (active, churned, etc)"
    dimension :plan, description: "Subscription plan"
    dimension :inserted_at, name: :signup_date

    # Basic measures
    measure :count, description: "Total customers"

    measure :email,
      type: :count_distinct,
      name: :unique_customers,
      description: "Unique customer count"

    measure :lifetime_value,
      type: :sum,
      name: :total_ltv,
      description: "Total lifetime value"

    measure :lifetime_value,
      type: :avg,
      name: :avg_ltv,
      description: "Average lifetime value per customer"

    # Filtered measures
    measure :email,
      type: :count_distinct,
      name: :active_customers,
      description: "Active customers only",
      filters: [%{sql: "status = 'active'"}]

    measure :email,
      type: :count_distinct,
      name: :enterprise_customers,
      description: "Enterprise plan customers",
      filters: [%{sql: "plan = 'enterprise'"}]
  end
end
```

**Query it:**

```elixir
# Executive dashboard
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.plan(),
    Customer.Measures.active_customers(),
    Customer.Measures.total_ltv(),
    Customer.Measures.avg_ltv()
  ],
  order_by: [{3, :desc}]
)

Explorer.DataFrame.print(df)
```

**Output:**
```
+--------------+----------------------+-------------------+-----------------+
| plan         | active_customers     | total_ltv         | avg_ltv         |
+==============+======================+===================+=================+
| enterprise   | 45                   | 450000.00         | 10000.00        |
| professional | 230                  | 345000.00         | 1500.00         |
| starter      | 1200                 | 180000.00         | 150.00          |
+--------------+----------------------+-------------------+-----------------+
```

## Next Steps

**You're now productive with PowerOfThree!** Here's where to go next:

### Deepen Your Knowledge
- 📖 [ANALYTICS_WORKFLOW.md](../ANALYTICS_WORKFLOW.md) - Comprehensive workflow guide with architecture details
- 📘 [QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - Cheat sheet for common patterns
- 🎯 [Auto-Generation Blog Post](../docs/blog/auto-generation.md) - Deep dive into the auto-generation workflow

### Set Up Cube.js
- 🐳 [Docker Compose Setup](https://github.com/borodark/power-of-three-examples/blob/main/compose.yml) - Quick local development setup
- 📚 [Cube.js Documentation](https://cube.dev/docs/product/data-modeling/reference/cube) - Official Cube.js docs
- ⚡ [Pre-Aggregations Guide](https://cube.dev/docs/product/caching/getting-started-pre-aggregations) - Performance optimization

### Working Examples
- 💻 [Example Repository](https://github.com/borodark/power-of-three-examples) - Complete working examples
- 🔬 [Customer Example](https://github.com/borodark/power-of-three-examples/blob/main/lib/pot_examples/customer.ex) - Real-world customer analytics
- 📊 [Order Example](https://github.com/borodark/power-of-three-examples/blob/main/lib/pot_examples/order.ex) - E-commerce order analytics

### Advanced Topics
- **Multi-field dimensions** - Composite keys and concatenated fields
- **Time dimensions** - Date granularity and time-based analysis
- **Joins** - Connecting multiple cubes
- **Security** - Row-level access control
- **Performance** - Pre-aggregation strategies

## Summary

In 10 minutes, you've learned to:

1. ✅ Add PowerOfThree to an Ecto schema
2. ✅ Define dimensions and measures
3. ✅ Query with type-safe references
4. ✅ Work with Explorer DataFrames
5. ✅ Use auto-generation for quick starts
6. ✅ Create filtered measures for specific use cases
7. ✅ Build dynamic queries
8. ✅ Understand the Cube.js integration

**The PowerOfThree workflow:**

> **Start with everything** (auto-generation) → **Keep what performs** (copy, paste, refine) → **Pre-aggregate what matters** (Cube.js caching)

Welcome to ergonomic analytics in Elixir! 🚀

---

*Guide version 1.0 - December 2024*
