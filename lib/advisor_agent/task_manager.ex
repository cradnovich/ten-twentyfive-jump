defmodule AdvisorAgent.TaskManager do
  @moduledoc """
  Manages multi-step tasks that require waiting for external responses.
  """

  alias AdvisorAgent.{OpenAIModels, Repo, Tools, ToolExecutor}
  require Logger

  @doc """
  Creates a new task and saves the conversation history.
  """
  def create_task(user, description, conversation_history, context \\ %{}) do
    Repo.create_task(%{
      user_id: user.id,
      description: description,
      status: "in_progress",
      conversation_history: conversation_history,
      context: context
    })
  end

  @doc """
  Resumes a task with new information (e.g., an email reply).
  """
  def resume_task(task, new_message, user) do
    # Reload user from database to get latest settings (model, API key, etc.)
    fresh_user = Repo.get(AdvisorAgent.User, user.id)

    # Add new message to conversation history
    updated_history = task.conversation_history ++ [new_message]

    # Continue the conversation with the AI
    case continue_task_conversation(updated_history, fresh_user, task) do
      {:ok, response, :completed} ->
        # Task is complete
        Repo.update_task(task, %{
          status: "completed",
          result: response,
          conversation_history: updated_history
        })

      {:ok, _response, :waiting} ->
        # Task needs more time/responses
        Repo.update_task(task, %{
          status: "waiting_for_response",
          conversation_history: updated_history
        })

      {:error, error} ->
        Repo.update_task(task, %{
          status: "failed",
          error: error,
          conversation_history: updated_history
        })
    end
  end

  # Continues a task conversation with tool calling support.
  defp continue_task_conversation(conversation_history, user, task) do
    # Build system message with task context
    system_content = """
    You are continuing a multi-step task for a financial advisor.

    Task: #{task.description}
    Context: #{inspect(task.context)}

    Continue working on this task. Use the available tools to complete the task.
    When the task is complete, respond with a summary and include the phrase "TASK_COMPLETE" at the end.
    If you need to wait for more information, respond with what you're waiting for and include "WAITING_FOR_RESPONSE" at the end.
    """

    messages = [%{"role" => "system", "content" => system_content}] ++ conversation_history

    # Call OpenAI with tools
    case handle_tool_calling_loop(messages, user, 0) do
      {:ok, response} ->
        cond do
          String.contains?(response, "TASK_COMPLETE") ->
            clean_response = String.replace(response, "TASK_COMPLETE", "") |> String.trim()
            {:ok, clean_response, :completed}

          String.contains?(response, "WAITING_FOR_RESPONSE") ->
            clean_response =
              String.replace(response, "WAITING_FOR_RESPONSE", "") |> String.trim()

            {:ok, clean_response, :waiting}

          true ->
            {:ok, response, :waiting}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_tool_calling_loop(messages, user, iteration) do
    # Prevent infinite loops
    if iteration > 10 do
      {:error, "Maximum tool calling iterations reached"}
    else
      # Get tool definitions
      tools = Tools.get_tool_definitions()

      # Call OpenAI with tools
      case call_openai_with_tools(messages, tools, user) do
        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => nil}}
        when not is_nil(content) ->
          # No tool calls, we have the final response
          {:ok, content}

        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) and tool_calls != [] ->
          # LLM wants to call tools
          Logger.info("Task: LLM requested #{length(tool_calls)} tool call(s)")

          # Add assistant message with tool calls to conversation
          messages =
            messages ++ [%{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}]

          # Execute each tool call
          tool_results =
            Enum.map(tool_calls, fn tool_call ->
              tool_name = tool_call["function"]["name"]
              arguments = Jason.decode!(tool_call["function"]["arguments"])

              Logger.info("Task: Executing tool: #{tool_name}")

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
          {:ok, content || "I'm not sure how to continue."}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp call_openai_with_tools(messages, tools, user) do
    # Get user's preferred model or use default
    model_string = if user.selected_model do
      user.selected_model
    else
      OpenAIModels.to_string(OpenAIModels.default_chat_model())
    end

    # Get user's API key if provided
    api_key = user.openai_api_key

    # Log the parameters being sent to OpenAI
    Logger.info("=== TaskManager calling OpenAI ===")
    Logger.info("Model: #{model_string}")
    Logger.info("Using custom API key: #{if api_key, do: "Yes", else: "No (using system default)"}")

    # Build options for OpenAI call
    options = [
      model: model_string,
      messages: messages,
      tools: tools,
      tool_choice: "auto"
    ]

    # Add API key if user provided one
    options = if api_key, do: Keyword.put(options, :api_key, api_key), else: options

    case OpenAI.chat_completion(options) do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        {:ok, message}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Finds tasks that might be relevant to a new event (e.g., incoming email).
  """
  def find_relevant_tasks(user_id, query_text) do
    # Get all pending tasks for this user
    tasks = Repo.get_pending_tasks(user_id)

    # Simple relevance check - in production you'd use embeddings
    Enum.filter(tasks, fn task ->
      String.contains?(String.downcase(task.description), String.downcase(query_text)) or
        String.contains?(
          String.downcase(inspect(task.context)),
          String.downcase(query_text)
        )
    end)
  end
end
