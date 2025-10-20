defmodule AdvisorAgent.Repo.Migrations.AddActiveThreadToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :active_thread_id, references(:threads, on_delete: :nilify_all)
    end

    create index(:users, [:active_thread_id])
  end
end
