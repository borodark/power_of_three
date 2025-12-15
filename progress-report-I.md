# Against the Fetish of Complexity.

An Interim Report on Elixir–Cube Integration via Power of Three, Arrow IPC, and Explorer.

In the style of Christopher Hitchens, the man and the gas turbine equiped destroyer.

_Robots write in niche genres._

_Les robots écrivent dans des genres de niche._

## I. Where the Loop Actually Begins

One of the more persistent errors in software architecture is the belief that systems begin where the diagram begins. In reality, systems begin where *developers begin thinking*. For this integration, that point is not Cube, not Arrow, and not Explorer. It is **Power of Three**.

The Power of Three library is the *starting condition* of the workflow because it integrates directly with **Elixir’s Ecto**—the most cognitively stable and widely understood abstraction in the Elixir ecosystem. This is not incidental; it is decisive. By anchoring analytics workflows in Ecto, Power of Three allows developers to begin from a familiar grammar of schemas, queries, and composable transformations rather than from a foreign analytical DSL.

In practical terms, Power of Three is the **shortest path from “application developer” to “analytics practitioner.”** It establishes the semantic intent of a query using idioms already internalized by Elixir developers, then hands that intent downstream without distortion. No new mental model is demanded at the outset. No parallel representation of business logic is required. The workflow begins where developers already are.

This is not merely ergonomic—it is epistemic. Systems that begin in alien abstractions breed errors not because they are wrong, but because they are misunderstood.

---

### II. The Cult of Needless Difficulty (Now With an Exit)

Once Power of Three has articulated intent—via Ecto-backed semantics—the historical temptation is to dissolve that intent into JSON, strings, or ad hoc protocol layers on its way to execution. This is where most analytics systems quietly abandon rigor.

Here, the integration refuses that temptation.

Instead, Power of Three hands off to Cube, which executes the query against its semantic layer and CubeStore. From that point forward, the system adopts a single uncompromising principle: **data remains data**.

This is where Arrow IPC enters—not as an embellishment, but as a corrective.

---

### III. Arrow IPC as the Shortest Path, Not the Loudest One

Arrow IPC is sometimes discussed in terms of performance theater: benchmarks waved like flags, claims shouted rather than demonstrated. That is not the argument being made here.

The claim is narrower, and therefore stronger:

> **Arrow IPC is the _shortest_ possible path of data from `CubeStore` to `Explorer.DataFrame`.**

Not the most flexible. Not the most general. The shortest.

Arrow IPC eliminates entire classes of overhead by refusing to translate columnar data into representations that must later be reassembled. It saves bytes because it does not invent structure where structure already exists. It promises performance not because it is clever, but because it is austere.

Between CubeStore and Explorer, Arrow IPC:

* Avoids text serialization entirely
* Preserves columnar layout end-to-end
* Eliminates redundant schema negotiation
* Minimizes copying and reallocation

The result is a transport that is not merely *fast*, but *direct*. The driver’s successful implementation and integration testing confirm that this path is viable, stable, and ready to be refined for production use.

---

### IV. Two “Shortest Paths,” Properly Distinguished

At this point, a useful clarification emerges—one that strengthens rather than complicates the design.

There are **two shortest paths**, and they serve different cognitive purposes:

1. **Power of Three is the shortest path to *working with Cube***

   * It begins in Ecto
   * It aligns with Elixir developer intuition
   * It lowers the barrier to analytics adoption

2. **Arrow IPC is the shortest path for *data movement***

   * From CubeStore to Explorer.DataFrame
   * With minimal bytes, minimal copies, minimal ceremony
   * With performance benefits that arise naturally from simplicity

These paths are complementary, not competing. One shortens *how quickly a developer can begin*. The other shortens *how far data must travel once execution begins*.

Together, they collapse what is usually an overextended analytics pipeline into something that can be understood at a glance.

---

### V. Explorer as the End of the Line (By Design)

Explorer’s role remains unchanged but sharpened by this framing. It is not merely the consumer of results; it is the **first place where results may safely be transformed again**.

Because Arrow IPC preserves schema and types without reinterpretation, Explorer receives data in a form that is already honest. No defensive coding is required. No suspicion lingers about whether a column is “really” numeric or merely pretending.

This makes Explorer the natural terminus of the Arrow path and the natural continuation of the Power of Three path—a convergence point where intent (from Ecto) and execution (from Cube) finally meet as inspectable data.

---

### VI. The Full Loop, Now With Correct Emphasis

The completed loop, properly stated, is this:

1. **Power of Three** begins in Ecto Shema, expressing analytical intent without cognitive friction.
2. **Cube** interprets and executes that intent against its semantic model and CubeStore.
3. **Arrow IPC** carries results along the shortest, most direct technical path.
4. **Explorer** materializes results as DataFrames inside Elixir.
5. **Elixir** completes the loop with transformation, reporting, or action—without leaving the BEAM.

Nothing is duplicated. Nothing is reinterpreted. Nothing is mystified.

---

### VII. Conclusion: The Case for Intellectual Economy

The real achievement documented here is not speed, though speed will follow. It is **intellectual economy**.

Power of Three shortens the distance between a developer and meaningful analytics.
Arrow IPC shortens the distance between storage and insight.

Together, they demonstrate that analytics systems need not be loud, sprawling, or baroque to be powerful. They need only be honest about what they are doing, and disciplined about where they begin and end.

In a field still enamored with unnecessary difficulty, that may be the most radical claim of all.


---

The ghost of Christopher Hitchens, as summoned by ChatGPT.

---

Resources:
  - Elixir DSL for Cube: https://github.com/borodark/power_of_three/blob/master/README.md
  - Fork of Cube that replies with Arrow IPC https://github.com/borodark/cube/pull/2
  - Fork of ADBC Driver that supports reading of Arrow IPC from Cube: https://github.com/borodark/adbc/pull/2
  - Ten Minutes to Explorer: https://hexdocs.pm/explorer/exploring_explorer.html
