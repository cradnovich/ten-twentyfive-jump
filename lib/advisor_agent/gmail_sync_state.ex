defmodule AdvisorAgent.GmailSyncState do
  @moduledoc """
  Helper module for managing Gmail sync state and determining sync strategy.
  """

  alias AdvisorAgent.{Repo, User}
  require Logger

  @doc """
  Determines what type of sync should be performed for the user.
  Returns one of:
  - `:initial` - First time sync, fetch recent emails
  - `:forward` - Fetch emails newer than newest synced
  - `:backward` - Continue fetching older emails
  """
  def determine_sync_strategy(user) do
    cond do
      # No sync state yet - initial sync
      is_nil(user.gmail_newest_synced_date) ->
        :initial

      # Last sync was going backward and not complete - continue backward
      user.gmail_last_sync_direction == "backward" ->
        :backward

      # Default: check for new emails (forward sync)
      true ->
        :forward
    end
  end

  @doc """
  Updates the user's Gmail sync state after processing messages.
  """
  def update_sync_state(user, messages, direction, page_token \\ nil) do
    case messages do
      [] ->
        # No messages - mark direction as complete
        attrs = %{
          gmail_last_sync_direction: "complete",
          gmail_sync_page_token: nil
        }
        update_user_sync_state(user, attrs)

      messages when is_list(messages) ->
        # Extract internal dates from message metadata
        internal_dates = extract_internal_dates(messages)

        case {direction, internal_dates} do
          {:forward, dates} when dates != [] ->
            newest = Enum.max(dates)
            attrs = %{
              gmail_newest_synced_date: newest,
              gmail_last_sync_direction: "forward",
              gmail_sync_page_token: page_token
            }
            update_user_sync_state(user, attrs)

          {:backward, dates} when dates != [] ->
            oldest = Enum.min(dates)
            attrs = %{
              gmail_oldest_synced_date: oldest,
              gmail_last_sync_direction: "backward",
              gmail_sync_page_token: page_token
            }
            update_user_sync_state(user, attrs)

          {:initial, dates} when dates != [] ->
            # Initial sync: set both newest and oldest
            attrs = %{
              gmail_newest_synced_date: Enum.max(dates),
              gmail_oldest_synced_date: Enum.min(dates),
              gmail_last_sync_direction: "backward",  # Continue going backward on next run
              gmail_sync_page_token: page_token
            }
            update_user_sync_state(user, attrs)

          _ ->
            {:ok, user}
        end
    end
  end

  @doc """
  Builds a Gmail API query string for date-based filtering.
  """
  def build_date_query(_user, :initial) do
    # For initial sync, get recent emails (no date filter, Gmail returns newest first)
    nil
  end

  def build_date_query(user, :forward) do
    if user.gmail_newest_synced_date do
      # Convert Unix milliseconds to YYYY/MM/DD
      date = format_date_for_gmail(user.gmail_newest_synced_date)
      "after:#{date}"
    else
      nil
    end
  end

  def build_date_query(user, :backward) do
    if user.gmail_oldest_synced_date do
      # Convert Unix milliseconds to YYYY/MM/DD
      date = format_date_for_gmail(user.gmail_oldest_synced_date)
      "before:#{date}"
    else
      nil
    end
  end

  # Private helpers

  defp extract_internal_dates(messages) do
    messages
    |> Enum.map(fn msg ->
      # internalDate is stored in message metadata
      case msg do
        %{"internalDate" => date} when is_binary(date) ->
          String.to_integer(date)
        %{"internalDate" => date} when is_integer(date) ->
          date
        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_date_for_gmail(unix_milliseconds) when is_integer(unix_milliseconds) do
    # Convert Unix milliseconds to DateTime
    datetime = DateTime.from_unix!(unix_milliseconds, :millisecond)
    # Format as YYYY/MM/DD for Gmail API
    Calendar.strftime(datetime, "%Y/%m/%d")
  end

  defp update_user_sync_state(user, attrs) do
    user
    |> User.update_gmail_sync_state(attrs)
    |> Repo.update()
  end
end
