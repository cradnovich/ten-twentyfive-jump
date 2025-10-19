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
  Updates Gmail sync state for the user.
  """
  def update_gmail_sync_state(user, attrs) do
    user
    |> cast(attrs, [:gmail_newest_synced_date, :gmail_oldest_synced_date, :gmail_last_sync_direction, :gmail_sync_page_token])
  end
end
