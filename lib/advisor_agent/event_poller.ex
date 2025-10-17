defmodule AdvisorAgent.EventPoller do
  @moduledoc """
  Polls Gmail, Calendar, and Hubspot for new events and triggers proactive behavior.
  """

  use GenServer
  alias AdvisorAgent.{Repo, User, GmailClient, ProactiveAgent, TokenRefresher}
  require Logger

  @poll_interval 60_000  # Poll every 60 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Schedule first poll
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    # Poll for all users
    poll_all_users()

    # Schedule next poll
    schedule_poll()

    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp poll_all_users do
    # Get all users with Google access tokens
    users = Repo.all(User)

    Enum.each(users, fn user ->
      if user.google_access_token do
        # Refresh tokens if needed
        fresh_user = TokenRefresher.get_user_with_fresh_tokens(user.id)
        poll_gmail(fresh_user)
      end
    end)
  end

  defp poll_gmail(user) do
    # Check for new unread emails
    case GmailClient.search_emails(user.google_access_token, "is:unread") do
      {:ok, messages} when is_list(messages) and messages != [] ->
        Logger.info("Found #{length(messages)} unread emails for user #{user.id}")

        # Process each new email
        Enum.each(messages, fn message ->
          message_id = message["id"]

          # Get full email details
          case GmailClient.get_message(user.google_access_token, message_id) do
            {:ok, email_data} ->
              # Process with proactive agent
              Task.start(fn ->
                ProactiveAgent.process_gmail_event(user, email_data)
              end)

            {:error, error} ->
              Logger.error("Failed to get message #{message_id}: #{inspect(error)}")
          end
        end)

      {:ok, []} ->
        # No new emails
        :ok

      {:error, error} ->
        Logger.error("Failed to poll Gmail for user #{user.id}: #{inspect(error)}")
        :error
    end
  end
end
