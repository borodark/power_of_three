How Elixir Macro can help to reduce the entry barriers for Data Analytics solutions.
The cube.dev is the analytics solution that works with a few strokes of yaml DSL.
But who wants to write another yaml DSL? Let’s do it in Ecto.Schema cause we like Elixir.
It’s all boils down to how DB tables becomes Cubes, how one or a few columns become  either a Dimension or Measure.
Writing good SQL is ancient art and will be lost.
The Cube automates generation, deploying and running of the complicate SQLs for analytics with DSL. Cube works with most popular databases.
The Power of Three helps to automate the creation of this DSL. It validates column names against Ecto.Schema so produced cube configs will run right away.
This talk will help a software engineers to go at least shoulder deep into Data Analytics right from Elixir Ecto.Schema modules.

Power of three: DSL for OLAP cubes.
A few Elixir Macro can help reduce the entry barriers for Data Analytics solutions.

The cube.dev is the analytics solution that works with a few strokes of yaml DSL. 
But who wants to write another yaml DSL? Let’s do it in Ecto.Schema cause we like Elixir. 

It’s all boils down to how DB tables becomes Cubes, how one or a few columns become  either a Dimension or Measure. 
Writing good SQL is ancient art and will be lost. The Ecto itself is a DSL.  

Para-phrasing Chef Gusto from the movie Ratatouille: “Everyone can write SQL! But in doesn’t mean everyone should.”
Especially SQL for analytics. 

The Cube automates generation, deploying and running of the complicate SQLs for analytics with DSL. Cube works with most popular databases. 
The Power of Three helps to automate the creation of this DSL. It validates column names against Ecto.Schema so produced cube configs will run right away.

This talk will help a software engineers to go at least shoulder deep into Data Analytics right from Elixir Ecto.Schema modules.
Level: beginners and up. Understanding SQL, Databases as well as understanding of modern software systems engineering challenges in Data Analytics space may help.
 
##

For some who are coming DB admin/developer and not necessary speak OLAP, or DW patois a cubes Dimension and Measure looks easy to internalize, understand.

No-one has to share the spoils of inevitable high value liquidity even with some analytics dude. 

One wants to be in control . let’s define analytics artifacts in the one source file of Ecto.Schema. 

Seen many cleaver writers grinding 2K SQL statements with windows, roll-ups, subqueries in FROM, views, WITH. 

I remove my hat for the brave soul who would inherit this SQL when the original author decides to spawn off _the clever SQL_ consulting business.

The fresh generation of engineers according to many hypotheses, these days will have shorter attention span.

It’s complicated and a lot of things that are important preferably to be explicitly defined for others to better chance to comprehend What’s going on.

it is not uncommon to have CASE statements, buried deeply inside SQL to define categorical variables.

The case statements have to be regularly, updated to reflect new categories and logic to place data into these.

In short, please leave the clever part to the machines.

