defmodule FunSheep.Essays do
  @moduledoc """
  The Essays context.

  Manages essay rubric templates and student essay drafts.
  """

  import Ecto.Query

  alias FunSheep.Repo
  alias FunSheep.Essays.{EssayRubricTemplate, EssayDraft}

  ## Rubric Templates

  @doc "Gets a rubric template by ID. Returns nil if not found."
  def get_rubric_template(id) do
    Repo.get(EssayRubricTemplate, id)
  end

  @doc "Gets a rubric template by exam_type. Returns nil if not found."
  def get_rubric_template_by_exam_type(exam_type) do
    Repo.get_by(EssayRubricTemplate, exam_type: exam_type)
  end

  @doc "Lists all rubric templates."
  def list_rubric_templates do
    Repo.all(from rt in EssayRubricTemplate, order_by: rt.name)
  end

  ## Essay Drafts

  @doc """
  Gets the active (non-submitted) draft for the given student / question /
  optional schedule. Returns nil if none exists.
  """
  def get_active_draft(user_role_id, question_id, schedule_id \\ nil) do
    base_query =
      from(d in EssayDraft,
        where:
          d.user_role_id == ^user_role_id and
            d.question_id == ^question_id and
            d.submitted == false
      )

    query =
      if is_nil(schedule_id) do
        from(d in base_query, where: is_nil(d.schedule_id))
      else
        from(d in base_query, where: d.schedule_id == ^schedule_id)
      end

    Repo.one(query)
  end

  @doc """
  Gets or creates an active draft for the given student / question /
  optional schedule. On create, sets `started_at` and `last_saved_at` to now.
  """
  def get_or_create_draft(user_role_id, question_id, schedule_id \\ nil) do
    case get_active_draft(user_role_id, question_id, schedule_id) do
      %EssayDraft{} = draft ->
        {:ok, draft}

      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %EssayDraft{}
        |> EssayDraft.changeset(%{
          user_role_id: user_role_id,
          question_id: question_id,
          schedule_id: schedule_id,
          body: "",
          word_count: 0,
          last_saved_at: now,
          started_at: now,
          time_elapsed_seconds: 0
        })
        |> Repo.insert()
    end
  end

  @doc """
  Updates (or creates) the active draft with the given body and optional opts.

  Opts:
  - `:schedule_id` — scope to a test schedule
  - `:word_count` — precomputed word count (defaults to counting spaces)
  - `:time_elapsed_seconds` — cumulative elapsed time

  Returns `{:ok, draft}` or `{:error, changeset}`.
  """
  def upsert_draft(user_role_id, question_id, body, opts \\ []) do
    schedule_id = opts[:schedule_id]
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    word_count = opts[:word_count] || count_words(body)
    time_elapsed = opts[:time_elapsed_seconds]

    case get_active_draft(user_role_id, question_id, schedule_id) do
      %EssayDraft{} = draft ->
        update_attrs =
          %{
            body: body,
            word_count: word_count,
            last_saved_at: now
          }
          |> maybe_put(:time_elapsed_seconds, time_elapsed)

        draft
        |> EssayDraft.changeset(update_attrs)
        |> Repo.update()

      nil ->
        create_attrs =
          %{
            user_role_id: user_role_id,
            question_id: question_id,
            schedule_id: schedule_id,
            body: body,
            word_count: word_count,
            last_saved_at: now,
            started_at: now
          }
          |> maybe_put(:time_elapsed_seconds, time_elapsed)

        %EssayDraft{}
        |> EssayDraft.changeset(create_attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Marks a draft as submitted. Sets `submitted: true` and `submitted_at` to now.
  Returns `{:ok, draft}` or `{:error, changeset}`.
  """
  def submit_draft(draft_id) do
    case Repo.get(EssayDraft, draft_id) do
      nil ->
        {:error, :not_found}

      %EssayDraft{} = draft ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        draft
        |> EssayDraft.changeset(%{submitted: true, submitted_at: now})
        |> Repo.update()
    end
  end

  ## Helpers

  defp count_words(nil), do: 0

  defp count_words(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
