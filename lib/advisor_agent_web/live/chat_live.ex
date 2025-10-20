defmodule AdvisorAgentWeb.ChatLive do
  use AdvisorAgentWeb, :live_view

  alias AdvisorAgent.{GmailClient, HubspotClient, NomicClient, OpenAIModels, Repo, ThreadSummarizer, Tools, ToolExecutor, User}
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

    # Load or create active thread
    {thread, messages} = if current_user do
      load_or_create_thread(current_user)
    else
      {nil, []}
    end

    # Load threads for history tab
    grouped_threads = if current_user do
      Repo.get_threads_grouped_by_date(current_user.id)
    else
      %{today: [], yesterday: [], last_7_days: [], last_30_days: [], older: []}
    end

    {:ok,
     assign(socket, :messages, messages)
     |> assign(:current_user, current_user)
     |> assign(:user_input, "")
     |> assign(:active_tab, :chat)
     |> assign(:show_user_menu, false)
     |> assign(:current_thread, thread)
     |> assign(:thread_started_at, if(thread, do: thread.inserted_at, else: DateTime.utc_now()))
     |> assign(:search_query, "")
     |> assign(:grouped_threads, grouped_threads)}
  end

  defp load_or_create_thread(user) do
    cond do
      # User has an active thread - load it
      user.active_thread_id != nil ->
        case Repo.get_thread_with_messages(user.active_thread_id) do
          nil ->
            # Active thread was deleted, create new one
            create_new_thread(user)

          thread ->
            messages = Enum.map(thread.messages, fn msg ->
              %{text: msg.content, sender: String.to_atom(msg.role)}
            end)
            {thread, messages}
        end

      # No active thread - create one
      true ->
        create_new_thread(user)
    end
  end

  defp create_new_thread(user) do
    {:ok, thread} = Repo.create_thread(user.id)
    {:ok, _user} = Repo.set_active_thread(user.id, thread.id)
    {thread, []}
  end

  def handle_event("toggle_user_menu", _params, socket) do
    {:noreply, assign(socket, :show_user_menu, !socket.assigns.show_user_menu)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_atom(tab)

    # Reload threads when switching to history tab
    socket = if tab_atom == :history && socket.assigns.current_user do
      grouped_threads = Repo.get_threads_grouped_by_date(socket.assigns.current_user.id)
      |> filter_threads_by_search(socket.assigns.search_query)
      assign(socket, :grouped_threads, grouped_threads)
    else
      socket
    end

    {:noreply, assign(socket, :active_tab, tab_atom)}
  end

  def handle_event("update_user_input", %{"user_message" => value}, socket) do
    {:noreply, assign(socket, :user_input, value)}
  end

  def handle_event("send_message", %{"user_message" => user_message}, socket) do
    current_user = socket.assigns.current_user
    current_thread = socket.assigns.current_thread

    unless current_user do
      {:noreply, socket}
    else
      # Reload user from database to get latest settings (model, API key, etc.)
      fresh_user = Repo.get(User, current_user.id)

      # Save user message to database
      {:ok, _msg} = Repo.create_message(current_thread.id, "user", user_message)

      # Add user message to chat
      new_messages = socket.assigns.messages ++ [%{text: user_message, sender: :user}]
      socket = assign(socket, :messages, new_messages)
      socket = assign(socket, :user_input, "")
      socket = assign(socket, :current_user, fresh_user)

      # Process message with RAG and tool calling
      socket =
        case process_message_with_tools(user_message, fresh_user) do
          {:ok, response} ->
            # Save assistant response to database
            {:ok, _msg} = Repo.create_message(current_thread.id, "assistant", response)

            new_messages = socket.assigns.messages ++ [%{text: response, sender: :agent}]
            socket = assign(socket, :messages, new_messages)

            # Check if we should generate a summary (after 3 exchanges = 6 messages)
            updated_thread = Repo.get_thread_with_messages(current_thread.id)
            if ThreadSummarizer.ready_for_summary?(updated_thread) do
              Task.start(fn ->
                ThreadSummarizer.generate_summary(updated_thread, fresh_user)
              end)
            end

            assign(socket, :current_thread, updated_thread)

          {:error, error} ->
            Logger.error("Failed to process message: #{inspect(error)}")
            error_msg = "I apologize, but I encountered an error processing your request. Please try again."

            # Save error message to database
            {:ok, _msg} = Repo.create_message(current_thread.id, "assistant", error_msg)

            new_messages = socket.assigns.messages ++ [%{text: error_msg, sender: :agent}]
            assign(socket, :messages, new_messages)
        end

      {:noreply, socket}
    end
  end

  def handle_event("new_thread", _params, socket) do
    current_user = socket.assigns.current_user

    unless current_user do
      {:noreply, socket}
    else
      # Create new thread
      {thread, messages} = create_new_thread(current_user)

      # Reload threads for history
      grouped_threads = Repo.get_threads_grouped_by_date(current_user.id)
      |> filter_threads_by_search(socket.assigns.search_query)

      {:noreply,
       socket
       |> assign(:current_thread, thread)
       |> assign(:messages, messages)
       |> assign(:thread_started_at, thread.inserted_at)
       |> assign(:active_tab, :chat)
       |> assign(:grouped_threads, grouped_threads)}
    end
  end

  def handle_event("switch_thread", %{"thread_id" => thread_id}, socket) do
    current_user = socket.assigns.current_user

    unless current_user do
      {:noreply, socket}
    else
      thread_id = String.to_integer(thread_id)

      # Load the thread
      case Repo.get_thread_with_messages(thread_id) do
        nil ->
          {:noreply, socket}

        thread ->
          # Set as active thread
          {:ok, _user} = Repo.set_active_thread(current_user.id, thread.id)

          # Convert messages to UI format
          messages = Enum.map(thread.messages, fn msg ->
            %{text: msg.content, sender: String.to_atom(msg.role)}
          end)

          {:noreply,
           socket
           |> assign(:current_thread, thread)
           |> assign(:messages, messages)
           |> assign(:thread_started_at, thread.inserted_at)
           |> assign(:active_tab, :chat)}
      end
    end
  end

  def handle_event("delete_thread", %{"thread_id" => thread_id}, socket) do
    current_user = socket.assigns.current_user
    current_thread = socket.assigns.current_thread

    unless current_user do
      {:noreply, socket}
    else
      thread_id = String.to_integer(thread_id)

      # Delete the thread
      {:ok, _} = Repo.delete_thread(thread_id)

      # Reload threads for history
      grouped_threads = Repo.get_threads_grouped_by_date(current_user.id)
      |> filter_threads_by_search(socket.assigns.search_query)

      # If this was the active thread, create a new one
      socket = if current_thread && current_thread.id == thread_id do
        {thread, messages} = create_new_thread(current_user)

        socket
        |> assign(:current_thread, thread)
        |> assign(:messages, messages)
        |> assign(:thread_started_at, thread.inserted_at)
      else
        socket
      end

      {:noreply, assign(socket, :grouped_threads, grouped_threads)}
    end
  end

  def handle_event("search_threads", %{"search" => %{"query" => query}}, socket) do
    # Update search query and reload filtered threads
    socket = socket
    |> assign(:search_query, query)

    socket = if socket.assigns.current_user do
      grouped_threads = Repo.get_threads_grouped_by_date(socket.assigns.current_user.id)
      |> filter_threads_by_search(query)
      assign(socket, :grouped_threads, grouped_threads)
    else
      socket
    end

    {:noreply, socket}
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
      case call_openai_with_tools(messages, tools, current_user) do
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

  defp call_openai_with_tools(messages, tools, current_user) do
    # Get user's preferred model or use default
    model_string = if current_user.selected_model do
      current_user.selected_model
    else
      OpenAIModels.to_string(OpenAIModels.default_chat_model())
    end

    # Get user's API key if provided
    api_key = current_user.openai_api_key

    # Log the parameters being sent to OpenAI
    Logger.info("=== Calling OpenAI with the following parameters ===")
    Logger.info("Model: #{model_string}")
    Logger.info("Using custom API key: #{if api_key, do: "Yes", else: "No (using system default)"}")
    Logger.info("Messages: #{inspect(messages, pretty: true, limit: :infinity)}")
    Logger.info("Tools: #{inspect(tools, pretty: true, limit: :infinity)}")
    Logger.info("Tool choice: auto")
    Logger.info("=== End of OpenAI parameters ===")

    # Build params for OpenAI call
    params = [
      model: model_string,
      messages: messages,
      tools: tools,
      tool_choice: "auto"
    ]

    # Create config with API key if user provided one
    config = if api_key, do: %OpenAI.Config{api_key: api_key}, else: %OpenAI.Config{}

    result = OpenAI.chat_completion(params, config)

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

  defp render_history(assigns) do
    ~H"""
    <!-- Search Box -->
    <div class="mb-6">
      <form phx-change="search_threads">
        <input
          type="text"
          name="search[query]"
          value={@search_query}
          placeholder="Search threads..."
          class="w-full px-4 py-2 text-gray-900 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </form>
    </div>

    <!-- Thread Groups -->
    <%= if @grouped_threads.today != [] do %>
      <div class="mb-6">
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Today</h3>
        <%= for thread <- @grouped_threads.today do %>
          <.thread_item thread={thread} current_thread_id={@current_thread && @current_thread.id} />
        <% end %>
      </div>
    <% end %>

    <%= if @grouped_threads.yesterday != [] do %>
      <div class="mb-6">
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Yesterday</h3>
        <%= for thread <- @grouped_threads.yesterday do %>
          <.thread_item thread={thread} current_thread_id={@current_thread && @current_thread.id} />
        <% end %>
      </div>
    <% end %>

    <%= if @grouped_threads.last_7_days != [] do %>
      <div class="mb-6">
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Last 7 Days</h3>
        <%= for thread <- @grouped_threads.last_7_days do %>
          <.thread_item thread={thread} current_thread_id={@current_thread && @current_thread.id} />
        <% end %>
      </div>
    <% end %>

    <%= if @grouped_threads.last_30_days != [] do %>
      <div class="mb-6">
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Last 30 Days</h3>
        <%= for thread <- @grouped_threads.last_30_days do %>
          <.thread_item thread={thread} current_thread_id={@current_thread && @current_thread.id} />
        <% end %>
      </div>
    <% end %>

    <%= if @grouped_threads.older != [] do %>
      <div class="mb-6">
        <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Older</h3>
        <%= for thread <- @grouped_threads.older do %>
          <.thread_item thread={thread} current_thread_id={@current_thread && @current_thread.id} />
        <% end %>
      </div>
    <% end %>

    <%= if Enum.all?(Map.values(@grouped_threads), &(&1 == [])) do %>
      <div class="text-center py-12">
        <p class="text-gray-500 text-base">No chat threads found</p>
        <p class="text-gray-400 text-sm mt-2">Start a new conversation to see it here</p>
      </div>
    <% end %>
    """
  end

  defp filter_threads_by_search(grouped_threads, "") do
    grouped_threads
  end

  defp filter_threads_by_search(grouped_threads, query) do
    filter_fn = fn threads ->
      Enum.filter(threads, fn thread ->
        String.contains?(String.downcase(thread.title), String.downcase(query))
      end)
    end

    %{
      today: filter_fn.(grouped_threads.today),
      yesterday: filter_fn.(grouped_threads.yesterday),
      last_7_days: filter_fn.(grouped_threads.last_7_days),
      last_30_days: filter_fn.(grouped_threads.last_30_days),
      older: filter_fn.(grouped_threads.older)
    }
  end

  def render(assigns) do
    ~H"""
    <%= if @current_user do %>
      <div class="flex flex-col h-screen bg-white">
        <.chat_header current_user={@current_user} show_user_menu={@show_user_menu} />
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
            <%= render_history(assigns) %>
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
