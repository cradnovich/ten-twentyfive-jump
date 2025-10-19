defmodule AdvisorAgent.OpenAIIntegrationTest do
  use ExUnit.Case, async: false
  require Logger

  alias AdvisorAgent.Tools

  @moduletag :integration

  describe "OpenAI chat completion with RAG context" do
    test "successfully calls OpenAI with simple context and gets a valid response" do
      # Simple mock context (simulating RAG results)
      context = """
      [Email 1]
      Meeting request from John Doe about Q4 planning

      [Contact 1: Jane Smith (jane@example.com)]
      Contact: Jane Smith. Email: jane@example.com
      """

      # Build system message with context
      system_content = """
      You are an AI assistant for financial advisors. You have access to:
      - Email history and conversations
      - Calendar information
      - Hubspot CRM contacts and notes

      Use the following context from the database when relevant:
      #{context}

      You can use the available tools to help the user with tasks.
      Be proactive and helpful.
      """

      # Simple user message
      user_message = "How many meetings do I have this week?"

      # Build messages array
      messages = [
        %{"role" => "system", "content" => system_content},
        %{"role" => "user", "content" => user_message}
      ]

      # Get tool definitions
      tools = Tools.get_tool_definitions()

      # Call OpenAI with logging (same as in ChatLive)
      result = call_openai_with_tools(messages, tools)

      # Assert we get a valid response
      case result do
        {:ok, response_message} ->
          IO.puts("\n✅ Test PASSED - Got valid response from OpenAI")
          IO.puts("Response content: #{inspect(response_message["content"])}")

          assert is_map(response_message)
          assert response_message["role"] == "assistant"
          # Content might be nil if there are tool calls, so we just check the structure
          assert Map.has_key?(response_message, "content")

        {:error, error} ->
          IO.puts("\n❌ Test FAILED - OpenAI returned error")
          IO.puts("Error: #{inspect(error)}")
          flunk("OpenAI call failed with error: #{inspect(error)}")
      end
    end

    test "handles OpenAI response with tool calls" do
      # Simple context
      context = """
      [Contact 1: John Doe (john@example.com)]
      Contact: John Doe. Email: john@example.com
      """

      system_content = """
      You are an AI assistant. You have access to tools.

      Context:
      #{context}
      """

      # Message that should trigger a tool call
      user_message = "Send an email to john@example.com saying 'Hello'"

      messages = [
        %{"role" => "system", "content" => system_content},
        %{"role" => "user", "content" => user_message}
      ]

      tools = Tools.get_tool_definitions()

      result = call_openai_with_tools(messages, tools)

      case result do
        {:ok, response_message} ->
          IO.puts("\n✅ Test PASSED - Got valid response from OpenAI")

          # Check if response has tool_calls
          if Map.has_key?(response_message, "tool_calls") and response_message["tool_calls"] != nil do
            IO.puts("Response includes tool calls: #{length(response_message["tool_calls"])} tool(s)")
            IO.puts("Tool calls: #{inspect(response_message["tool_calls"])}")
          else
            IO.puts("Response content: #{inspect(response_message["content"])}")
          end

          assert is_map(response_message)
          assert response_message["role"] == "assistant"

        {:error, error} ->
          IO.puts("\n❌ Test FAILED - OpenAI returned error")
          flunk("OpenAI call failed with error: #{inspect(error)}")
      end
    end
  end

  # Helper function with the same logging as ChatLive
  defp call_openai_with_tools(messages, tools) do
    # Log the parameters being sent to OpenAI
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("=== Calling OpenAI with the following parameters ===")
    IO.puts("Model: gpt-4-turbo-preview")
    IO.puts("\nMessages:")
    IO.inspect(messages, pretty: true, limit: :infinity)
    IO.puts("\nTools (#{length(tools)} total):")
    IO.inspect(tools, pretty: true, limit: :infinity)
    IO.puts("Tool choice: auto")
    IO.puts("=== End of OpenAI parameters ===")
    IO.puts(String.duplicate("=", 80) <> "\n")

    result = OpenAI.chat_completion(
      model: "gpt-4-turbo-preview",
      messages: messages,
      tools: tools,
      tool_choice: "auto"
    )

    # Log the raw response from OpenAI
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("=== OpenAI raw response ===")
    IO.inspect(result, pretty: true, limit: :infinity)
    IO.puts("=== End of OpenAI raw response ===")
    IO.puts(String.duplicate("=", 80) <> "\n")

    case result do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        IO.puts("✓ Successfully extracted message from OpenAI response")
        {:ok, message}

      {:ok, response} ->
        IO.puts("✗ OpenAI response did not match expected pattern")
        IO.puts("Response structure:")
        IO.inspect(response, pretty: true, limit: :infinity)
        {:error, "Unexpected response format from OpenAI"}

      {:error, error} ->
        IO.puts("✗ OpenAI API error")
        IO.inspect(error, pretty: true, limit: :infinity)
        {:error, error}
    end
  end
end
