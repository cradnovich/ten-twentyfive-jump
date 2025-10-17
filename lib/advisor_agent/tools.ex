defmodule AdvisorAgent.Tools do
  @moduledoc """
  Defines all available tools for the AI agent.
  """

  @doc """
  Returns the list of tool definitions in OpenAI function calling format.
  """
  def get_tool_definitions do
    [
      %{
        type: "function",
        function: %{
          name: "send_email",
          description:
            "Send an email to a recipient. Use this to send emails on behalf of the user.",
          parameters: %{
            type: "object",
            properties: %{
              to: %{
                type: "string",
                description: "The email address of the recipient"
              },
              subject: %{
                type: "string",
                description: "The subject line of the email"
              },
              body: %{
                type: "string",
                description: "The body content of the email"
              }
            },
            required: ["to", "subject", "body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "search_emails",
          description:
            "Search for emails using Gmail search syntax. Returns a list of matching email IDs.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description:
                  "Gmail search query (e.g., 'from:john@example.com subject:meeting', 'is:unread', etc.)"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "get_calendar_availability",
          description:
            "Check the user's calendar availability for a given time range. Returns busy/free times.",
          parameters: %{
            type: "object",
            properties: %{
              time_min: %{
                type: "string",
                description: "Start time in RFC3339 format (e.g., '2025-10-18T09:00:00-07:00')"
              },
              time_max: %{
                type: "string",
                description: "End time in RFC3339 format (e.g., '2025-10-18T17:00:00-07:00')"
              }
            },
            required: ["time_min", "time_max"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_calendar_event",
          description: "Create a new event on the user's Google Calendar.",
          parameters: %{
            type: "object",
            properties: %{
              summary: %{
                type: "string",
                description: "Title of the event"
              },
              description: %{
                type: "string",
                description: "Description of the event"
              },
              start_time: %{
                type: "string",
                description: "Start time in RFC3339 format (e.g., '2025-10-18T09:00:00-07:00')"
              },
              end_time: %{
                type: "string",
                description: "End time in RFC3339 format (e.g., '2025-10-18T10:00:00-07:00')"
              },
              attendees: %{
                type: "array",
                items: %{type: "string"},
                description: "List of attendee email addresses"
              }
            },
            required: ["summary", "start_time", "end_time"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "lookup_hubspot_contact",
          description:
            "Look up a contact in Hubspot by email or name. Returns contact details if found.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Email address or name to search for"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_hubspot_contact",
          description: "Create a new contact in Hubspot CRM.",
          parameters: %{
            type: "object",
            properties: %{
              email: %{
                type: "string",
                description: "Contact's email address"
              },
              firstname: %{
                type: "string",
                description: "Contact's first name"
              },
              lastname: %{
                type: "string",
                description: "Contact's last name"
              },
              phone: %{
                type: "string",
                description: "Contact's phone number (optional)"
              },
              company: %{
                type: "string",
                description: "Contact's company (optional)"
              }
            },
            required: ["email"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "add_hubspot_note",
          description: "Add a note to a Hubspot contact.",
          parameters: %{
            type: "object",
            properties: %{
              contact_id: %{
                type: "string",
                description: "The ID of the Hubspot contact"
              },
              note_body: %{
                type: "string",
                description: "The content of the note"
              }
            },
            required: ["contact_id", "note_body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "list_calendar_events",
          description: "List upcoming events from the user's calendar.",
          parameters: %{
            type: "object",
            properties: %{
              time_min: %{
                type: "string",
                description:
                  "Start time in RFC3339 format (optional, defaults to current time)"
              },
              time_max: %{
                type: "string",
                description: "End time in RFC3339 format (optional)"
              },
              max_results: %{
                type: "integer",
                description: "Maximum number of events to return (default: 10)"
              }
            }
          }
        }
      }
    ]
  end
end
