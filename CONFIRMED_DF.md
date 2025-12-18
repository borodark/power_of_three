# Landing

Looks like we landed in YUL

## Connecting and Exploring Accessors

```elixir
# Connect to Cube
iex(one@localhost)5> {:ok, qub} = PowerOfThree.CubeConnection.connect(
  driver_path: Path.expand("_build/dev/lib/adbc/priv/lib/libadbc_driver_cube.so", __DIR__),
  token: "test"
)
{:ok, #PID<0.1376.0>}

# Get all Customer dimensions as a list
iex(one@localhost)6> PotExamples.Customer.dimensions()
[
  %PowerOfThree.DimensionRef{
    name: :email_per_brand_per_market,
    module: PotExamples.Customer,
    type: :string,
    sql: "brand_code||market_code||email",
    meta: %{ecto_fields: [:brand_code, :market_code, :email]},
    description: nil,
    primary_key: true,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :given_name,
    module: PotExamples.Customer,
    type: :string,
    sql: "first_name",
    meta: %{ecto_field: :first_name, ecto_field_type: :string},
    description: "good documentation",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :zodiac,
    module: PotExamples.Customer,
    type: :string,
    sql: "CASE\nWHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 'Aquarius'\nWHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 'Pisces'\nWHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 'Aries'\nWHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 'Taurus'\nWHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 'Gemini'\nWHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 'Cancer'\nWHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 'Leo'\nWHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 'Virgo'\nWHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 'Libra'\nWHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 'Scorpio'\nWHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 'Sagittarius'\nWHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 'Capricorn'\nELSE 'Professor Abe Weissman'\nEND\n",
    meta: %{ecto_fields: [:birthday_day, :birthday_month]},
    description: "SQL for a zodiac sign for given [:birthday_day, :birthday_month], not _gyroscope_, TODO unicode of Emoji",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :star_sector,
    module: PotExamples.Customer,
    type: :number,
    sql: "CASE\nWHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 0\nWHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 1\nWHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 2\nWHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 3\nWHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 4\nWHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 5\nWHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 6\nWHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 7\nWHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 8\nWHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 9\nWHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 10\nWHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 11\nELSE -1\nEND\n",
    meta: %{ecto_fields: [:birthday_day, :birthday_month]},
    description: "integer from 0 to 11 for zodiac signs",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :bm_code,
    module: PotExamples.Customer,
    type: :string,
    sql: "brand_code|| '_' || market_code",
    meta: %{ecto_fields: [:brand_code, :market_code]},
    description: nil,
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :brand,
    module: PotExamples.Customer,
    type: :string,
    sql: "brand_code",
    meta: %{ecto_field: :brand_code, ecto_field_type: :string},
    description: "Beer",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :market,
    module: PotExamples.Customer,
    type: :string,
    sql: "market_code",
    meta: %{ecto_field: :market_code, ecto_field_type: :string},
    description: "market_code, like AU",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :updated,
    module: PotExamples.Customer,
    type: :time,
    sql: "updated_at",
    meta: %{ecto_field: :updated_at, ecto_field_type: :naive_datetime},
    description: "updated_at timestamp",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :inserted_at,
    module: PotExamples.Customer,
    type: :time,
    sql: "inserted_at",
    meta: %{ecto_field: :inserted_at},
    description: "inserted_at",
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  }
]

# Get all Customer measures as a list
iex(one@localhost)7> PotExamples.Customer.measures()
[
  %PowerOfThree.MeasureRef{
    name: "count",
    module: PotExamples.Customer,
    type: :count,
    sql: nil,
    meta: nil,
    description: "no need for fields for :count type measure",
    filters: nil,
    format: nil
  },
  %PowerOfThree.MeasureRef{
    name: :emails_distinct,
    module: PotExamples.Customer,
    type: :count_distinct,
    sql: :email,
    meta: %{ecto_field: :email, ecto_type: :string},
    description: "count distinct of emails",
    filters: nil,
    format: nil
  },
  %PowerOfThree.MeasureRef{
    name: :aquarii,
    module: PotExamples.Customer,
    type: :count_distinct,
    sql: :email,
    meta: %{ecto_field: :email, ecto_type: :string},
    description: "Filtered by start sector = 0",
    filters: [
      %{
        sql: "(birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)"
      }
    ],
    format: nil
  }
]

# Get all Order measures as a list
iex(one@localhost)8> PotExamples.Order.measures()
[
  %PowerOfThree.MeasureRef{
    name: "subtotal_amount",
    module: PotExamples.Order,
    type: :avg,
    sql: :subtotal_amount,
    meta: %{ecto_field: :subtotal_amount, ecto_type: :integer},
    description: nil,
    filters: nil,
    format: nil
  },
  %PowerOfThree.MeasureRef{
    name: "tax_amount",
    module: PotExamples.Order,
    type: :sum,
    sql: :tax_amount,
    meta: %{ecto_field: :tax_amount, ecto_type: :integer},
    description: nil,
    filters: nil,
    format: :currency
  },
  %PowerOfThree.MeasureRef{
    name: "total_amount",
    module: PotExamples.Order,
    type: :sum,
    sql: :total_amount,
    meta: %{ecto_field: :total_amount, ecto_type: :integer},
    description: nil,
    filters: nil,
    format: nil
  },
  %PowerOfThree.MeasureRef{
    name: "discount_total_amount",
    module: PotExamples.Order,
    type: :sum,
    sql: :discount_total_amount,
    meta: %{ecto_field: :discount_total_amount, ecto_type: :integer},
    description: nil,
    filters: nil,
    format: nil
  },
  %PowerOfThree.MeasureRef{
    name: "discount_and_tax",
    module: PotExamples.Order,
    type: :number,
    sql: "sum(discount_total_amount + tax_amount)",
    meta: nil,
    description: nil,
    filters: nil,
    format: :currency
  },
  %PowerOfThree.MeasureRef{
    name: "count",
    module: PotExamples.Order,
    type: :count,
    sql: nil,
    meta: nil,
    description: nil,
    filters: nil,
    format: nil
  }
]

# Get all Order dimensions as a list
iex(one@localhost)9> PotExamples.Order.dimensions()
[
  %PowerOfThree.DimensionRef{
    name: :order_id,
    module: PotExamples.Order,
    type: :number,
    sql: "id",
    meta: %{ecto_field: :id, ecto_field_type: :id},
    description: nil,
    primary_key: true,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :FIN,
    module: PotExamples.Order,
    type: :string,
    sql: "financial_status",
    meta: %{ecto_field: :financial_status, ecto_field_type: :string},
    description: nil,
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :FUL,
    module: PotExamples.Order,
    type: :string,
    sql: "fulfillment_status",
    meta: %{ecto_field: :fulfillment_status, ecto_field_type: :string},
    description: nil,
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: "market_code",
    module: PotExamples.Order,
    type: :string,
    sql: "market_code",
    meta: %{ecto_field: :market_code, ecto_field_type: :string},
    description: nil,
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  },
  %PowerOfThree.DimensionRef{
    name: :brand,
    module: PotExamples.Order,
    type: :string,
    sql: "brand_code",
    meta: %{ecto_fields: [:brand_code]},
    description: nil,
    primary_key: false,
    format: nil,
    propagate_filters_to_sub_query: nil,
    public: nil
  }
]
```

