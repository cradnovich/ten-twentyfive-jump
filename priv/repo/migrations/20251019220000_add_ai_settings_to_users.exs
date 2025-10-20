defmodule AdvisorAgent.Repo.Migrations.AddAiSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Store user's OpenAI API key (optional - for users who want to use their own key)
      add :openai_api_key, :text

      # Store user's preferred AI model (e.g., "gpt-4o", "gpt-4o-mini", etc.)
      add :selected_model, :string
    end
  end
end
