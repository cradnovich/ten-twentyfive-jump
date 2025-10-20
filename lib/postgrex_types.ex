Postgrex.Types.define(
  AdvisorAgent.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
