defmodule AdvisorAgentWeb.Plugs.SetCurrentUser do
  import Plug.Conn

  alias AdvisorAgent.Repo
  alias AdvisorAgent.User

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    current_user =
      if user_id do
        Repo.get(User, user_id)
      else
        nil
      end

    assign(conn, :current_user, current_user)
  end
end
