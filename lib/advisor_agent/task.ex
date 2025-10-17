defmodule AdvisorAgent.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :user_id, :integer
    field :description, :string
    field :status, :string, default: "pending"
    field :conversation_history, {:array, :map}, default: []
    field :context, :map, default: %{}
    field :result, :string
    field :error, :string

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:user_id, :description, :status, :conversation_history, :context, :result, :error])
    |> validate_required([:user_id, :description])
    |> validate_inclusion(:status, ["pending", "in_progress", "waiting_for_response", "completed", "failed"])
  end
end
