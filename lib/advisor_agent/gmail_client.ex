defmodule AdvisorAgent.GmailClient do
  @moduledoc """
  Client for interacting with the Gmail API.
  """

  alias AdvisorAgent.Repo
  alias AdvisorAgent.Document
  alias AdvisorAgent.OpenAIClient
  alias OAuth2.Client
  require Logger

  @gmail_api_base_url "https://www.googleapis.com/gmail/v1/users/me"

  @doc """
  Fetches emails from Gmail and stores them as documents.
  """
  def fetch_and_store_emails(user_id, access_token) do
    # TODO: Implement token refresh logic
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Tesla.get(@gmail_api_base_url <> "/messages", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: %{"messages" => messages}}} ->
        Enum.each(messages, fn %{"id" => message_id} ->
          case get_message(access_token, message_id) do
            {:ok, message_payload} ->
              process_and_store_message(user_id, message_payload)
            {:error, error} ->
              Logger.error("Failed to get message #{message_id}: #{inspect(error)}")
          end
        end)
        {:ok, :emails_fetched}
      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to fetch messages: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_fetch_messages}
      {:error, error} ->
        Logger.error("Failed to fetch messages: #{inspect(error)}")
        {:error, :failed_to_fetch_messages}
    end
  end

  defp get_message(access_token, message_id) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    case Tesla.get(@gmail_api_base_url <> "/messages/#{message_id}", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to get message: Status #{status}, Body: #{inspect(body)}"}
      {:error, error} ->
        {:error, "Failed to get message: #{inspect(error)}"}
    end
  end

  defp process_and_store_message(user_id, message_payload) do
    # Extract relevant parts of the email
    # For simplicity, let's just take the snippet for now
    content = message_payload["snippet"]

    case OpenAIClient.generate_embedding(content) do
      {:ok, embedding} ->
        metadata = %{
          "user_id" => user_id,
          "source" => "gmail",
          "message_id" => message_payload["id"],
          "thread_id" => message_payload["threadId"],
          "labels" => message_payload["labelIds"],
          "timestamp" => message_payload["internalDate"]
        }

        changeset = Document.changeset(%Document{}, %{
          content: content,
          embedding: embedding,
          metadata: metadata
        })

        case Repo.insert(changeset) do
          {:ok, _document} ->
            Logger.info("Stored email document: #{message_payload["id"]}")
          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("Failed to store email document: #{inspect(changeset.errors)}")
        end
      {:error, error} ->
        Logger.error("Failed to generate embedding for email: #{inspect(error)}")
    end
  end
end
