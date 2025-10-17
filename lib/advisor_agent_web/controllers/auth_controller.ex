defmodule AdvisorAgentWeb.AuthController do
  use AdvisorAgentWeb, :controller

  alias AdvisorAgent.{Repo, User}

  def callback(conn, %{"provider" => "google"}) do
    auth = conn.assigns.ueberauth_auth

    # Calculate token expiration time
    expires_at =
      if auth.credentials.expires_at do
        DateTime.from_unix!(auth.credentials.expires_at)
      else
        nil
      end

    # Find or create user
    user =
      case Repo.get_by(User, email: auth.info.email) do
        nil ->
          # Create new user
          %User{}
          |> User.changeset(%{
            email: auth.info.email,
            name: auth.info.name,
            picture: auth.info.image,
            google_access_token: auth.credentials.token,
            google_refresh_token: auth.credentials.refresh_token,
            google_token_expires_at: expires_at
          })
          |> Repo.insert!()

        user ->
          # Update existing user with new Google credentials
          user
          |> User.update_google_credentials(%{
            name: auth.info.name,
            picture: auth.info.image,
            google_access_token: auth.credentials.token,
            google_refresh_token: auth.credentials.refresh_token,
            google_token_expires_at: expires_at
          })
          |> Repo.update!()
      end

    conn
    |> put_session(:user_id, user.id)
    |> redirect(to: "/")
  end

  def callback(conn, %{"provider" => "hubspot"}) do
    auth = conn.assigns.ueberauth_auth

    # Get user_id from session
    user_id = get_session(conn, :user_id)

    if user_id do
      # Calculate token expiration time
      expires_at =
        if auth.credentials.expires_at do
          DateTime.from_unix!(auth.credentials.expires_at)
        else
          nil
        end

      # Update user with Hubspot credentials
      user = Repo.get!(User, user_id)

      user
      |> User.update_hubspot_credentials(%{
        hubspot_access_token: auth.credentials.token,
        hubspot_refresh_token: auth.credentials.refresh_token,
        hubspot_token_expires_at: expires_at
      })
      |> Repo.update!()
    end

    conn
    |> redirect(to: "/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end
end