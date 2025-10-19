defmodule AdvisorAgent.NomicClient do
  @moduledoc """
  Client for interacting with the Nomic Embed API to generate embeddings.
  """

  require Logger

  @nomic_api_base_url "https://api-atlas.nomic.ai/v1"
  @embedding_model "nomic-embed-text-v1.5"

  @doc """
  Generates an embedding for the given text using Nomic Embed API.
  """
  def generate_embedding(text) when is_binary(text) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("Nomic API key not configured, skipping embedding generation")
      {:error, %{"error" => %{"type" => "missing_api_key", "message" => "Nomic API key not configured"}}}
    else
      case Req.post(@nomic_api_base_url <> "/embedding/text",
             auth: {:bearer, api_key},
             json: %{
               model: @embedding_model,
               texts: [text],
               task_type: "search_document"
             }
           ) do
        {:ok, %Req.Response{status: 200, body: %{"embeddings" => [embedding | _rest]}}} ->
          {:ok, embedding}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Failed to generate Nomic embedding: Status #{status}, Body: #{inspect(body)}")
          {:error, %{"error" => %{"type" => "api_error", "message" => "Nomic API error: #{status}"}}}

        {:error, error} ->
          Logger.error("Failed to generate Nomic embedding: #{inspect(error)}")
          {:error, %{"error" => %{"type" => "request_error", "message" => "Request failed: #{inspect(error)}"}}}
      end
    end
  end

  defp get_api_key do
    Application.get_env(:advisor_agent, :nomic_api_key) ||
      System.get_env("NOMIC_API_KEY")
  end
end
