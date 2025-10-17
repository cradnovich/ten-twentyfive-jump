defmodule AdvisorAgent.Repo do
  use Ecto.Repo,
    otp_app: :advisor_agent,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  alias AdvisorAgent.{Document, OngoingInstruction, Task}

  def search_documents(query_embedding, limit \\ 5) do
    Document
    |> order_by([d], fragment("? <-> ?", d.embedding, ^query_embedding))
    |> limit(^limit)
    |> __MODULE__.all()
  end

  # Ongoing Instructions
  def get_active_instructions(user_id) do
    OngoingInstruction
    |> where([i], i.user_id == ^user_id and i.active == true)
    |> __MODULE__.all()
  end

  def create_instruction(attrs) do
    %OngoingInstruction{}
    |> OngoingInstruction.changeset(attrs)
    |> __MODULE__.insert()
  end

  def deactivate_instruction(instruction_id) do
    instruction = __MODULE__.get!(OngoingInstruction, instruction_id)
    instruction
    |> OngoingInstruction.changeset(%{active: false})
    |> __MODULE__.update()
  end

  # Tasks
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> __MODULE__.insert()
  end

  def update_task(task, attrs) do
    task
    |> Task.changeset(attrs)
    |> __MODULE__.update()
  end

  def get_pending_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id and t.status in ["pending", "in_progress", "waiting_for_response"])
    |> __MODULE__.all()
  end

  def get_task(task_id) do
    __MODULE__.get(Task, task_id)
  end
end
