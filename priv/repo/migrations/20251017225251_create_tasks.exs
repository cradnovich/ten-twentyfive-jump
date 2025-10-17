defmodule AdvisorAgent.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :description, :text, null: false
      add :status, :string, default: "pending", null: false
      add :conversation_history, :jsonb, default: "[]"
      add :context, :jsonb, default: "{}"
      add :result, :text
      add :error, :text

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
  end
end
