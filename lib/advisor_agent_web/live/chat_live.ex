defmodule AdvisorAgentWeb.ChatLive do
  use AdvisorAgentWeb, :live_view

  alias AdvisorAgent.{GmailClient, HubspotClient, OpenAIClient, Repo, Tools, ToolExecutor, User}
  require Logger

  def mount(_params, session, socket) do
    # Load user from session
    current_user =
      case session["user_id"] do
        nil -> nil
        user_id -> Repo.get(User, user_id)
      end

    if current_user && current_user.google_access_token do
      user_id = current_user.email

      Task.start(fn ->
        GmailClient.fetch_and_store_emails(user_id, current_user.google_access_token)
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
     |> assign(:user_input, "")}
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

  def handle_event("update_user_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :user_input, value)}
  end

  defp process_message_with_tools(user_message, current_user) do
    # Generate embedding and get RAG context
    {context, _rag_error} =
      case OpenAIClient.generate_embedding(user_message) do
        {:ok, query_embedding} ->
          relevant_documents = Repo.search_documents(query_embedding)
          context_text = Enum.map_join(relevant_documents, "\n", fn doc -> doc.content end)
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
        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => nil}}
        when not is_nil(content) ->
          # No tool calls, we have the final response
          {:ok, content}

        {:ok, %{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) and tool_calls != [] ->
          # LLM wants to call tools
          Logger.info("LLM requested #{length(tool_calls)} tool call(s)")

          # Add assistant message with tool calls to conversation
          messages = messages ++ [%{"role" => "assistant", "content" => content, "tool_calls" => tool_calls}]

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
    case OpenAI.chat_completion(
           model: "gpt-4-turbo-preview",
           messages: messages,
           tools: tools,
           tool_choice: "auto"
         ) do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        {:ok, message}

      {:error, error} ->
        {:error, error}
    end
  end

  def render(assigns) do
    ~H"""
    <%= if @current_user do %>
      <div class="flex flex-col h-screen bg-white">
        <!-- Header -->
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <h1 class="text-xl font-semibold text-gray-900">Ask Anything</h1>
          <button class="p-2 hover:bg-gray-100 rounded-full">
            <svg class="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex items-center justify-between px-6 py-3 border-b border-gray-200">
          <div class="flex items-center gap-6">
            <button class="text-sm font-medium text-gray-900 border-b-2 border-gray-900 pb-1">Chat</button>
            <button class="text-sm font-medium text-gray-500 hover:text-gray-900 pb-1">History</button>
          </div>
          <button class="flex items-center gap-2 text-sm font-medium text-gray-700 hover:text-gray-900">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New thread
          </button>
        </div>

        <!-- Chat Area -->
        <div class="flex-1 overflow-y-auto px-6 py-6">
          <!-- Context Info -->
          <div class="text-center mb-8">
            <p class="text-sm text-gray-500">Context set to all meetings</p>
            <p class="text-xs text-gray-400">11:17am – May 13, 2025</p>
          </div>

          <!-- Initial Message -->
          <div class="mb-6">
            <p class="text-gray-900 text-base">
              I can answer questions about any Jump meeting. What do you want to know?
            </p>
          </div>

          <!-- Messages -->
          <%= for message <- @messages do %>
            <%= if message.sender == :user do %>
              <div class="flex justify-end mb-6">
                <div class="bg-gray-100 rounded-2xl px-5 py-3 max-w-lg">
                  <p class="text-gray-900 text-base"><%= message.text %></p>
                </div>
              </div>
            <% else %>
              <div class="mb-6">
                <div class="text-gray-900 text-base max-w-2xl">
                  <%= message.text %>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Input Area -->
        <div class="border-t border-gray-200 px-6 py-4">
          <form phx-submit="send_message" class="relative">
            <textarea
              class="w-full resize-none rounded-2xl border border-gray-300 px-4 py-3 pr-12 focus:outline-none focus:border-gray-400 text-base"
              rows="1"
              placeholder="Ask anything about your meetings..."
              name="user_message"
              phx-change="update_user_input"
            ><%= @user_input %></textarea>
            <div class="absolute bottom-3 right-3 flex items-center gap-2">
              <button type="submit" class="p-2 bg-gray-900 hover:bg-gray-800 rounded-full">
                <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 10l7-7m0 0l7 7m-7-7v18" />
                </svg>
              </button>
            </div>
          </form>

          <div class="flex items-center justify-between mt-3">
            <div class="flex items-center gap-2">
              <button class="p-2 hover:bg-gray-100 rounded-full">
                <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
              </button>
              <button class="flex items-center gap-1 px-3 py-1.5 text-sm border border-gray-300 rounded-full hover:bg-gray-50">
                <span>All meetings</span>
                <svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </button>
            </div>
            <div class="flex items-center gap-2">
              <button class="p-2 hover:bg-gray-100 rounded-full">
                <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.344 6.344a1 1 0 01-1.414 0l-2.828-2.828a1 1 0 010-1.414l6.344-6.344a1 1 0 011.414 0l2.828 2.828a1 1 0 010 1.414z" />
                </svg>
              </button>
              <button class="p-2 hover:bg-gray-100 rounded-full">
                <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-14 0m7 10v-3" />
                </svg>
              </button>
              <button class="p-2 hover:bg-gray-100 rounded-full">
                <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-14 0m7 10v-3" />
                </svg>
              </button>
            </div>
          </div>
        </div>
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
