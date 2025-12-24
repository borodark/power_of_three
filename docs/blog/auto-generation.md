# Introducing Auto-Generated Cubes: Your AI Pair Programmer for PowerOfThree

> **Start with everything. Keep what performs. Pre-aggregate what matters.**

## TL;DR

PowerOfThree now auto-generates complete cube definitions from your Ecto schemas. Just write `cube :my_cube, sql_table: "my_table"` and get a syntax-highlighted, copy-paste-ready cube definition during compilation.

**Start with everything.** Auto-generation gives you all dimensions and measures.
**Keep what performs.** Copy, paste, delete the noise.
**Pre-aggregate what matters.** Let Cube.js cache what scales.

## The Problem: Cold Start Anxiety

We've all been there. You've got your Ecto schema defined with 15 fields. Now you need to create a Cube.js configuration. Which fields should be dimensions? Which should be measures? What about that `created_at` timestamp - is it useful? Should you create a `count_distinct` for the email field?

You stare at the blank `do...end` block. The cursor blinks. Analysis paralysis sets in.

Meanwhile, your AI assistant is probably going to suggest something like:

```elixir
cube :products, sql_table: "products" do
  dimension(:name)
  dimension(:description)
  dimension(:sku)
  dimension(:active)
  dimension(:inserted_at)
  dimension(:updated_at)

  measure(:count)
  measure(:quantity, type: :sum, name: :quantity_sum)
  measure(:quantity, type: :count_distinct, name: :quantity_distinct)
  measure(:price, type: :sum, name: :price_sum)
end
```

Sound familiar? Your LLM knows the pattern. It generates all the obvious stuff. Then YOU delete 80% of it and keep only what you need.

**So why not automate that first step?**

## The Solution: Generate Everything, Keep What Matters

PowerOfThree's new auto-generation feature does exactly what an LLM would do - but at compile time, with zero tokens spent, and with perfect knowledge of your schema.

### How It Works

Instead of writing:

```elixir
cube :products, sql_table: "products" do
  # ... manual field-by-field definition
end
```

Just write:

```elixir
cube :products, sql_table: "products"
```

That's it. During compilation, PowerOfThree will:

1. **Introspect your Ecto schema** - Read all your field definitions
2. **Generate sensible defaults** - Apply opinionated rules based on field types
3. **Print the equivalent code** - Show you exactly what was generated, syntax-highlighted
4. **Compile it** - Your cube is ready to use immediately

### What Gets Generated?

**Dimensions** (things you group by):
- All string fields (`:string`, `:binary_id`, etc.)
- Boolean fields (`:boolean`)
- Timestamp fields (`:inserted_at`, `:updated_at`, `:date`, `:time`, etc.)

**Measures** (things you aggregate):
- `count` - always included
- For integer fields: **both** `sum` and `count_distinct`
- For float/decimal fields: `sum`

### The Magic: Compile-Time Feedback

Here's where it gets interesting. When you compile, you see:

```elixir
# Auto-generated cube definition (copy-paste ready):

cube :products,
  sql_table: "products" do

  dimension(:name)
  dimension(:description)
  dimension(:sku)
  dimension(:active)
  dimension(:inserted_at)
  dimension(:updated_at)

  measure(:count)
  measure(:id, type: :sum, name: :id_sum)
  measure(:id, type: :count_distinct, name: :id_distinct)
  measure(:quantity, type: :sum, name: :quantity_sum)
  measure(:quantity, type: :count_distinct, name: :quantity_distinct)
  measure(:price, type: :sum, name: :price_sum)
end
```

*(In your terminal, this appears with beautiful syntax highlighting - keywords in yellow, atoms in cyan, options in magenta)*

## The Workflow: Scaffold → Refine → Own

This is the exact workflow you'd follow with an LLM, but faster:

### 1. **Scaffold** - Start with auto-generation

```elixir
defmodule MyApp.Product do
  use Ecto.Schema
  use PowerOfThree

  schema "products" do
    field :name, :string
    field :description, :string
    field :sku, :string
    field :active, :boolean
    field :price, :float
    field :quantity, :integer
    timestamps()
  end

  # Let PowerOfThree generate everything
  cube :products, sql_table: "products"
end
```

