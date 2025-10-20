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

    # Create config with API key if user provided one
    config = if api_key, do: %OpenAI.Config{api_key: api_key}, else: %OpenAI.Config{}

    Logger.info("Generating thread summary with model: #{model_string}")

    case OpenAI.chat_completion(params, config) do
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

  @doc """
  Checks if a thread is ready for summary generation.
  Returns true if the thread has exactly 6 messages (3 exchanges).
  """
  def ready_for_summary?(thread) do
    thread.message_count == 6
  end
end
