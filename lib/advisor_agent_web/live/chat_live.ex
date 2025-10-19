defmodule AdvisorAgentWeb.ChatLive do
  use AdvisorAgentWeb, :live_view

  alias AdvisorAgent.{GmailClient, HubspotClient, NomicClient, Repo, Tools, ToolExecutor, User}
  import AdvisorAgentWeb.ChatComponents
  require Logger

  def mount(_params, session, socket) do
    # Load user from session
    current_user =
      case session["user_id"] do
        nil -> nil
        user_id -> Repo.get(User, user_id)
      end

    if current_user && current_user.google_access_token do
      Task.start(fn ->
        GmailClient.fetch_and_store_emails_incremental(current_user, current_user.google_access_token)
      end)
    end

    if current_user && current_user.hubspot_access_token do
      user_id = current_user.email

      Task.start(fn ->
        HubspotClient.fetch_and_store_contacts_and_notes(user_id, current_user.hubspot_access_token)
      end)
    end

    {:ok,
     assign(socket, :messages, [])
     |> assign(:current_user, current_user)
     |> assign(:user_input, "")
     |> assign(:active_tab, :chat)
     |> assign(:thread_started_at, DateTime.utc_now())}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  def handle_event("update_user_input", %{"user_message" => value}, socket) do
    {:noreply, assign(socket, :user_input, value)}
  end

  def handle_event("send_message", %{"user_message" => user_message}, socket) do
    current_user = socket.assigns.current_user

    unless current_user do
      {:noreply, socket}
    else
      # Add user message to chat
      new_messages = socket.assigns.messages ++ [%{text: user_message, sender: :user}]
      socket = assign(socket, :messages, new_messages)
      socket = assign(socket, :user_input, "")

      # Process message with RAG and tool calling
      socket =
        case process_message_with_tools(user_message, current_user) do
          {:ok, response} ->
            new_messages = socket.assigns.messages ++ [%{text: response, sender: :agent}]
            assign(socket, :messages, new_messages)

          {:error, error} ->
            Logger.error("Failed to process message: #{inspect(error)}")
            error_msg = "I apologize, but I encountered an error processing your request. Please try again."
            new_messages = socket.assigns.messages ++ [%{text: error_msg, sender: :agent}]
            assign(socket, :messages, new_messages)
        end

      {:noreply, socket}
    end
  end

  defp process_message_with_tools(user_message, current_user) do
    # Generate embedding and get RAG context
    {context, _rag_error} =
      case NomicClient.generate_embedding(user_message) do
        {:ok, query_embedding} ->
          relevant_documents = Repo.search_documents(query_embedding, 10)
          context_text = format_context_with_metadata(relevant_documents)
          {context_text, nil}

        {:error, error} ->
          Logger.warning("Failed to generate embedding: #{inspect(error)}")
          {"", error}
      end

    # Get ongoing instructions
    ongoing_instructions = Repo.get_active_instructions(current_user.id)
    instructions_text =
      if ongoing_instructions != [] do
        instructions_list =
          Enum.map_join(ongoing_instructions, "\n", fn inst ->
            "- #{inst.instruction}"
          end)

        "\n\nONGOING INSTRUCTIONS (always follow these):\n#{instructions_list}"
      else
        ""
      end

    # Build system message with RAG context and ongoing instructions
    system_content =
      if context != "" do
        """
        You are an AI assistant for financial advisors. You have access to:
        - Email history and conversations
        - Calendar information
        - Hubspot CRM contacts and notes

        Use the following context from the database when relevant:
        #{context}

        You can use the available tools to help the user with tasks like:
        - Sending emails
        - Scheduling meetings
        - Looking up contacts in Hubspot
        - Managing calendar events
        - Creating and managing ongoing instructions

        Be proactive and helpful. If you need to perform an action, use the appropriate tool.#{instructions_text}
        """
      else
        """
        You are an AI assistant for financial advisors. You have access to tools to:
        - Send emails
        - Search emails
        - Manage calendar events
        - Look up and create Hubspot contacts
        - Add notes to contacts
        - Create and manage ongoing instructions

        Be proactive and helpful.#{instructions_text}
        """
      end

    # Start conversation with tool calling
    initial_messages = [
      %{"role" => "system", "content" => system_content},
      %{"role" => "user", "content" => user_message}
    ]

    # Call OpenAI with tools and handle tool calling loop
    handle_tool_calling_loop(initial_messages, current_user, 0)
  end

  defp handle_tool_calling_loop(messages, current_user, iteration) do
    # Prevent infinite loops
    if iteration > 10 do
      {:error, "Maximum tool calling iterations reached"}
    else
      # Get tool definitions
      tools = Tools.get_tool_definitions()

      # Call OpenAI with tools
      case call_openai_with_tools(messages, tools) do
        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}}
        when is_nil(tool_calls) and not is_nil(content) ->
          # No tool calls, we have the final response
          {:ok, content}

        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) and tool_calls != [] ->
          # LLM wants to call tools
          Logger.info("LLM requested #{length(tool_calls)} tool call(s)")

          # Add assistant message with tool calls to conversation
          assistant_message = %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}
          messages = messages ++ [assistant_message]

          # Execute each tool call
          tool_results =
            Enum.map(tool_calls, fn tool_call ->
              tool_name = tool_call["function"]["name"]
              arguments = Jason.decode!(tool_call["function"]["arguments"])

              Logger.info("Executing tool: #{tool_name}")

              result =
                case ToolExecutor.execute_tool(tool_name, arguments, current_user) do
                  {:ok, result} -> result
                  {:error, error} -> "Error: #{error}"
                end

              %{
                "role" => "tool",
                "tool_call_id" => tool_call["id"],
                "content" => result
              }
            end)

          # Add tool results to conversation
          messages = messages ++ tool_results

          # Continue the loop with tool results
          handle_tool_calling_loop(messages, current_user, iteration + 1)

        {:ok, %{"role" => "assistant", "content" => content}} ->
          # Fallback for when content is present but no tool calls
          {:ok, content || "I'm not sure how to help with that."}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp call_openai_with_tools(messages, tools) do
    # Log the parameters being sent to OpenAI
    Logger.info("=== Calling OpenAI with the following parameters ===")
    Logger.info("Model: gpt-3.5-turbo")
    Logger.info("Messages: #{inspect(messages, pretty: true, limit: :infinity)}")
    Logger.info("Tools: #{inspect(tools, pretty: true, limit: :infinity)}")
    Logger.info("Tool choice: auto")
    Logger.info("=== End of OpenAI parameters ===")

    result = OpenAI.chat_completion(
      model: "gpt-3.5-turbo",
      messages: messages,
      tools: tools,
      tool_choice: "auto"
    )

    # Log the raw response from OpenAI
    Logger.info("=== OpenAI raw response ===")
    Logger.info("#{inspect(result, pretty: true, limit: :infinity)}")
    Logger.info("=== End of OpenAI raw response ===")

    case result do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        Logger.info("Successfully extracted message from OpenAI response")
        {:ok, message}

      {:ok, response} ->
        Logger.error("OpenAI response did not match expected pattern. Response: #{inspect(response, pretty: true)}")
        {:error, "Unexpected response format from OpenAI"}

      {:error, error} ->
        Logger.error("OpenAI API error: #{inspect(error, pretty: true)}")
        {:error, error}
    end
  end

  defp format_context_with_metadata(documents) when documents == [], do: ""

  defp format_context_with_metadata(documents) do
    documents
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, index} ->
      source_type = doc.metadata["source"]

      header = case source_type do
        "gmail" ->
          "[Email #{index}]"
        "hubspot_contact" ->
          name = "#{doc.metadata["firstname"]} #{doc.metadata["lastname"]}"
          email = doc.metadata["email"]
          "[Contact #{index}: #{name} (#{email})]"
        "hubspot_note" ->
          "[Note #{index}]"
        _ ->
          "[Document #{index}]"
      end

      "#{header}\n#{doc.content}"
    end)
  end

  def render(assigns) do
    ~H"""
    <%= if @current_user do %>
      <div class="flex flex-col h-screen bg-white">
        <.chat_header current_user={@current_user} />
        <.tab_nav active_tab={@active_tab} />

        <%= if @active_tab == :chat do %>
          <!-- Chat Area -->
          <div class="flex-1 overflow-y-auto px-6 py-6">
            <!-- Thread Start Time -->
            <div class="text-center mb-8">
              <p class="text-xs text-gray-400"><%= Calendar.strftime(@thread_started_at, "%I:%M%P – %B %d, %Y") %></p>
            </div>

            <!-- Initial Message -->
            <div class="mb-6">
              <p class="text-gray-900 text-base">
                I can answer questions about any Jump meeting. What do you want to know?
              </p>
            </div>

            <!-- Messages -->
            <%= for message <- @messages do %>
              <.message_bubble message={message} />
            <% end %>
          </div>
        <% else %>
          <!-- History Area -->
          <div class="flex-1 overflow-y-auto px-6 py-6">
            <div class="text-center py-12">
              <p class="text-gray-500 text-base">No previous chat threads</p>
              <p class="text-gray-400 text-sm mt-2">Your chat history will appear here</p>
            </div>
          </div>
        <% end %>

        <.chat_input user_input={@user_input} />
      </div>
    <% else %>
      <!-- Login Screen -->
      <div class="flex items-center justify-center h-screen bg-gray-50">
        <div class="text-center">
          <h1 class="text-3xl font-semibold text-gray-900 mb-6">Welcome to Ask Anything</h1>
          <a href="/auth/google" class="inline-block px-6 py-3 text-base font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg">
            Log in with Google
          </a>
        </div>
      </div>
    <% end %>
    """
  end
end