Run `mix compile`. See the output.

### 2. **Refine** - Copy and customize

Look at the generated code in your terminal. Think: "Do I really need `id_sum`? Probably not. But `quantity_distinct` is useful."

Copy the output. Paste it into your file. Delete the noise:

```elixir
  cube :products, sql_table: "products" do
    dimension(:name)
    dimension(:active)
    dimension(:inserted_at)

    measure(:count)
    measure(:quantity, type: :sum, name: :total_quantity)
    measure(:quantity, type: :count_distinct, name: :unique_quantities)
    measure(:price, type: :sum, name: :total_revenue)
  end
```

### 3. **Own** - Add business logic

Now you're in control. Add the domain-specific stuff that no auto-generator could know:

```elixir
  cube :products, sql_table: "products" do
    dimension(:name)
    dimension(:active)
    dimension(:inserted_at)

    measure(:count, description: "Total products")

    measure(:quantity,
      type: :sum,
      name: :total_quantity,
      description: "Sum of all product quantities"
    )

    measure(:price,
      type: :sum,
      name: :total_revenue,
      description: "Total revenue from all products",
      filters: [%{sql: "active = true"}]  # Only active products!
    )

    # Domain-specific calculated measure
    measure(:quantity,
      type: :count_distinct,
      name: :reorder_needed,
      description: "Products that need reordering",
      filters: [%{sql: "quantity < 10"}]
    )
  end
```

## The Philosophy: Friction → Flow

The best tools reduce cognitive load at the start, then get out of your way. Auto-generation gives you:

- **Zero mental overhead** - No decisions about which fields to include
- **Immediate feedback** - See what was generated instantly
- **Copy-paste escape hatch** - Switch to explicit mode any time
- **Learning tool** - See the patterns, understand the conventions

This mirrors how developers actually work with AI assistants:
1. Ask for boilerplate
2. Get comprehensive output
3. Delete most of it
4. Keep the gems
5. Add your insights

Except now it's built into your compile step, runs in milliseconds, and costs nothing.

## Implementation Details

For the curious, here's what we built:

### Auto-Generation Rules

When `cube/2` (no block) is called, PowerOfThree:

1. Reads `Module.get_attribute(__MODULE__, :ecto_fields)` at compile time
2. Filters fields by type
3. Generates appropriate dimension/measure macros
4. Delegates to the existing `cube/3` implementation

### Syntax Highlighting

The pretty-printed output uses `IO.ANSI` for terminal colors:

```elixir
def generate_cube_source_code(cube_name, opts, ecto_fields) do
  alias IO.ANSI

  # Build syntax-highlighted strings
  "#{ANSI.yellow()}cube#{ANSI.reset()} #{ANSI.cyan()}:#{cube_name}#{ANSI.reset()}"
  # ... etc
end
```

### Backward Compatibility

100% backward compatible. Explicit blocks (`cube/3`) work exactly as before. You can mix and match:

```elixir
# Auto-generated in dev/test
if Mix.env() in [:dev, :test] do
  cube :products, sql_table: "products"
else
  # Explicit in production
  cube :products, sql_table: "products" do
    dimension(:name)
    measure(:count)
  end
end
```

## When to Use Auto-Generation vs Explicit

**Use auto-generation when:**
- Starting a new cube (prototyping)
- You want all fields as dimensions
- Standard aggregations are sufficient
- Learning PowerOfThree conventions

**Use explicit blocks when:**
- You need custom SQL expressions
- You want filtered measures (e.g., "revenue from active customers only")
- You need multi-field dimensions (concatenated)
- You want to exclude most fields
- Your cube has complex business logic

**Hybrid approach (recommended):**
1. Start with auto-generation
2. See what gets generated
3. Copy the output
4. Delete the obvious stuff you don't need
5. Enhance what remains with business logic

## Real-World Example

Here's a before/after from our test suite:

**Before** (manual definition):
```elixir
schema "customers" do
  field :email, :string
  field :first_name, :string
  field :brand_code, :string
  field :market_code, :string
  field :birthday_day, :integer
  field :birthday_month, :integer
  timestamps()
end

# You stare at this for 5 minutes...
cube :customers, sql_table: "customer" do
  # ... what goes here? 🤔
end
```

