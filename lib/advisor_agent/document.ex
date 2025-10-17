defmodule AdvisorAgent.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :content, :string
    field :embedding, {:array, :float}
    field :metadata, :map

    timestamps()
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:content, :embedding, :metadata])
    |> validate_required([:content, :embedding])
  end
end
