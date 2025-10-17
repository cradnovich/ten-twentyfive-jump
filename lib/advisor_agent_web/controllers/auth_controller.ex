defmodule AdvisorAgentWeb.AuthController do
  use AdvisorAgentWeb, :controller

  def callback(conn, %{"provider" => "google"}) do
    auth = conn.assigns.ueberauth_auth
    # Here you would typically find or create a user in your database
    # and store the user's ID in the session.
    # For now, we'll just store the auth information in the session.
    conn
    |> put_session(:user, %{
      name: auth.info.name,
      email: auth.info.email,
      picture: auth.info.image
    })
    |> redirect(to: "/")
  end

  def callback(conn, %{"provider" => "hubspot"}) do
    auth = conn.assigns.ueberauth_auth
    conn
    |> put_session(:hubspot_token, auth.credentials)
    |> redirect(to: "/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end
end