defmodule AdvisorAgent.HubspotClient do
  @moduledoc """
  Client for interacting with the Hubspot API.
  """

  alias AdvisorAgent.Repo
  alias AdvisorAgent.Document
  alias AdvisorAgent.NomicClient
  require Logger

  @hubspot_api_base_url "https://api.hubapi.com"

  @doc """
  Looks up a contact in Hubspot by email or name.
  """
  def lookup_contact(access_token, query) do
    # Try searching by email first
    case search_contact_by_email(access_token, query) do
      {:ok, contact} when not is_nil(contact) ->
        {:ok, contact}

      _ ->
        # If not found by email, search by name
        search_contacts_by_name(access_token, query)
    end
  end

  defp search_contact_by_email(access_token, email) do
    case Req.get(@hubspot_api_base_url <> "/crm/v3/objects/contacts/#{email}",
           auth: {:bearer, access_token},
           params: %{idProperty: "email"}
         ) do
      {:ok, %Req.Response{status: 200, body: contact}} ->
        {:ok, contact}

      {:ok, %Req.Response{status: 404}} ->
        {:ok, nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to lookup contact: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_lookup_contact}

      {:error, error} ->
        Logger.error("Failed to lookup contact: #{inspect(error)}")
        {:error, :failed_to_lookup_contact}
    end
  end

  defp search_contacts_by_name(access_token, name) do
    # For now, just fetch all contacts and filter by name
    # In production, you'd want to use Hubspot's search API
    case Req.get(@hubspot_api_base_url <> "/crm/v3/objects/contacts",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => contacts}}} ->
        found =
          Enum.find(contacts, fn contact ->
            firstname = get_in(contact, ["properties", "firstname"]) || ""
            lastname = get_in(contact, ["properties", "lastname"]) || ""
            full_name = "#{firstname} #{lastname}" |> String.downcase()
            String.contains?(full_name, String.downcase(name))
          end)

        if found, do: {:ok, found}, else: {:error, :contact_not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to search contacts: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_search_contacts}

      {:error, error} ->
        Logger.error("Failed to search contacts: #{inspect(error)}")
        {:error, :failed_to_search_contacts}
    end
  end

  @doc """
  Creates a new contact in Hubspot.
  """
  def create_contact(access_token, contact_data) do
    properties =
      contact_data
      |> Enum.into(%{})

    body = %{
      properties: properties
    }

    case Req.post(@hubspot_api_base_url <> "/crm/v3/objects/contacts",
           auth: {:bearer, access_token},
           json: body
         ) do
      {:ok, %Req.Response{status: 201, body: contact}} ->
        {:ok, contact}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to create contact: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to create contact: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to create contact: #{inspect(error)}")
        {:error, "Failed to create contact: #{inspect(error)}"}
    end
  end

  @doc """
  Adds a note to a Hubspot contact.
  """
  def add_note(access_token, contact_id, note_body) do
    note_data = %{
      properties: %{
        hs_note_body: note_body,
        hs_timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      }
    }

    # First create the note
    case Req.post(@hubspot_api_base_url <> "/crm/v3/objects/notes",
           auth: {:bearer, access_token},
           json: note_data
         ) do
      {:ok, %Req.Response{status: 201, body: note}} ->
        # Then associate the note with the contact
        note_id = note["id"]
        associate_note_with_contact(access_token, note_id, contact_id)
        {:ok, note}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to create note: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to create note: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to create note: #{inspect(error)}")
        {:error, "Failed to create note: #{inspect(error)}"}
    end
  end

  defp associate_note_with_contact(access_token, note_id, contact_id) do
    association_data = [
      %{
        from: %{id: note_id},
        to: %{id: contact_id},
        type: "note_to_contact"
      }
    ]

    case Req.put(@hubspot_api_base_url <> "/crm/v3/associations/notes/contacts/batch/create",
           auth: {:bearer, access_token},
           json: %{inputs: association_data}
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "Failed to associate note with contact: Status #{status}, Body: #{inspect(body)}"
        )

      {:error, error} ->
        Logger.error("Failed to associate note with contact: #{inspect(error)}")
    end
  end

  @doc """
  Fetches Hubspot contacts and their notes and stores them as documents.
  """
  def fetch_and_store_contacts_and_notes(user_id, access_token) do
    # TODO: Implement token refresh logic
    case Req.get(@hubspot_api_base_url <> "/crm/v3/objects/contacts",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => contacts}}} ->
        Enum.each(contacts, fn contact ->
          process_and_store_contact(user_id, contact)
          fetch_and_store_contact_notes(user_id, access_token, contact["id"])
        end)

        {:ok, :contacts_fetched}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to fetch contacts: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_fetch_contacts}

      {:error, error} ->
        Logger.error("Failed to fetch contacts: #{inspect(error)}")
        {:error, :failed_to_fetch_contacts}
    end
  end

  defp process_and_store_contact(user_id, contact) do
    content = "Contact: #{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]}. Email: #{contact["properties"]["email"]}"

    case NomicClient.generate_embedding(content) do
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

        case Repo.insert(changeset, on_conflict: :nothing) do
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
    case Req.get(
           @hubspot_api_base_url <>
             "/crm/v3/objects/contacts/#{contact_id}/associations/notes",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => notes}}} ->
        Enum.each(notes, fn note ->
          get_note_details(user_id, access_token, note["id"])
        end)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "Failed to fetch notes for contact #{contact_id}: Status #{status}, Body: #{inspect(body)}"
        )

      {:error, error} ->
        Logger.error("Failed to fetch notes for contact #{contact_id}: #{inspect(error)}")
    end
  end

  defp get_note_details(user_id, access_token, note_id) do
    case Req.get(@hubspot_api_base_url <> "/crm/v3/objects/notes/#{note_id}",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        process_and_store_note(user_id, body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to get note #{note_id}: Status #{status}, Body: #{inspect(body)}")

      {:error, error} ->
        Logger.error("Failed to get note #{note_id}: #{inspect(error)}")
    end
  end

  defp process_and_store_note(user_id, note_payload) do
    content = note_payload["properties"]["hs_note_body"]

    case NomicClient.generate_embedding(content) do
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

        case Repo.insert(changeset, on_conflict: :nothing) do
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
