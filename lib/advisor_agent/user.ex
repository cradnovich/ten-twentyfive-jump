defmodule AdvisorAgent.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :picture, :string
    field :google_access_token, :string
    field :google_refresh_token, :string
    field :google_token_expires_at, :utc_datetime
    field :hubspot_access_token, :string
    field :hubspot_refresh_token, :string
    field :hubspot_token_expires_at, :utc_datetime

    # Gmail sync state tracking
    field :gmail_newest_synced_date, :integer
    field :gmail_oldest_synced_date, :integer
    field :gmail_last_sync_direction, :string
    field :gmail_sync_page_token, :string

    # AI model configuration
    field :openai_api_key, :string
    field :selected_model, :string

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :picture,
      :google_access_token,
      :google_refresh_token,
      :google_token_expires_at,
      :hubspot_access_token,
      :hubspot_refresh_token,
      :hubspot_token_expires_at
    ])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end

  @doc """
  Updates Google OAuth credentials for the user.
  """
  def update_google_credentials(user, attrs) do
    user
    |> cast(attrs, [:google_access_token, :google_refresh_token, :google_token_expires_at, :name, :picture])
    |> validate_required([:google_access_token])
  end

  @doc """
  Updates Hubspot OAuth credentials for the user.
  """
  def update_hubspot_credentials(user, attrs) do
    user
    |> cast(attrs, [:hubspot_access_token, :hubspot_refresh_token, :hubspot_token_expires_at])
    |> validate_required([:hubspot_access_token])
  end

  @doc """
  Clears Hubspot OAuth credentials for the user.
  """
  def clear_hubspot_credentials(user) do
    user
    |> cast(%{hubspot_access_token: nil, hubspot_refresh_token: nil, hubspot_token_expires_at: nil}, [:hubspot_access_token, :hubspot_refresh_token, :hubspot_token_expires_at])
  end

  @doc """
  Updates Gmail sync state for the user.
  """
  def update_gmail_sync_state(user, attrs) do
    user
    |> cast(attrs, [:gmail_newest_synced_date, :gmail_oldest_synced_date, :gmail_last_sync_direction, :gmail_sync_page_token])
  end

  @doc """
  Updates AI model configuration for the user.
  """
  def update_ai_settings(user, attrs) do
    user
    |> cast(attrs, [:openai_api_key, :selected_model])
  end
end