**After** (with auto-generation):
```elixir
# 1. First compile - generate everything
cube :customers, sql_table: "customer"

# 2. See the output, copy what you need
# 3. Replace with:
cube :customers, sql_table: "customer" do
  dimension(:email)
  dimension(:brand_code)
  dimension(:market_code)

  measure(:count)
  measure(:email, type: :count_distinct, name: :unique_customers)

  # Now add your domain knowledge
  measure(:email,
    type: :count_distinct,
    name: :aquarius_customers,
    filters: [%{
      sql: "(birthday_month = 1 AND birthday_day >= 20) OR
            (birthday_month = 2 AND birthday_day <= 18)"
    }]
  )
end
```

## Test Coverage

We added comprehensive test coverage:

- **21 new tests** for auto-generation
- **241 total tests**, all passing
- Tests for dimensions, measures, accessors, YAML generation
- Backward compatibility tests

## Try It Now

Update PowerOfThree and try the new workflow:

```elixir
# In your schema file
defmodule MyApp.Order do
  use Ecto.Schema
  use PowerOfThree

  schema "orders" do
    field :customer_email, :string
    field :total_amount, :float
    field :status, :string
    field :item_count, :integer
    timestamps()
  end

  # Just this - no block!
  cube :orders, sql_table: "orders"
end
```

Run `mix compile` and watch the magic happen in your terminal.

## The Bigger Picture

This feature embodies a philosophy we're embracing across PowerOfThree:

> **Give developers the full picture, then let them carve out what they need.**

Rather than forcing manual, incremental definition (which leads to analysis paralysis), we generate comprehensive defaults and make it trivial to refine them.

It's the same reason LLMs are effective - they lower the activation energy for starting, then give you something concrete to react to. Editing is easier than creating.

But unlike an LLM:
- It's instant (compile-time)
- It's free (no API costs)
- It's deterministic (same input = same output)
- It knows your exact schema (no hallucinations)

### Why Bother Defining Cubes At All?

Once you've defined your cubes (whether auto-generated or hand-crafted), the real magic happens: **[pre-aggregations](https://cube.dev/docs/product/caching/getting-started-pre-aggregations)**.

Cube.js can pre-calculate and cache your aggregations, turning queries that would scan millions of rows into instant lookups. Your carefully curated dimensions and measures become the foundation for blazing-fast analytics.

As the [Analytics Workflow guide](../ANALYTICS_WORKFLOW.md) reminds us: realize that it was all for caching and pre-aggregations. The cube definitions you refine today become the performance optimizations that scale tomorrow.

Auto-generation gets you there faster - start with everything, keep what performs, pre-aggregate what matters.

## What's Next?

We're exploring:

- **Smart filtering** - Detect common patterns (e.g., "if field contains 'email', suggest count_distinct")
- **YAML preview** - Show the generated YAML config in the output
- **Interactive mode** - CLI prompt to select which dimensions/measures to keep
- **Convention profiles** - Different auto-generation rules for different domains (e.g., e-commerce, SaaS, analytics)

## Conclusion

Auto-generation isn't about replacing thoughtful cube design. It's about removing the blank canvas problem.

That's how you work with AI. That's how you should work with your tools.

Now your compile step is your pair programmer.

---

> **Start with everything. Keep what performs. Pre-aggregate what matters.**

This is the new workflow. Auto-generation eliminates analysis paralysis. Copy-paste gives you control. Cube.js delivers the performance.

Your analytics layer just got a lot more ergonomic.

---

**Try it:** Upgrade PowerOfThree, add `cube :my_cube, sql_table: "my_table"` to any schema, run `mix compile`, and see what happens.

**Share it:** Copy the output from your terminal and show us what cubes you're building. We'd love to see what you keep vs. what you delete.

**Extend it:** The code is open source. If you have ideas for smarter defaults, send a PR.

Happy cubing! 🎲

---

*Released in PowerOfThree v0.1.2 - Auto-generation feature*
*Full test suite: 241 tests passing, 100% backward compatible*
*Special thanks to the Cube.js team for building such a great platform*
