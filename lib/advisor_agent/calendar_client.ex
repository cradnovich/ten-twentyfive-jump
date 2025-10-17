defmodule AdvisorAgent.CalendarClient do
  @moduledoc """
  Client for interacting with the Google Calendar API.
  """

  require Logger

  @calendar_api_base_url "https://www.googleapis.com/calendar/v3"

  @doc """
  Gets the user's availability by checking free/busy times.
  """
  def get_availability(access_token, time_min, time_max, calendar_id \\ "primary") do
    body = %{
      timeMin: time_min,
      timeMax: time_max,
      items: [%{id: calendar_id}]
    }

    case Req.post(@calendar_api_base_url <> "/freeBusy",
           auth: {:bearer, access_token},
           json: body
         ) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to get availability: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to get availability: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to get availability: #{inspect(error)}")
        {:error, "Failed to get availability: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a calendar event.
  """
  def create_event(access_token, event_details, calendar_id \\ "primary") do
    case Req.post(@calendar_api_base_url <> "/calendars/#{calendar_id}/events",
           auth: {:bearer, access_token},
           json: event_details
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to create event: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to create event: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to create event: #{inspect(error)}")
        {:error, "Failed to create event: #{inspect(error)}"}
    end
  end

  @doc """
  Lists events from the calendar.
  """
  def list_events(access_token, opts \\ [], calendar_id \\ "primary") do
    params =
      opts
      |> Enum.into(%{})

    case Req.get(@calendar_api_base_url <> "/calendars/#{calendar_id}/events",
           auth: {:bearer, access_token},
           params: params
         ) do
      {:ok, %Req.Response{status: 200, body: %{"items" => items}}} ->
        {:ok, items}

      {:ok, %Req.Response{status: 200, body: %{}}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to list events: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_list_events}

      {:error, error} ->
        Logger.error("Failed to list events: #{inspect(error)}")
        {:error, :failed_to_list_events}
    end
  end

  @doc """
  Updates a calendar event.
  """
  def update_event(access_token, event_id, event_details, calendar_id \\ "primary") do
    case Req.put(@calendar_api_base_url <> "/calendars/#{calendar_id}/events/#{event_id}",
           auth: {:bearer, access_token},
           json: event_details
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to update event: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to update event: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to update event: #{inspect(error)}")
        {:error, "Failed to update event: #{inspect(error)}"}
    end
  end

  @doc """
  Deletes a calendar event.
  """
  def delete_event(access_token, event_id, calendar_id \\ "primary") do
    case Req.delete(@calendar_api_base_url <> "/calendars/#{calendar_id}/events/#{event_id}",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 204}} ->
        {:ok, :deleted}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to delete event: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to delete event: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to delete event: #{inspect(error)}")
        {:error, "Failed to delete event: #{inspect(error)}"}
    end
  end

  @doc """
  Gets a specific event from the calendar.
  """
  def get_event(access_token, event_id, calendar_id \\ "primary") do
    case Req.get(@calendar_api_base_url <> "/calendars/#{calendar_id}/events/#{event_id}",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to get event: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to get event: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to get event: #{inspect(error)}")
        {:error, "Failed to get event: #{inspect(error)}"}
    end
  end
end
