# PowerOfThree Quick Reference

**Cheat sheet for common patterns and workflows**

---

## 30-Second Start

```elixir
# 1. Add to existing Ecto schema
defmodule Customer do
  use Ecto.Schema
  use PowerOfThree  # ← Add this

  schema "customer" do
    field :email, :string
    field :brand_code, :string
  end

  cube :analytics do
    dimension :email
    dimension :brand_code, name: :brand
    measure :count
  end
end

# 2. Query
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Measures.count()
  ]
)
```

---

## Cube Definition Patterns

### Simple Dimension
```elixir
dimension :field_name
```

### Dimension with Options
```elixir
dimension :field_name,
  name: :custom_name,        # Optional: rename
  description: "Friendly description",
  type: :string,              # Auto-detected from Ecto if omitted
  primary_key: true           # Mark as primary key
```

### Composite Dimension (Multiple Fields)
```elixir
dimension [:brand_code, :market_code],
  name: :brand_market,
  primary_key: true
# SQL: brand_code||market_code
```

### Calculated Dimension (SQL Expression)
```elixir
dimension [:field1, :field2],
  name: :calculated,
  type: :boolean,
  sql: "CASE WHEN field1 > field2 THEN 1 ELSE 0 END"
```

### Count Measure
```elixir
measure :count  # Special - no field needed
```

### Aggregation Measures
```elixir
measure :field_name,
  name: :custom_name,
  type: :sum              # :sum, :avg, :min, :max
```

### Count Distinct
```elixir
measure :email,
  name: :unique_users,
  type: :count_distinct
```

### Filtered Measure
```elixir
measure :email,
  name: :active_users,
  type: :count_distinct,
  filters: [
    %{sql: "status = 'active'"}
  ]
```

### Time Dimensions (Automatic)
```elixir
time_dimensions()  # Adds inserted_at, updated_at from timestamps()
```

---

## Query Patterns

### Basic Query
```elixir
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Measures.count()
  ]
)
```

### With Filters
```elixir
{:ok, df} = Customer.df(
  columns: [...],
  where: "brand_code = 'NIKE' AND status = 'active'"
)
```

### With Ordering
```elixir
{:ok, df} = Customer.df(
  columns: [...],
  order_by: [{2, :desc}]  # Order by 2nd column DESC
)

# Multiple columns
{:ok, df} = Customer.df(
  columns: [...],
  order_by: [{3, :desc}, {1, :asc}]  # Then by 1st column ASC
)
```

### With Limit/Offset
```elixir
{:ok, df} = Customer.df(
  columns: [...],
  limit: 100,
  offset: 50  # Skip first 50, return next 100
)
```

### Complete Example
```elixir
{:ok, df} = Customer.df(
  columns: [
    Customer.Dimensions.brand(),
    Customer.Dimensions.market(),
    Customer.Measures.count(),
    Customer.Measures.revenue()
  ],
  where: "brand_code IS NOT NULL",
  order_by: [{4, :desc}, {1, :asc}],
  limit: 20,
  offset: 10
)
```

### Bang Version (Raises on Error)
```elixir
df = Customer.df!(columns: [...])  # Raises Adbc.Error on failure
```

---

## Accessor Patterns

### Module Access (Type-Safe)
```elixir
# Direct access - fast, autocomplete-friendly
brand = Customer.Dimensions.brand()
count = Customer.Measures.count()

Customer.df(columns: [brand, count])
```

### List Access (Dynamic)
```elixir
# Get all available
dimensions = Customer.dimensions()  # [%DimensionRef{}, ...]
measures = Customer.measures()      # [%MeasureRef{}, ...]

# Explore
Enum.each(dimensions, fn d ->
  IO.puts("#{d.name} (#{d.type}): #{d.description}")
end)

# Find specific
brand = Enum.find(dimensions, fn d -> d.name == :brand end)
count = Enum.find(measures, fn m -> m.name == "count" end)

Customer.df(columns: [brand, count])
```

### Combined Pattern
```elixir
# Let users select dimensions
selected_dim_names = [:brand, :market]  # From UI

dimensions = Customer.dimensions()
selected_dims = Enum.filter(dimensions, fn d ->
  d.name in selected_dim_names
end)

# Add your required measures
Customer.df(
  columns: selected_dims ++ [
    Customer.Measures.count(),
    Customer.Measures.revenue()
  ]
)
```

---

## DataFrame Operations

### Explorer Integration
```elixir
{:ok, df} = Customer.df(columns: [...])

# Filter
Explorer.DataFrame.filter(df, brand == "Nike")

# Group
Explorer.DataFrame.group_by(df, "brand")

# Sort
Explorer.DataFrame.sort_by(df, desc: "measure(customer.count)")

# Select columns
Explorer.DataFrame.select(df, ["brand", "measure(customer.count)"])

# Export
Explorer.DataFrame.to_csv(df, "output.csv")
Explorer.DataFrame.to_rows(df)  # List of maps
```

---

## Type Reference

### Dimension Types
- `:string` - Text data
- `:number` - Numeric (integers, decimals)
- `:time` - Timestamps, dates
- `:boolean` - True/false
- `:geo` - Geographic data

