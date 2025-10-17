defmodule AdvisorAgent.TokenRefresher do
  @moduledoc """
  Handles OAuth token refresh for Google and Hubspot.
  """

  alias AdvisorAgent.{Repo, User}
  require Logger

  @google_token_url "https://oauth2.googleapis.com/token"
  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"

  @doc """
  Refreshes a user's Google access token if it's expired or about to expire.
  Returns {:ok, new_token} or {:error, reason}.
  """
  def refresh_google_token(user) do
    if token_needs_refresh?(user.google_token_expires_at) do
      Logger.info("Refreshing Google token for user #{user.id}")

      google_client_id = System.get_env("GOOGLE_CLIENT_ID")
      google_client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

      params = %{
        client_id: google_client_id,
        client_secret: google_client_secret,
        refresh_token: user.google_refresh_token,
        grant_type: "refresh_token"
      }

      case Req.post(@google_token_url, form: params) do
        {:ok, %Req.Response{status: 200, body: response}} ->
          new_access_token = response["access_token"]
          expires_in = response["expires_in"]

          # Calculate new expiration time
          expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

          # Update user in database
          user
          |> User.update_google_credentials(%{
            google_access_token: new_access_token,
            google_token_expires_at: expires_at
          })
          |> Repo.update()

          {:ok, new_access_token}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error(
            "Failed to refresh Google token: Status #{status}, Body: #{inspect(body)}"
          )

          {:error, :failed_to_refresh_token}

        {:error, error} ->
          Logger.error("Failed to refresh Google token: #{inspect(error)}")
          {:error, error}
      end
    else
      # Token is still valid
      {:ok, user.google_access_token}
    end
  end

  @doc """
  Refreshes a user's Hubspot access token if it's expired or about to expire.
  Returns {:ok, new_token} or {:error, reason}.
  """
  def refresh_hubspot_token(user) do
    if token_needs_refresh?(user.hubspot_token_expires_at) do
      Logger.info("Refreshing Hubspot token for user #{user.id}")

      hubspot_client_id = System.get_env("HUBSPOT_CLIENT_ID")
      hubspot_client_secret = System.get_env("HUBSPOT_CLIENT_SECRET")

      params = %{
        grant_type: "refresh_token",
        client_id: hubspot_client_id,
        client_secret: hubspot_client_secret,
        refresh_token: user.hubspot_refresh_token
      }

      case Req.post(@hubspot_token_url, form: params) do
        {:ok, %Req.Response{status: 200, body: response}} ->
          new_access_token = response["access_token"]
          expires_in = response["expires_in"]

          # Calculate new expiration time
          expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

          # Update user in database
          user
          |> User.update_hubspot_credentials(%{
            hubspot_access_token: new_access_token,
            hubspot_token_expires_at: expires_at
          })
          |> Repo.update()

          {:ok, new_access_token}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error(
            "Failed to refresh Hubspot token: Status #{status}, Body: #{inspect(body)}"
          )

          {:error, :failed_to_refresh_token}

        {:error, error} ->
          Logger.error("Failed to refresh Hubspot token: #{inspect(error)}")
          {:error, error}
      end
    else
      # Token is still valid
      {:ok, user.hubspot_access_token}
    end
  end

  @doc """
  Gets a user with refreshed tokens. Automatically refreshes if needed.
  """
  def get_user_with_fresh_tokens(user_id) do
    user = Repo.get(User, user_id)

    if user do
      # Refresh Google token if needed
      user =
        case refresh_google_token(user) do
          {:ok, _token} -> Repo.get(User, user_id)
          {:error, _} -> user
        end

      # Refresh Hubspot token if needed
      user =
        case refresh_hubspot_token(user) do
          {:ok, _token} -> Repo.get(User, user_id)
          {:error, _} -> user
        end

      user
    else
      nil
    end
  end

  # Private helper to check if a token needs refresh
  # Refresh if token expires within the next 5 minutes
  defp token_needs_refresh?(nil), do: false

  defp token_needs_refresh?(expires_at) do
    now = DateTime.utc_now()
    # Add 5 minute buffer
    buffer_time = DateTime.add(now, 300, :second)
    DateTime.compare(buffer_time, expires_at) == :gt
  end
end
