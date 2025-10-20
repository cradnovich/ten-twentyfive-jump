defmodule AdvisorAgent.ProactiveAgent do
  @moduledoc """
  Handles proactive behavior based on incoming events and ongoing instructions.
  """

  alias AdvisorAgent.{OpenAIModels, Repo, TaskManager, Tools, ToolExecutor}
  require Logger

  @doc """
  Processes an incoming Gmail event (new email).
  """
  def process_gmail_event(user, email_data) do
    Logger.info("Processing Gmail event for user #{user.id}")

    # Get ongoing instructions
    instructions = Repo.get_active_instructions(user.id)

    # Find relevant tasks (tasks waiting for email responses)
    relevant_tasks =
      TaskManager.find_relevant_tasks(
        user.id,
        email_data["from"] || email_data["subject"] || ""
      )

    # If there are relevant tasks, resume them
    if relevant_tasks != [] do
      Enum.each(relevant_tasks, fn task ->
        Logger.info("Resuming task #{task.id} with new email")

        new_message = %{
          "role" => "user",
          "content" =>
            "New email received from #{email_data["from"]}: Subject: #{email_data["subject"]}, Body: #{email_data["body"]}"
        }

        TaskManager.resume_task(task, new_message, user)
      end)
    end

    # Check if we should proactively take action based on ongoing instructions
    if instructions != [] do
      process_with_instructions(user, email_data, instructions, "new_email")
    end

    :ok
  end

  @doc """
  Processes an incoming Calendar event.
  """
  def process_calendar_event(user, calendar_data) do
    Logger.info("Processing Calendar event for user #{user.id}")

    # Get ongoing instructions
    instructions = Repo.get_active_instructions(user.id)

    # Check if we should proactively take action
    if instructions != [] do
      process_with_instructions(user, calendar_data, instructions, "new_calendar_event")
    end

    :ok
  end

  @doc """
  Processes an incoming Hubspot event (new contact, updated contact, etc).
  """
  def process_hubspot_event(user, hubspot_data) do
    Logger.info("Processing Hubspot event for user #{user.id}")

    # Get ongoing instructions
    instructions = Repo.get_active_instructions(user.id)

    # Check if we should proactively take action
    if instructions != [] do
      process_with_instructions(user, hubspot_data, instructions, "new_hubspot_contact")
    end

    :ok
  end

  # Private function to process an event with ongoing instructions
  defp process_with_instructions(user, event_data, instructions, event_type) do
    # Build system message with ongoing instructions
    instructions_text =
      Enum.map_join(instructions, "\n", fn inst ->
        "- #{inst.instruction}"
      end)

    system_content = """
    You are a proactive AI assistant for a financial advisor.

    A #{event_type} event has occurred:
    #{format_event_data(event_data)}

    You have the following ongoing instructions to consider:
    #{instructions_text}

    Review the event and your ongoing instructions. If any of your instructions apply to this event,
    use the available tools to take the appropriate action.

    If no action is needed, respond with "NO_ACTION_NEEDED".
    """

    messages = [
      %{"role" => "system", "content" => system_content},
      %{"role" => "user", "content" => "Please review the event and take any necessary actions."}
    ]

    # Call OpenAI with tools
    case handle_tool_calling_loop(messages, user, 0) do
      {:ok, response} ->
        if String.contains?(response, "NO_ACTION_NEEDED") do
          Logger.info("No proactive action needed for #{event_type}")
        else
          Logger.info("Proactive agent took action: #{response}")
        end

        :ok

      {:error, error} ->
        Logger.error("Proactive agent error: #{inspect(error)}")
        :error
    end
  end

  defp format_event_data(data) when is_map(data) do
    Enum.map_join(data, "\n", fn {key, value} ->
      "#{key}: #{inspect(value)}"
    end)
  end

  defp format_event_data(data), do: inspect(data)

  defp handle_tool_calling_loop(messages, user, iteration) do
    # Prevent infinite loops
    if iteration > 5 do
      {:error, "Maximum tool calling iterations reached"}
    else
      # Get tool definitions
      tools = Tools.get_tool_definitions()

      # Call OpenAI with tools
      case call_openai_with_tools(messages, tools) do
        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => nil}}
        when not is_nil(content) ->
          # No tool calls, we have the final response
          {:ok, content}

        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) and tool_calls != [] ->
          # LLM wants to call tools
          Logger.info("Proactive agent: LLM requested #{length(tool_calls)} tool call(s)")

          # Add assistant message with tool calls to conversation
          messages =
            messages ++ [%{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}]

          # Execute each tool call
          tool_results =
            Enum.map(tool_calls, fn tool_call ->
              tool_name = tool_call["function"]["name"]
              arguments = Jason.decode!(tool_call["function"]["arguments"])

              Logger.info("Proactive agent: Executing tool: #{tool_name}")

              result =
                case ToolExecutor.execute_tool(tool_name, arguments, user) do
                  {:ok, result} -> result
                  {:error, error} -> "Error: #{error}"
                end

              %{
                "role" => "tool",
                "tool_call_id" => tool_call["id"],
                "content" => result
              }
            end)

          # Add tool results to conversation
          messages = messages ++ tool_results

          # Continue the loop with tool results
          handle_tool_calling_loop(messages, user, iteration + 1)

        {:ok, %{"role" => "assistant", "content" => content}} ->
          # Fallback for when content is present but no tool calls
          {:ok, content || "NO_ACTION_NEEDED"}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp call_openai_with_tools(messages, tools) do
    model_string = OpenAIModels.to_string(OpenAIModels.default_chat_model())

    case OpenAI.chat_completion(
           model: model_string,
           messages: messages,
           tools: tools,
           tool_choice: "auto"
         ) do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        {:ok, message}

      {:error, error} ->
        {:error, error}
    end
  end
end
