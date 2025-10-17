defmodule AdvisorAgentWeb.ChatLive do
  use AdvisorAgentWeb, :live_view

  alias AdvisorAgent.{GmailClient, HubspotClient, OpenAIClient, Repo, Tools, ToolExecutor}
  require Logger

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

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

    # Build system message with RAG context
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

        Be proactive and helpful. If you need to perform an action, use the appropriate tool.
        """
      else
        """
        You are an AI assistant for financial advisors. You have access to tools to:
        - Send emails
        - Search emails
        - Manage calendar events
        - Look up and create Hubspot contacts
        - Add notes to contacts

        Be proactive and helpful.
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
    <div class="max-w-3xl mx-auto my-12 bg-white rounded-lg shadow-md">
      <div class="p-6 border-b border-gray-200">
        <div class="flex justify-between items-center">
          <h1 class="text-2xl font-semibold text-gray-800">Ask Anything</h1>
          <div>
            <%= if @current_user do %>
              <div class="flex items-center">
                <img src={@current_user.picture} alt={@current_user.name} class="w-8 h-8 rounded-full mr-2">
                <span class="text-sm font-semibold text-gray-800"><%= @current_user.name %></span>
                <%= if !@current_user.hubspot_access_token do %>
                  <a href="/auth/hubspot" class="ml-4 px-4 py-2 text-sm font-semibold text-white bg-orange-500 hover:bg-orange-600 rounded-md">Connect to Hubspot</a>
                <% end %>
                <a href="/auth/logout" class="ml-4 text-sm font-semibold text-gray-500 hover:text-gray-700">Log out</a>
              </div>
            <% else %>
              <a href="/auth/google" class="px-4 py-2 text-sm font-semibold text-white bg-blue-500 hover:bg-blue-600 rounded-md">Log in with Google</a>
            <% end %>
          </div>
        </div>
        <div class="mt-4 flex items-center justify-between">
          <div class="flex items-center">
            <button class="px-4 py-2 text-sm font-semibold text-gray-800 bg-gray-200 rounded-md">Chat</button>
            <button class="ml-2 px-4 py-2 text-sm font-semibold text-gray-500 hover:bg-gray-200 rounded-md">History</button>
          </div>
          <button class="flex items-center px-4 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-200 rounded-md">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New thread
          </button>
        </div>
      </div>

      <div class="p-6">
        <%= if @current_user do %>
          <div class="text-sm text-gray-500 text-center">
            <p>Context set to all meetings</p>
            <p>11:17am – May 13, 2025</p>
          </div>

          <div class="mt-6">
            <p class="text-gray-700">
              I can answer questions about any Jump meeting. What do you want to know?
            </p>
          </div>

          <%= for message <- @messages do %>
            <div class={[
              "mt-6 flex",
              if(message.sender == :user, do: "justify-end", else: "justify-start")
            ]}>
              <div class={[
                "rounded-lg p-4 max-w-lg",
                if(message.sender == :user, do: "bg-blue-500 text-white", else: "bg-gray-200 text-gray-800")
              ]}>
                {message.text}
              </div>
            </div>
          <% end %>

        <% else %>
          <div class="text-center">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Please log in to view the chat.</h2>
          </div>
        <% end %>
      </div>

      <div class="p-6 bg-gray-50 border-t border-gray-200 rounded-b-lg">
        <form phx-submit="send_message">
          <div class="flex items-center">
            <textarea
              class="w-full px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              rows="1"
              placeholder="Ask anything about your meetings..."
              name="user_message"
              value={@user_input}
              phx-change="update_user_input"
            ></textarea>
            <button type="submit" class="ml-2 px-4 py-2 text-sm font-semibold text-white bg-blue-500 hover:bg-blue-600 rounded-md">Send</button>
          </div>
        </form>
        <div class="mt-2 flex justify-between items-center">
            <div class="flex items-center">
                <button class="flex items-center px-3 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-200 rounded-md">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                </button>
                <button class="ml-2 flex items-center px-3 py-2 text-sm font-semibold text-gray-800 border border-gray-300 rounded-md">
                    All meetings
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                </button>
            </div>
            <div class="flex items-center">
                <button class="text-gray-500 hover:text-gray-700 p-2 rounded-full">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l-7-7 7-7 7 7-7 7zm0 0v-8" /></svg>
                </button>
                <button class="text-gray-500 hover:text-gray-700 p-2 rounded-full ml-2">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.344 6.344a1 1 0 01-1.414 0l-2.828-2.828a1 1 0 010-1.414l6.344-6.344a1 1 0 011.414 0l2.828 2.828a1 1 0 010 1.414z" /></svg>
                </button>
                <button class="text-gray-500 hover:text-gray-700 p-2 rounded-full ml-2">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-14 0m7 10v-3" /></svg>
                </button>
            </div>
        </div>
      </div>
    </div>
    """
  end
end
