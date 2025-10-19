defmodule AdvisorAgent.Repo.Migrations.AddGmailSyncStateToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Track the newest email timestamp we've synced (Unix milliseconds from Gmail internalDate)
      add :gmail_newest_synced_date, :bigint

      # Track the oldest email timestamp we've synced (Unix milliseconds from Gmail internalDate)
      add :gmail_oldest_synced_date, :bigint

      # Track which direction we're currently syncing: "forward" (newer), "backward" (older), or "complete"
      add :gmail_last_sync_direction, :string, default: "forward"

      # For resuming pagination if interrupted mid-sync
      add :gmail_sync_page_token, :string
    end
  end
end
