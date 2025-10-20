defmodule AdvisorAgent.Repo do
  use Ecto.Repo,
    otp_app: :advisor_agent,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  alias AdvisorAgent.{Document, Message, OngoingInstruction, Task, Thread, User}

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

  # Threads
  @doc """
  Creates a new thread for a user.
  """
  def create_thread(user_id) do
    %Thread{}
    |> Thread.changeset(%{user_id: user_id})
    |> __MODULE__.insert()
  end

  @doc """
  Gets a thread with all its messages preloaded.
  """
  def get_thread_with_messages(thread_id) do
    messages_query = from m in Message, order_by: [asc: m.inserted_at]

    from(t in Thread,
      where: t.id == ^thread_id,
      preload: [messages: ^messages_query]
    )
    |> __MODULE__.one()
  end

  @doc """
  Gets all threads for a user, ordered by most recently updated.
  """
  def get_user_threads(user_id, opts \\ []) do
    # Subquery for latest message
    latest_message_query = from m in Message, order_by: [desc: m.inserted_at], limit: 1

    # Base query
    base_query = from(t in Thread,
      where: t.user_id == ^user_id,
      order_by: [desc: t.updated_at],
      preload: [messages: ^latest_message_query]
    )

    # Apply search filter if provided
    query = case Keyword.get(opts, :search) do
      nil -> base_query
      search_term ->
        from t in base_query, where: ilike(t.title, ^"%#{search_term}%")
    end

    __MODULE__.all(query)
  end

  @doc """
  Gets threads grouped by date periods.
  Returns a map with keys: :today, :yesterday, :last_7_days, :last_30_days, :older
  """
  def get_threads_grouped_by_date(user_id) do
    # Get start of today by truncating to the day
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    yesterday_start = DateTime.add(today_start, -1, :day)
    last_7_days_start = DateTime.add(today_start, -7, :day)
    last_30_days_start = DateTime.add(today_start, -30, :day)

    threads = get_user_threads(user_id)

    %{
      today: Enum.filter(threads, fn t -> DateTime.compare(t.updated_at, today_start) in [:gt, :eq] end),
      yesterday: Enum.filter(threads, fn t ->
        DateTime.compare(t.updated_at, yesterday_start) in [:gt, :eq] &&
        DateTime.compare(t.updated_at, today_start) == :lt
      end),
      last_7_days: Enum.filter(threads, fn t ->
        DateTime.compare(t.updated_at, last_7_days_start) in [:gt, :eq] &&
        DateTime.compare(t.updated_at, yesterday_start) == :lt
      end),
      last_30_days: Enum.filter(threads, fn t ->
        DateTime.compare(t.updated_at, last_30_days_start) in [:gt, :eq] &&
        DateTime.compare(t.updated_at, last_7_days_start) == :lt
      end),
      older: Enum.filter(threads, fn t ->
        DateTime.compare(t.updated_at, last_30_days_start) == :lt
      end)
    }
  end

  @doc """
  Updates a thread's title.
  """
  def update_thread_title(thread_id, title) do
    thread = __MODULE__.get!(Thread, thread_id)
    thread
    |> Thread.update_title(title)
    |> __MODULE__.update()
  end

  @doc """
  Deletes a thread and all its messages.
  """
  def delete_thread(thread_id) do
    thread = __MODULE__.get!(Thread, thread_id)
    __MODULE__.delete(thread)
  end

  @doc """
  Sets the active thread for a user.
  """
  def set_active_thread(user_id, thread_id) do
    user = __MODULE__.get!(User, user_id)
    user
    |> User.update_active_thread(thread_id)
    |> __MODULE__.update()
  end

  # Messages
  @doc """
  Creates a new message in a thread.
  """
  def create_message(thread_id, role, content) do
    # Create the message
    result = %Message{}
    |> Message.changeset(%{thread_id: thread_id, role: role, content: content})
    |> __MODULE__.insert()

    # Increment thread message count and update timestamp
    case result do
      {:ok, message} ->
        thread = __MODULE__.get!(Thread, thread_id)
        thread
        |> Thread.increment_message_count()
        |> __MODULE__.update()

        {:ok, message}

      error ->
        error
    end
  end
end
