defmodule AdvisorAgentWeb.HealthController do
  use AdvisorAgentWeb, :controller

  def index(conn, _params) do
    # Check database connection
    case Ecto.Adapters.SQL.query(AdvisorAgent.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", message: "database unavailable"})
    end
  end
end
