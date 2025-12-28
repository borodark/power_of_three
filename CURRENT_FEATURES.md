✅ COMPLETED: Column aliasing feature

You can now control the names of columns in the returned DataFrame using keyword list syntax:

```elixir
{:ok, df} = Customer.df(
  columns: [
    mah_brand: Customer.Dimensions.brand(),
    mah_people: Customer.Measures.count()
  ],
  limit: 1
)
```

This produces a DataFrame with columns: ["mah_brand", "mah_people"] instead of the default names.

Features:
- ✅ Works with both HTTP and ADBC modes
- ✅ Supports all query options (WHERE, ORDER BY, LIMIT, OFFSET)
- ✅ Backward compatible - plain list syntax still works
- ✅ Comprehensive test coverage (5 HTTP tests)

Implementation details:
- Column refs are parsed to detect keyword list format
- Aliases are extracted and mapped to Cube member names
- DataFrame columns are renamed after query execution
- Works with both normalized names (HTTP) and full member names (ADBC)
