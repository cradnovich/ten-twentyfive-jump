defmodule AdvisorAgentWeb.Plugs.SetCurrentUser do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> assign(:current_user, get_session(conn, :user))
    |> assign(:hubspot_token, get_session(conn, :hubspot_token))
  end
end
