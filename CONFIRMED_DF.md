# Landing

Looks like we landed in YUL

```iex

iex(one@localhost)11> {:ok, qub} =PowerOfThree.CubeConnection.connect(driver_path: Path.expand("_build/dev/lib/adbc/priv/lib/libadbc_driver_cube.so", __DIR__), token: "test")
{:ok, #PID<0.1393.0>}

iex(one@localhost)12>PotExamples.Customer.df!(columns: [PotExamples.Customer.dimensions().zodiac(), PotExamples.Customer.measures().count()], connection: qub) |> Explorer.DataFrame.print(limit: :infinity)

+------------------------------------------------------+
|      Explorer DataFrame: [rows: 13, columns: 2]      |
+-----------------------------+------------------------+
| measure(of_customers.count) |         zodiac         |
|            <s64>            |        <string>        |
+=============================+========================+
| 1241                        | Gemini                 |
| 1158                        | Sagittarius            |
| 1133                        | Capricorn              |
| 42792                       | Professor Abe Weissman |
| 1201                        | Taurus                 |
| 1082                        | Scorpio                |
| 1153                        | Libra                  |
| 1188                        | Virgo                  |
| 1199                        | Aries                  |
| 1242                        | Cancer                 |
| 1215                        | Aquarius               |
| 1208                        | Leo                    |
| 1188                        | Pisces                 |
+-----------------------------+------------------------+

:ok
iex(one@localhost)13>

iex(one@localhost)7> PotExamples.Customer.df!(columns: [ PotExamples.Customer.dimensions().star_sector(), PotExamples.Customer.dimensions().zodiac(), PotExamples.Customer.measures().count()], connection: qub) |> Explorer.DataFrame.print(limit: :infinity)

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



```

Chers passagers, notre avion a atterri à Montréal !


```iex

iex(one@localhost)5> {:ok, qub} =PowerOfThree.CubeConnection.connect(driver_path: Path.expand("_build/dev/lib/adbc/priv/lib/libadbc_driver_cube.so", __DIR__), token: "test")
{:ok, #PID<0.1145.0>}

iex(one@localhost)6> PotExamples.Order.df!(columns: [PotExamples.Order.measures().count(),PotExamples.Order.dimensions().brand()],connection: qub) |> Explorer.DataFrame.print(limit: :infinity)

+--------------------------------------------+
| Explorer DataFrame: [rows: 34, columns: 2] |
+--------------------+-----------------------+
|       brand        | measure(orders.count) |
|      <string>      |         <s64>         |
+====================+=======================+
| Amstel             | 15890                 |
| Becks              | 15925                 |
| Birra Moretti      | 15902                 |
| Blue Moon          | 16002                 |
| BudLight           | 15833                 |
| Budweiser          | 15688                 |
| Carlsberg          | 15837                 |
| Coors lite         | 16144                 |
| Corona Extra       | 16090                 |
| Delirium Noctorum' | 15785                 |
| Delirium Tremens   | 15904                 |
| Dos Equis          | 15931                 |
| Fosters            | 15993                 |
| Guinness           | 16086                 |
| Harp               | 16043                 |
| Heineken           | 15803                 |
| Hoegaarden         | 15805                 |
| Kirin Inchiban     | 15875                 |
| Leffe              | 15981                 |
| Lowenbrau          | 15955                 |
| Miller Draft       | 15888                 |
| Murphys            | 15961                 |
| Pabst Blue Ribbon  | 16037                 |
| Pacifico           | 15905                 |
| Patagonia          | 16110                 |
| Paulaner           | 15839                 |
| Quimes             | 15681                 |
| Red Stripe         | 15957                 |
| Rolling Rock       | 15810                 |
| Samuel Adams       | 15687                 |
| Sapporo Premium    | 15730                 |
| Sierra Nevada      | 15930                 |
| Stella Artois      | 16241                 |
| Tsingtao           | 15941                 |
+--------------------+-----------------------+

:ok
iex(one@localhost)7>

```