## Querying with df!/1

### Customer Query - Zodiac Signs

```elixir
# Query Customer cube using module accessors
iex(one@localhost)17> PotExamples.Customer.df!(
  columns: [
    PotExamples.Customer.Dimensions.star_sector(),
    PotExamples.Customer.Dimensions.zodiac(),
    PotExamples.Customer.Measures.count()
  ],
  connection: qub
) |> Explorer.DataFrame.print(limit: :infinity)



+--------------------------------------------------------------------+
|             Explorer DataFrame: [rows: 13, columns: 3]             |
+-----------------------------+-------------+------------------------+
| measure(of_customers.count) | star_sector |         zodiac         |
|            <s64>            |    <f64>    |        <string>        |
+=============================+=============+========================+
| 1242                        | 5.0         | Cancer                 |
| 1082                        | 9.0         | Scorpio                |
| 1201                        | 3.0         | Taurus                 |
| 1153                        | 8.0         | Libra                  |
| 1188                        | 7.0         | Virgo                  |
| 1241                        | 4.0         | Gemini                 |
| 1188                        | 1.0         | Pisces                 |
| 1208                        | 6.0         | Leo                    |
| 1158                        | 10.0        | Sagittarius            |
| 42792                       | -1.0        | Professor Abe Weissman |
| 1133                        | 11.0        | Capricorn              |
| 1215                        | 0.0         | Aquarius               |
| 1199                        | 2.0         | Aries                  |
+-----------------------------+-------------+------------------------+

:ok
```

