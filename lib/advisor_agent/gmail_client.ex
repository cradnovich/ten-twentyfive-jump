defmodule AdvisorAgent.GmailClient do
  @moduledoc """
  Client for interacting with the Gmail API.
  """

  alias AdvisorAgent.{Repo, Document, NomicClient, GmailSyncState}
  require Logger

  @gmail_api_base_url "https://www.googleapis.com/gmail/v1/users/me"
  @default_page_size 100

  @doc """
  Sends an email using Gmail API.
  """
  def send_email(access_token, to, subject, body, from \\ nil) do
    # Build the email in RFC 2822 format
    from_email = from || "me"

    email_content =
      """
      From: #{from_email}
      To: #{to}
      Subject: #{subject}
      Content-Type: text/plain; charset=utf-8

      #{body}
      """
      |> String.trim()

    # Base64url encode the email
    encoded_email =
      email_content
      |> Base.url_encode64(padding: false)

    case Req.post(@gmail_api_base_url <> "/messages/send",
           auth: {:bearer, access_token},
           json: %{raw: encoded_email}
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to send email: Status #{status}, Body: #{inspect(body)}")
        {:error, "Failed to send email: Status #{status}"}

      {:error, error} ->
        Logger.error("Failed to send email: #{inspect(error)}")
        {:error, "Failed to send email: #{inspect(error)}"}
    end
  end

  @doc """
  Searches for emails matching a query.
  """
  def search_emails(access_token, query) do
    case Req.get(@gmail_api_base_url <> "/messages",
           auth: {:bearer, access_token},
           params: %{q: query}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"messages" => messages}}} ->
        {:ok, messages}

      {:ok, %Req.Response{status: 200, body: %{}}} ->
        {:ok, []}

      {:ok, %Req.Response{status: 400, body: %{"error" => %{"message" => "Mail service not enabled"}}}} ->
        Logger.warning("Gmail service not enabled for this account")
        {:error, :gmail_not_enabled}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to search emails: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_search_emails}

      {:error, error} ->
        Logger.error("Failed to search emails: #{inspect(error)}")
        {:error, :failed_to_search_emails}
    end
  end

  @doc """
  Fetches emails from Gmail and stores them as documents.
  """
  def fetch_and_store_emails(user_id, access_token) do
    # TODO: Implement token refresh logic
    case Req.get(@gmail_api_base_url <> "/messages",
           auth: {:bearer, access_token}
         ) do
      {:ok, %Req.Response{status: 200, body: %{"messages" => messages}}} ->
        Enum.each(messages, fn %{"id" => message_id} ->
          case get_message(access_token, message_id) do
            {:ok, message_payload} ->
              process_and_store_message(user_id, message_payload)

            {:error, error} ->
              Logger.error("Failed to get message #{message_id}: #{inspect(error)}")
          end
        end)

        {:ok, :emails_fetched}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to fetch messages: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_fetch_messages}

      {:error, error} ->
        Logger.error("Failed to fetch messages: #{inspect(error)}")
        {:error, :failed_to_fetch_messages}
    end
  end

  @doc """
  Incrementally fetches and stores emails based on user's sync state.
  Supports bidirectional sync (newer and older emails) with pagination.
  """
  def fetch_and_store_emails_incremental(user, access_token) do
    # Determine sync strategy
    sync_strategy = GmailSyncState.determine_sync_strategy(user)

    Logger.info("Starting incremental Gmail sync for user #{user.email} with strategy: #{sync_strategy}")

    # Build date query if needed
    date_query = GmailSyncState.build_date_query(user, sync_strategy)

    # Fetch one page of messages
    case fetch_messages_page(access_token, date_query, user.gmail_sync_page_token) do
      {:ok, messages, next_page_token} ->
        # Get full message details for each message
        full_messages = fetch_full_messages(access_token, messages)

        # Store each message
        Enum.each(full_messages, fn message_payload ->
          process_and_store_message(user.email, message_payload)
        end)

        # Update sync state
        case GmailSyncState.update_sync_state(user, full_messages, sync_strategy, next_page_token) do
          {:ok, updated_user} ->
            Logger.info("Successfully synced #{length(full_messages)} emails. Next page token: #{inspect(next_page_token)}")
            {:ok, {updated_user, length(full_messages)}}

          {:error, error} ->
            Logger.error("Failed to update sync state: #{inspect(error)}")
            {:error, :failed_to_update_sync_state}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # Fetches a single page of message IDs from Gmail with optional query and pagination.
  # Returns {:ok, messages, next_page_token} or {:error, reason}
  defp fetch_messages_page(access_token, query, page_token) do
    params = %{
      maxResults: @default_page_size
    }
    |> add_if_present(:q, query)
    |> add_if_present(:pageToken, page_token)

    case Req.get(@gmail_api_base_url <> "/messages",
           auth: {:bearer, access_token},
           params: params
         ) do
      {:ok, %Req.Response{status: 200, body: %{"messages" => messages} = body}} ->
        next_page_token = Map.get(body, "nextPageToken")
        {:ok, messages, next_page_token}

      {:ok, %Req.Response{status: 200, body: %{}}} ->
        # No messages
        {:ok, [], nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to fetch messages page: Status #{status}, Body: #{inspect(body)}")
        {:error, :failed_to_fetch_messages}

      {:error, error} ->
        Logger.error("Failed to fetch messages page: #{inspect(error)}")
        {:error, :failed_to_fetch_messages}
    end
  end

  # Fetches full message details for a list of message IDs.
  defp fetch_full_messages(access_token, messages) do
    messages
    |> Enum.map(fn %{"id" => message_id} ->
      case get_message(access_token, message_id) do
        {:ok, message_payload} ->
          message_payload

        {:error, error} ->
          Logger.error("Failed to get message #{message_id}: #{inspect(error)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Helper to conditionally add params
  defp add_if_present(params, _key, nil), do: params
  defp add_if_present(params, key, value), do: Map.put(params, key, value)

  @doc """
  Gets the details of a specific email message.
  """
  def get_message(access_token, message_id) do
    case Req.get(@gmail_api_base_url <> "/messages/#{message_id}",
           auth: {:bearer, access_token},
           params: %{format: "full"}
         ) do
      {:ok, %Req.Response{status: 200, body: message}} ->
        # Extract useful fields
        headers = get_in(message, ["payload", "headers"]) || []

        from = find_header(headers, "From")
        subject = find_header(headers, "Subject")
        snippet = message["snippet"]

        {:ok,
         %{
           "id" => message["id"],
           "threadId" => message["threadId"],
           "labelIds" => message["labelIds"],
           "internalDate" => message["internalDate"],
           "from" => from,
           "subject" => subject,
           "snippet" => snippet,
           "body" => extract_body(message["payload"])
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Failed to get message: Status #{status}, Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Failed to get message: #{inspect(error)}"}
    end
  end

  defp find_header(headers, name) do
    case Enum.find(headers, fn h -> h["name"] == name end) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_body(payload) do
    cond do
      payload["body"]["data"] ->
        Base.url_decode64!(payload["body"]["data"], padding: false)

      payload["parts"] ->
        payload["parts"]
        |> Enum.find(fn part -> part["mimeType"] == "text/plain" end)
        |> case do
          %{"body" => %{"data" => data}} -> Base.url_decode64!(data, padding: false)
          _ -> ""
        end

      true ->
        ""
    end
  end

  defp process_and_store_message(user_id, message_payload) do
    # Extract relevant parts of the email
    # For simplicity, let's just take the snippet for now
    content = message_payload["snippet"]

    case NomicClient.generate_embedding(content) do
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

        case Repo.insert(changeset, on_conflict: :nothing) do
          {:ok, _document} ->
            Logger.info("Stored email document: #{message_payload["id"]}")
          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("Failed to store email document: #{inspect(changeset.errors)}")
        end

      {:error, %{"error" => %{"type" => "missing_api_key", "message" => message}}} ->
        if is_binary(message) and String.contains?(message, "API key") do
          Logger.warning("Nomic API key not configured, skipping embedding generation for email: #{message_payload["id"]}")
        else
          Logger.error("Failed to generate embedding for email: #{inspect(%{"error" => %{"type" => "invalid_request_error", "message" => message}})}")
        end

      {:error, error} ->
        Logger.error("Failed to generate embedding for email: #{inspect(error)}")
    end
  end
end
