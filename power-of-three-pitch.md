I’ve published an **interim progress report** on an experiment in *reducing—not increasing—the cognitive load of analytics integration* in Elixir:

👉 [Progress Report I: Integrating Elixir Analytics with Cube via Power of Three, Arrow IPC, and Explorer](https://github.com/borodark/power_of_three/blob/master/progress-report-I.md)

It is now **practically and technically proven** that custom Elixir applications can integrate with Cube’s semantic layer while keeping the developer experience grounded in Ecto—and move analytical data from CubeStore to `Explorer.DataFrame` along what is likely the **shortest possible path**.

Two ideas frame the work:

• **Power of Three** is the starting point of the workflow because it integrates directly with Ecto. This makes analytics approachable to Elixir developers gently introducing Cube DSL in form of Elixir Macros.

• **Arrow IPC** is the shortest (and potentially fastest) path for data once execution begins—preserving columnar structure, saving bytes, and delivering results directly into Explorer without detours through JSON or ad-hoc serialization.

The article documents the completed integration, the architectural decisions behind it, and the full analytics loop — from intent expressed within `Ecto.Schema` to Cube execution to Arrow-backed DataFrames—now working end-to-end.

This is an interim report, not a manifesto. But it does suggest that analytics systems can be **simpler, more honest, and easier to reason about** than we’ve come to accept.

Feedback, criticism, and curiosity are all welcome.
