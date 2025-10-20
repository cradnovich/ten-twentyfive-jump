defmodule AdvisorAgent.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :thread_id, references(:threads, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false

      timestamps()
    end

    create index(:messages, [:thread_id])
    create index(:messages, [:inserted_at])
  end
end
