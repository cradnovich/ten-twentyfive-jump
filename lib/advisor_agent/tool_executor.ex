defmodule AdvisorAgent.ToolExecutor do
  @moduledoc """
  Executes tool calls requested by the AI agent.
  """

  alias AdvisorAgent.{GmailClient, CalendarClient, HubspotClient, Repo}
  require Logger

  @doc """
  Executes a tool call and returns the result.
  """
  def execute_tool(tool_name, arguments, user) do
    Logger.info("Executing tool: #{tool_name} with arguments: #{inspect(arguments)}")

    case tool_name do
      "send_email" ->
        send_email(arguments, user)

      "search_emails" ->
        search_emails(arguments, user)

      "get_calendar_availability" ->
        get_calendar_availability(arguments, user)

      "create_calendar_event" ->
        create_calendar_event(arguments, user)

      "list_calendar_events" ->
        list_calendar_events(arguments, user)

      "lookup_hubspot_contact" ->
        lookup_hubspot_contact(arguments, user)

      "create_hubspot_contact" ->
        create_hubspot_contact(arguments, user)

      "add_hubspot_note" ->
        add_hubspot_note(arguments, user)

      "create_ongoing_instruction" ->
        create_ongoing_instruction(arguments, user)

      "list_ongoing_instructions" ->
        list_ongoing_instructions(user)

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  defp send_email(%{"to" => to, "subject" => subject, "body" => body}, user) do
    case GmailClient.send_email(user.google_access_token, to, subject, body) do
      {:ok, _result} ->
        {:ok, "Email sent successfully to #{to}"}

      {:error, error} ->
        {:error, "Failed to send email: #{inspect(error)}"}
    end
  end

  defp search_emails(%{"query" => query}, user) do
    case GmailClient.search_emails(user.google_access_token, query) do
      {:ok, messages} ->
        {:ok, "Found #{length(messages)} emails matching '#{query}'"}

      {:error, error} ->
        {:error, "Failed to search emails: #{inspect(error)}"}
    end
  end

  defp get_calendar_availability(
         %{"time_min" => time_min, "time_max" => time_max},
         user
       ) do
    case CalendarClient.get_availability(user.google_access_token, time_min, time_max) do
      {:ok, result} ->
        busy_times =
          get_in(result, ["calendars", "primary", "busy"]) || []

        if busy_times == [] do
          {:ok, "You are free between #{time_min} and #{time_max}"}
        else
          busy_slots =
            Enum.map_join(busy_times, ", ", fn slot ->
              "#{slot["start"]} to #{slot["end"]}"
            end)

          {:ok, "Busy times: #{busy_slots}"}
        end

      {:error, error} ->
        {:error, "Failed to get availability: #{inspect(error)}"}
    end
  end

  defp create_calendar_event(arguments, user) do
    %{
      "summary" => summary,
      "start_time" => start_time,
      "end_time" => end_time
    } = arguments

    description = Map.get(arguments, "description", "")
    attendees_list = Map.get(arguments, "attendees", [])

    attendees =
      Enum.map(attendees_list, fn email ->
        %{email: email}
      end)

    event_details = %{
      summary: summary,
      description: description,
      start: %{
        dateTime: start_time,
        timeZone: "America/Los_Angeles"
      },
      end: %{
        dateTime: end_time,
        timeZone: "America/Los_Angeles"
      },
      attendees: attendees
    }

    case CalendarClient.create_event(user.google_access_token, event_details) do
      {:ok, _event} ->
        {:ok, "Calendar event '#{summary}' created successfully on #{start_time}"}

      {:error, error} ->
        {:error, "Failed to create calendar event: #{inspect(error)}"}
    end
  end

  defp list_calendar_events(arguments, user) do
    time_min = Map.get(arguments, "time_min", DateTime.utc_now() |> DateTime.to_iso8601())
    time_max = Map.get(arguments, "time_max")
    max_results = Map.get(arguments, "max_results", 10)

    params =
      [
        timeMin: time_min,
        maxResults: max_results,
        singleEvents: true,
        orderBy: "startTime"
      ]
      |> maybe_add_time_max(time_max)

    case CalendarClient.list_events(user.google_access_token, params) do
      {:ok, events} ->
        if events == [] do
          {:ok, "No upcoming events found"}
        else
          events_summary =
            Enum.map_join(events, "\n", fn event ->
              start = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
              "- #{event["summary"]} on #{start}"
            end)

          {:ok, "Upcoming events:\n#{events_summary}"}
        end

      {:error, error} ->
        {:error, "Failed to list events: #{inspect(error)}"}
    end
  end

  defp lookup_hubspot_contact(%{"query" => query}, user) do
    case HubspotClient.lookup_contact(user.hubspot_access_token, query) do
      {:ok, contact} ->
        {:ok, "Found contact: #{inspect(contact)}"}

      {:error, error} ->
        {:error, "Failed to lookup contact: #{inspect(error)}"}
    end
  end

  defp create_hubspot_contact(arguments, user) do
    case HubspotClient.create_contact(user.hubspot_access_token, arguments) do
      {:ok, contact} ->
        {:ok, "Contact created successfully with ID: #{contact["id"]}"}

      {:error, error} ->
        {:error, "Failed to create contact: #{inspect(error)}"}
    end
  end

  defp add_hubspot_note(
         %{"contact_id" => contact_id, "note_body" => note_body},
         user
       ) do
    case HubspotClient.add_note(user.hubspot_access_token, contact_id, note_body) do
      {:ok, _note} ->
        {:ok, "Note added successfully to contact #{contact_id}"}

      {:error, error} ->
        {:error, "Failed to add note: #{inspect(error)}"}
    end
  end

  defp maybe_add_time_max(params, nil), do: params
  defp maybe_add_time_max(params, time_max), do: Keyword.put(params, :timeMax, time_max)

  defp create_ongoing_instruction(%{"instruction" => instruction}, user) do
    case Repo.create_instruction(%{user_id: user.id, instruction: instruction}) do
      {:ok, _instruction} ->
        {:ok, "Ongoing instruction created successfully: '#{instruction}'"}

      {:error, error} ->
        {:error, "Failed to create ongoing instruction: #{inspect(error)}"}
    end
  end

  defp list_ongoing_instructions(user) do
    instructions = Repo.get_active_instructions(user.id)

    if instructions == [] do
      {:ok, "No active ongoing instructions found."}
    else
      instructions_text =
        Enum.map_join(instructions, "\n", fn inst ->
          "- #{inst.instruction}"
        end)

      {:ok, "Active ongoing instructions:\n#{instructions_text}"}
    end
  end
end
