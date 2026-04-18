defmodule StudySmartWeb.WebhookController do
  @moduledoc """
  Controller for receiving Interactor webhook callbacks and tool callbacks.

  Handles:
  - Interactor platform events (agent responses, workflow state changes, credential status)
  - AI agent tool callbacks (OCR text retrieval, question search/storage)
  """

  use StudySmartWeb, :controller

  require Logger

  @doc "Handles incoming Interactor webhook events."
  def interactor(conn, params) do
    case params do
      %{"type" => "agent.response_sent"} ->
        handle_agent_response(conn, params)

      %{"type" => "workflow." <> _rest} ->
        handle_workflow_event(conn, params)

      %{"type" => "credential." <> _rest} ->
        handle_credential_event(conn, params)

      _ ->
        Logger.debug("Received unhandled webhook event: #{inspect(params["type"])}")
        json(conn, %{status: "received"})
    end
  end

  @doc "Handles AI agent tool callback requests."
  def tool_callback(conn, %{"tool_name" => tool_name} = params) do
    case tool_name do
      "get_ocr_text" ->
        handle_get_ocr_text(conn, params)

      "search_questions" ->
        handle_search_questions(conn, params)

      "store_question" ->
        handle_store_question(conn, params)

      _ ->
        Logger.warning("Unknown tool callback: #{tool_name}")
        conn |> put_status(404) |> json(%{error: "Unknown tool"})
    end
  end

  def tool_callback(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing tool_name"})
  end

  # --- Webhook Event Handlers ---

  defp handle_agent_response(conn, _params) do
    # TODO: Forward AI response to student's LiveView via PubSub
    json(conn, %{status: "received"})
  end

  defp handle_workflow_event(conn, _params) do
    # TODO: Update workflow progress in UI via PubSub
    json(conn, %{status: "received"})
  end

  defp handle_credential_event(conn, _params) do
    # TODO: Notify about credential status changes
    json(conn, %{status: "received"})
  end

  # --- Tool Callback Handlers ---

  defp handle_get_ocr_text(conn, %{"arguments" => %{"material_id" => material_id}}) do
    case StudySmart.Repo.get(StudySmart.Content.UploadedMaterial, material_id) do
      nil ->
        json(conn, %{error: "Material not found"})

      _material ->
        pages = StudySmart.Content.list_ocr_pages_by_material(material_id)
        text = Enum.map_join(pages, "\n\n---\n\n", & &1.extracted_text)
        json(conn, %{text: text, page_count: length(pages)})
    end
  end

  defp handle_get_ocr_text(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing arguments.material_id"})
  end

  defp handle_search_questions(conn, %{"arguments" => %{"course_id" => course_id} = args}) do
    filters =
      if args["chapter_id"],
        do: %{chapter_id: args["chapter_id"]},
        else: %{}

    questions = StudySmart.Questions.list_questions_by_course(course_id, filters)

    json(conn, %{
      questions:
        Enum.map(questions, fn q ->
          %{id: q.id, content: q.content, answer: q.answer}
        end)
    })
  end

  defp handle_search_questions(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing arguments.course_id"})
  end

  defp handle_store_question(conn, %{"arguments" => args}) do
    case StudySmart.Questions.create_question(args) do
      {:ok, q} ->
        json(conn, %{id: q.id, status: "created"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_changeset_errors(changeset)})

      {:error, other} ->
        conn
        |> put_status(422)
        |> json(%{errors: %{error: inspect(other)}})
    end
  end

  defp handle_store_question(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing arguments"})
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
