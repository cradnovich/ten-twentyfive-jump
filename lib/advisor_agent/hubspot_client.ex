defmodule AdvisorAgent.HubspotClient do
  @moduledoc """
  Client for interacting with the Hubspot API.
  """

  alias AdvisorAgent.Repo
  alias AdvisorAgent.Document
  alias AdvisorAgent.OpenAIClient
  alias OAuth2.Client
  require Logger

  @hubspot_api_base_url "https://api.hubapi.com"

  @doc """
  Fetches Hubspot contacts and their notes and stores them as documents.
  """
  def fetch_and_store_contacts_and_notes(user_id, access_token) do
    # TODO: Implement token refresh logic
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Tesla.get(@hubspot_api_base_url <> "/crm/v3/objects/contacts", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => contacts}}} ->
        Enum.each(contacts, fn contact ->
          process_and_store_contact(user_id, contact)
          fetch_and_store_contact_notes(user_id, access_token, contact["id"])
        end)
        {:ok, :contacts_fetched}
      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to fetch contacts: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_fetch_contacts}
      {:error, error} ->
        Logger.error("Failed to fetch contacts: #{inspect(error)}")
        {:error, :failed_to_fetch_contacts}
    end
  end

  defp process_and_store_contact(user_id, contact) do
    content = "Contact: #{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]}. Email: #{contact["properties"]["email"]}"

    case OpenAIClient.generate_embedding(content) do
      {:ok, embedding} ->
        metadata = %{
          "user_id" => user_id,
          "source" => "hubspot_contact",
          "contact_id" => contact["id"],
          "firstname" => contact["properties"]["firstname"],
          "lastname" => contact["properties"]["lastname"],
          "email" => contact["properties"]["email"]
        }

        changeset = Document.changeset(%Document{}, %{
          content: content,
          embedding: embedding,
          metadata: metadata
        })

        case Repo.insert(changeset) do
          {:ok, _document} ->
            Logger.info("Stored Hubspot contact: #{contact["id"]}")
          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("Failed to store Hubspot contact: #{inspect(changeset.errors)}")
        end
      {:error, error} ->
        Logger.error("Failed to generate embedding for Hubspot contact: #{inspect(error)}")
    end
  end

  defp fetch_and_store_contact_notes(user_id, access_token, contact_id) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    case Tesla.get(@hubspot_api_base_url <> "/crm/v3/objects/contacts/#{contact_id}/associations/notes", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => notes}}} ->
        Enum.each(notes, fn note ->
          get_note_details(user_id, access_token, note["id"])
        end)
      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to fetch notes for contact #{contact_id}: Status #{status}, Body: #{inspect(body)}")
      {:error, error} ->
        Logger.error("Failed to fetch notes for contact #{contact_id}: #{inspect(error)}")
    end
  end

  defp get_note_details(user_id, access_token, note_id) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    case Tesla.get(@hubspot_api_base_url <> "/crm/v3/objects/notes/#{note_id}", headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        process_and_store_note(user_id, body)
      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to get note #{note_id}: Status #{status}, Body: #{inspect(body)}")
      {:error, error} ->
        Logger.error("Failed to get note #{note_id}: #{inspect(error)}")
    end
  end

  defp process_and_store_note(user_id, note_payload) do
    content = note_payload["properties"]["hs_note_body"]

    case OpenAIClient.generate_embedding(content) do
      {:ok, embedding} ->
        metadata = %{
          "user_id" => user_id,
          "source" => "hubspot_note",
          "note_id" => note_payload["id"],
          "created_at" => note_payload["properties"]["hs_createdate"]
        }

        changeset = Document.changeset(%Document{}, %{
          content: content,
          embedding: embedding,
          metadata: metadata
        })

        case Repo.insert(changeset) do
          {:ok, _document} ->
            Logger.info("Stored Hubspot note: #{note_payload["id"]}")
          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("Failed to store Hubspot note: #{inspect(changeset.errors)}")
        end
      {:error, error} ->
        Logger.error("Failed to generate embedding for Hubspot note: #{inspect(error)}")
    end
  end
end
