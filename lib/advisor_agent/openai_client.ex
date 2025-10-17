defmodule AdvisorAgent.OpenAIClient do
  @moduledoc """
  Client for interacting with the OpenAI API to generate embeddings.
  """

  alias OpenAI

  @embedding_model "text-embedding-ada-002"

  @doc """
  Generates an embedding for the given text.
  """
  def generate_embedding(text) when is_binary(text) do
    case OpenAI.Embeddings.create(@embedding_model, text) do
      {:ok, %{"data" => [%{"embedding" => embedding} | _rest]}} ->
        {:ok, embedding}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Generates a chat completion for the given messages.
  """
  def generate_chat_completion(messages, model \\ "gpt-3.5-turbo") do
    case OpenAI.Chat.create(model, messages) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _rest]}} ->
        {:ok, content}
      {:error, error} ->
        {:error, error}
    end
  end
end
