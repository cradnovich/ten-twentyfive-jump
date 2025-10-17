defmodule AdvisorAgent.Repo do
  use Ecto.Repo,
    otp_app: :advisor_agent,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  alias AdvisorAgent.Document

  def search_documents(query_embedding, limit \\ 5) do
    Document
    |> order_by([d], fragment("?<->?", d.embedding, ^query_embedding))
    |> limit(^limit)
    |> Repo.all()
  end
end
