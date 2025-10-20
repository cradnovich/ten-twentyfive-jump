defmodule AdvisorAgent.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  schema "threads" do
    field :title, :string, default: "New Chat"
    field :message_count, :integer, default: 0

    belongs_to :user, AdvisorAgent.User
    has_many :messages, AdvisorAgent.Message, on_delete: :delete_all

    timestamps()
  end

  @doc false
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:user_id, :title, :message_count])
    |> validate_required([:user_id])
  end

  @doc """
  Increments the message count for a thread.
  """
  def increment_message_count(thread) do
    thread
    |> cast(%{message_count: thread.message_count + 1}, [:message_count])
  end

  @doc """
  Updates the title of a thread.
  """
  def update_title(thread, title) do
    thread
    |> cast(%{title: title}, [:title])
    |> validate_required([:title])
  end
end