### Order Query - Revenue by Brand

```elixir
# Query Order cube using module accessors
iex(one@localhost)26> PotExamples.Order.df!(
  columns: [
    PotExamples.Order.Measures.subtotal_amount(),
    PotExamples.Order.Measures.count(),
    PotExamples.Order.Dimensions.brand()
  ],
  connection: qub
) |> Explorer.DataFrame.print(limit: :infinity)

+------------------------------------------------------------------------------+
|                  Explorer DataFrame: [rows: 34, columns: 3]                  |
+--------------------+-----------------------+---------------------------------+
|       brand        | measure(orders.count) | measure(orders.subtotal_amount) |
|      <string>      |         <s64>         |              <f64>              |
+====================+=======================+=================================+
| Amstel             | 15890                 | 2132.695028319698               |
| Becks              | 15925                 | 2133.7591836734696              |
| Birra Moretti      | 15902                 | 2151.898503332914               |
| Blue Moon          | 16002                 | 2172.3542057242844              |
| BudLight           | 15833                 | 2150.4294827259523              |
| Budweiser          | 15688                 | 2145.915795512494               |
| Carlsberg          | 15837                 | 2167.716170991981               |
| Coors lite         | 16144                 | 2138.7765733399406              |
| Corona Extra       | 16090                 | 2149.8628962088255              |
| Delirium Noctorum' | 15785                 | 2150.947671840355               |
| Delirium Tremens   | 15904                 | 2142.342429577465               |
| Dos Equis          | 15931                 | 2144.9996233758084              |
| Fosters            | 15993                 | 2158.3047583317702              |
| Guinness           | 16086                 | 2148.7577396493843              |
| Harp               | 16043                 | 2140.9031976562987              |
| Heineken           | 15803                 | 2155.0800480921343              |
| Hoegaarden         | 15805                 | 2159.342929452705               |
| Kirin Inchiban     | 15875                 | 2151.6735118110237              |
| Leffe              | 15981                 | 2136.280583192541               |
| Lowenbrau          | 15955                 | 2127.4642431839547              |
| Miller Draft       | 15888                 | 2161.012525176234               |
| Murphys            | 15961                 | 2156.6232692187205              |
| Pabst Blue Ribbon  | 16037                 | 2153.296252416287               |
| Pacifico           | 15905                 | 2120.824331971078               |
| Patagonia          | 16110                 | 2122.4302917442583              |
| Paulaner           | 15839                 | 2140.601489993055               |
| Quimes             | 15681                 | 2145.463108220139               |
| Red Stripe         | 15957                 | 2147.2993043805227              |
| Rolling Rock       | 15810                 | 2137.029411764706               |
| Samuel Adams       | 15687                 | 2141.9038694460382              |
| Sapporo Premium    | 15730                 | 2140.2146853146855              |
| Sierra Nevada      | 15930                 | 2150.4951663527936              |
| Stella Artois      | 16241                 | 2147.856782217844               |
| Tsingtao           | 15941                 | 2143.970767204065               |
+--------------------+-----------------------+---------------------------------+

:ok
```

## Summary

The examples above demonstrate:

1. **List Accessors**: `Customer.dimensions()` and `Customer.measures()` return lists of fully resolved structs
2. **Module Accessors**: `Customer.Dimensions.brand()` and `Customer.Measures.count()` for direct access
3. **DataFrame Queries**: Using `df!/1` with module accessors to build and execute queries
4. **Explorer Integration**: Results automatically converted to Explorer DataFrames when available
