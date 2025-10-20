defmodule AdvisorAgent.OpenAIClient do
  @moduledoc """
  Client for interacting with the OpenAI API to generate embeddings.
  """

  alias AdvisorAgent.OpenAIModels

  @doc """
  Generates an embedding for the given text.
  """
  def generate_embedding(text) when is_binary(text) do
    model_string = OpenAIModels.to_string(OpenAIModels.default_embedding_model())

    case OpenAI.embeddings(model: model_string, input: text) do
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
    - model: Atom representing the model (default: :gpt_3_5_turbo)
  """
  def generate_chat_completion(messages, model \\ nil) do
    model_atom = model || OpenAIModels.default_chat_model()
    model_string = OpenAIModels.to_string(model_atom)

    case OpenAI.chat_completion(model: model_string, messages: messages) do
      {:ok, %{choices: [%{"message" => %{"content" => content}} | _rest]}} ->
        {:ok, content}

      {:error, error} ->
        {:error, error}
    end
  end
end
