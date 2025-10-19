defmodule AdvisorAgent.Repo.Migrations.ChangeEmbeddingDimension do
  use Ecto.Migration

  def up do
    # Delete existing documents since we're changing embedding dimensions
    # Old OpenAI embeddings (1536) are incompatible with Nomic (768)
    execute "TRUNCATE TABLE documents"

    # Drop and recreate the embedding column with new dimension
    alter table(:documents) do
      remove :embedding
    end

    alter table(:documents) do
      add :embedding, :vector, size: 768, null: false
    end
  end

  def down do
    # Revert back to OpenAI embedding dimension
    execute "TRUNCATE TABLE documents"

    alter table(:documents) do
      remove :embedding
    end

    alter table(:documents) do
      add :embedding, :vector, size: 1536, null: false
    end
  end
end
