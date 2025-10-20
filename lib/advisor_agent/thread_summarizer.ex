defmodule AdvisorAgent.ThreadSummarizer do
  @moduledoc """
  Generates AI-powered summaries for chat threads.
  """

  alias AdvisorAgent.{OpenAIModels, Repo}
  require Logger

  @doc """
  Generates a summary title for a thread based on its messages.
  This should be called after a thread has at least 6 messages (3 exchanges).
  """
  def generate_summary(thread, user) do
    # Get user's selected model or use default
    model_string = if user.selected_model do
      user.selected_model
    else
      OpenAIModels.to_string(OpenAIModels.default_chat_model())
    end

    # Get user's API key if provided
    api_key = user.openai_api_key

    # Build conversation context from thread messages
    conversation_text = thread.messages
    |> Enum.take(6)  # Only use first 6 messages for summary
    |> Enum.map(fn msg ->
      role = if msg.role == "user", do: "User", else: "Assistant"
      "#{role}: #{msg.content}"
    end)
    |> Enum.join("\n\n")

    system_prompt = """
    Generate a concise, descriptive title (3-6 words) for this conversation.
    The title should capture the main topic or question.
    Do not use quotes or punctuation in the title.
    Respond with ONLY the title, nothing else.
    """

    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => "Conversation:\n#{conversation_text}"}
    ]

    # Build params for OpenAI call
    params = [
      model: model_string,
      messages: messages,
      max_tokens: 20
    ]

    Logger.info("Generating thread summary with model: #{model_string}")

    # Use direct HTTP call for self-hosted models
    result = if OpenAIModels.self_hosted?(model_string) do
      call_self_hosted_completion(model_string, messages)
    else
      config = if api_key, do: %OpenAI.Config{api_key: api_key}, else: %OpenAI.Config{}
      OpenAI.chat_completion(params, config)
    end

    case result do
      {:ok, %{choices: [%{"message" => %{"content" => title}} | _]}} ->
        clean_title = String.trim(title)
        Logger.info("Generated thread title: #{clean_title}")

        # Update the thread title in the database
        Repo.update_thread_title(thread.id, clean_title)

      {:error, error} ->
        Logger.error("Failed to generate thread summary: #{inspect(error)}")
        {:error, error}
    end
  end

  defp call_self_hosted_completion(model, messages) do
    base_url = Application.get_env(:advisor_agent, :self_hosted_model_url, "http://localhost:8080")
    url = "#{base_url}/v1/chat/completions"

    body = Jason.encode!(%{
      model: model,
      messages: messages,
      max_tokens: 20
    })

    headers = [{"Content-Type", "application/json"}]
    options = [recv_timeout: 120_000, timeout: 120_000]

    case HTTPoison.post(url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, %{choices: [%{"message" => %{"content" => content}}]}}
          {:ok, parsed} ->
            Logger.error("Unexpected self-hosted response format: #{inspect(parsed)}")
            {:error, "Unexpected response format"}
          {:error, decode_error} ->
            {:error, decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Self-hosted API error (#{status_code}): #{response_body}")
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a thread is ready for summary generation.
  Returns true if the thread has exactly 6 messages (3 exchanges).
  """
  def ready_for_summary?(thread) do
    thread.message_count == 6
  end
end
