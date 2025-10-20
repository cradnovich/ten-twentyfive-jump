defmodule AdvisorAgent.Repo.Migrations.CreateThreads do
  use Ecto.Migration

  def change do
    create table(:threads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, default: "New Chat"
      add :message_count, :integer, default: 0

      timestamps()
    end

    create index(:threads, [:user_id])
    create index(:threads, [:updated_at])
  end
end
