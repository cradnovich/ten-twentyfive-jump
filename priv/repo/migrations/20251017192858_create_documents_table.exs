defmodule AdvisorAgent.Repo.Migrations.CreateDocumentsTable do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :content, :text, null: false
      add :embedding, :vector, size: 1536, null: false
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end
  end
end
