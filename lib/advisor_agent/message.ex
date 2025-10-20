defmodule AdvisorAgent.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string

    belongs_to :thread, AdvisorAgent.Thread

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:thread_id, :role, :content])
    |> validate_required([:thread_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
