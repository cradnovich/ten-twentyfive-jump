defmodule AdvisorAgent.OpenAIClient do
  @moduledoc """
  Client for interacting with the OpenAI API to generate embeddings.
  """

  alias AdvisorAgent.OpenAIModels
  require Logger

  @doc """
  Generates an embedding for the given text.

  ## Parameters
    - text: The text to generate an embedding for
    - api_key: Optional API key to use (defaults to system config)
  """
  def generate_embedding(text, api_key \\ nil) when is_binary(text) do
    model_string = OpenAIModels.to_string(OpenAIModels.default_embedding_model())

    params = [model: model_string, input: text]
    config = if api_key, do: %OpenAI.Config{api_key: api_key}, else: %OpenAI.Config{}

    case OpenAI.embeddings(params, config) do
      {:ok, %{data: [%{"embedding" => embedding} | _rest]}} ->
        {:ok, embedding}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Generates a chat completion for the given messages.

  ## Parameters
    - messages: List of message maps for the conversation
    - opts: Keyword list of options
      - :model - Atom or string representing the model (default: default_chat_model())
      - :api_key - API key to use (default: system config)
  """
  def generate_chat_completion(messages, opts \\ []) do
    model = Keyword.get(opts, :model) || OpenAIModels.default_chat_model()
    api_key = Keyword.get(opts, :api_key)

    model_string = if is_atom(model) do
      OpenAIModels.to_string(model)
    else
      model
    end

    # Use direct HTTP call for self-hosted models
    if OpenAIModels.self_hosted?(model_string) do
      call_self_hosted_completion(model_string, messages)
    else
      params = [model: model_string, messages: messages]
      config = if api_key, do: %OpenAI.Config{api_key: api_key}, else: %OpenAI.Config{}

      case OpenAI.chat_completion(params, config) do
        {:ok, %{choices: [%{"message" => %{"content" => content}} | _rest]}} ->
          {:ok, content}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp call_self_hosted_completion(model, messages) do
    base_url = Application.get_env(:advisor_agent, :self_hosted_model_url, "http://localhost:8080")
    url = "#{base_url}/v1/chat/completions"

    body = Jason.encode!(%{
      model: model,
      messages: messages
    })

    headers = [{"Content-Type", "application/json"}]
    options = [recv_timeout: 120_000, timeout: 120_000]

    case HTTPoison.post(url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, content}
          {:ok, parsed} ->
            Logger.error("Unexpected self-hosted response format: #{inspect(parsed)}")
            {:error, "Unexpected response format"}
          {:error, decode_error} ->
            {:error, decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Self-hosted API error (#{status_code}): #{response_body}")
        {:error, "HTTP #{status_code}: #{response_body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