### Measure Types
- `:count` - COUNT(*)
- `:count_distinct` - COUNT(DISTINCT field)
- `:count_distinct_approx` - HLL approximation
- `:sum` - SUM(field)
- `:avg` - AVG(field)
- `:min` - MIN(field)
- `:max` - MAX(field)
- `:number` - Custom SQL expression

---

## Ecto Type → Cube Type Mapping

```
Ecto Type              → Cube Type
----------------------   ------------
:id                    → :number
:binary_id             → :string
:integer               → :number
:float                 → :number
:decimal               → :number
:boolean               → :boolean
:string                → :string
:binary                → :string
:date                  → :time
:time                  → :time
:naive_datetime        → :time
:utc_datetime          → :time
```


## Common Patterns

### Dashboard Query
```elixir
def dashboard_metrics(filters \\ %{}) do
  Customer.df(
    columns: [
      Customer.Dimensions.brand(),
      Customer.Measures.count(),
      Customer.Measures.revenue(),
      Customer.Measures.active_users()
    ],
    where: build_filter_sql(filters),
    order_by: [{3, :desc}],  # Order by revenue
    limit: 10
  )
end
```

### Time Series
```elixir
def daily_signups(start_date, end_date) do
  Customer.df(
    columns: [
      Customer.Dimensions.inserted_at(),
      Customer.Measures.count()
    ],
    where: "inserted_at BETWEEN '#{start_date}' AND '#{end_date}'",
    order_by: [{1, :asc}]
  )
end
```

### Top N Analysis
```elixir
def top_brands(n \\ 10) do
  Customer.df(
    columns: [
      Customer.Dimensions.brand(),
      Customer.Measures.revenue()
    ],
    order_by: [{2, :desc}],
    limit: n
  )
end
```

### Cohort Analysis
```elixir
def cohort_by_signup_month do
  Customer.df(
    columns: [
      Customer.Dimensions.signup_month(),
      Customer.Dimensions.zodiac(),
      Customer.Measures.count(),
      Customer.Measures.active_users()
    ],
    order_by: [{1, :asc}, {3, :desc}]
  )
end
```

---

## Testing

### Test Cube Definition
```elixir
defmodule CustomerTest do
  use ExUnit.Case

  test "cube generates accessor modules" do
    assert Code.ensure_loaded?(Customer.Dimensions)
    assert Code.ensure_loaded?(Customer.Measures)
  end

  test "dimensions list includes expected dimensions" do
    dimensions = Customer.dimensions()
    names = Enum.map(dimensions, & &1.name)

    assert :brand in names
    assert :market in names
  end

  test "measures list includes expected measures" do
    measures = Customer.measures()
    names = Enum.map(measures, & &1.name)

    assert "count" in names or :count in names
    assert :revenue in names
  end
end
```

### Test Query Generation
```elixir
test "df/1 generates correct SQL" do
  # Note: Would need to expose internal QueryBuilder for this
  # Alternatively, test end-to-end with a test database
  {:ok, df} = Customer.df(
    columns: [
      Customer.Dimensions.brand(),
      Customer.Measures.count()
    ],
    limit: 1
  )

  assert df != nil
end
```

---

## Performance Tips

### Limit Results
```elixir
# ❌ Bad - Fetches everything
Customer.df!(columns: [...])

# ✅ Good - Limit what you need
Customer.df!(columns: [...], limit: 100)
```
 
### Use Filtered Measures
```elixir
# ❌ Bad - Filter in application
{:ok, df} = Customer.df(columns: [Customer.Measures.count()])
active_count = df |> filter_in_elixir(...)

# ✅ Good - Filter in database
measure :count,
  name: :active_count,
  filters: [%{sql: "status = 'active'"}]

{:ok, df} = Customer.df(columns: [Customer.Measures.active_count()])
```

---

## Troubleshooting

### "Module not found"
```
** (UndefinedFunctionError) function Customer.Dimensions.brand/0 is undefined

Solution: Run `mix compile` after changing cube definitions
```

---

## Complete Minimal Example

```elixir
# lib/my_app/customer.ex
defmodule MyApp.Customer do
  use Ecto.Schema
  use PowerOfThree

  schema "customer" do
    field :email, :string
    field :brand_code, :string
    timestamps()
  end

  cube :analytics,
    sql_table: "customer" do
    dimension :email
    dimension :brand_code, name: :brand
    measure :count
    time_dimensions()
  end
end

# Usage
iex> {:ok, df} = MyApp.Customer.df(
...>   columns: [
...>     MyApp.Customer.Dimensions.brand(),
...>     MyApp.Customer.Measures.count()
...>   ],
...>   limit: 10
...> )
{:ok, #Explorer.DataFrame<...>}

iex> Explorer.DataFrame.print(df)
+--------+-------------------------+
| brand  | measure(customer.count) |
+========+=========================+
| Nike   | 1500                    |
| Adidas | 1200                    |
| ...    | ...                     |
+--------+-------------------------+
```

---

## Next Steps

- Read [ANALYTICS_WORKFLOW.md](ANALYTICS_WORKFLOW.md) for detailed walkthrough
- Check [PHASE3_INTEGRATION_TEST_RESULTS.md](PHASE3_INTEGRATION_TEST_RESULTS.md) for test results
- Review [CONFIRMED_DF.md](CONFIRMED_DF.md) for live query examples
- Explore `/power-of-three-examples` for working code

---

*Quick reference version 1.0 - December 2025*
