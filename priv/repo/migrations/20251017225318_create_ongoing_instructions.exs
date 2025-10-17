defmodule AdvisorAgent.Repo.Migrations.CreateOngoingInstructions do
  use Ecto.Migration

  def change do
    create table(:ongoing_instructions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create index(:ongoing_instructions, [:user_id])
    create index(:ongoing_instructions, [:active])
  end
end
