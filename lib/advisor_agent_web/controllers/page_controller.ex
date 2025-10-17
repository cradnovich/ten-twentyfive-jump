defmodule AdvisorAgentWeb.PageController do
  use AdvisorAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
