defmodule AdvisorAgent.OngoingInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  alias AdvisorAgent.User

  schema "ongoing_instructions" do
    belongs_to :user, User
    field :instruction, :string
    field :active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(ongoing_instruction, attrs) do
    ongoing_instruction
    |> cast(attrs, [:user_id, :instruction, :active])
    |> validate_required([:user_id, :instruction])
  end
end
