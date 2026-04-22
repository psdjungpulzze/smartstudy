defmodule FunSheepWeb.WebhookController do
  @moduledoc """
  Controller for receiving Interactor webhook callbacks and tool callbacks.

  Handles:
  - Interactor platform events (agent responses, workflow state changes, credential status)
  - AI agent tool callbacks (OCR text retrieval, question search/storage)
  """

  use FunSheepWeb, :controller

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

      %{"type" => "subscription." <> _rest} ->
        handle_billing_event(conn, params)

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

  defp handle_credential_event(conn, %{"type" => type, "data" => data}) do
    credential_id = data["credential_id"] || data["id"]

    case credential_id && FunSheep.Integrations.get_by_credential_id(credential_id) do
      nil ->
        # No credential_id on the event, or no matching connection on our
        # side — either way there's nothing actionable. The event is still
        # acknowledged so Interactor doesn't retry forever.
        json(conn, %{status: "received"})

      false ->
        json(conn, %{status: "received"})

      connection ->
        apply_credential_event(connection, type)
        json(conn, %{status: "ok"})
    end
  end

  defp handle_credential_event(conn, _params) do
    json(conn, %{status: "received"})
  end

  defp apply_credential_event(connection, "credential.revoked") do
    {:ok, updated} = FunSheep.Integrations.mark_status(connection, :revoked)
    FunSheep.Integrations.broadcast(updated, :revoked)
  end

  defp apply_credential_event(connection, "credential.expired") do
    {:ok, updated} = FunSheep.Integrations.mark_status(connection, :expired)
    FunSheep.Integrations.broadcast(updated, :expired)
  end

  defp apply_credential_event(connection, "credential.refreshed") do
    {:ok, updated} =
      FunSheep.Integrations.update_connection(connection, %{
        status: :active,
        last_sync_error: nil
      })

    FunSheep.Integrations.broadcast(updated, :refreshed)
  end

  defp apply_credential_event(_connection, _type), do: :ok

  defp handle_billing_event(conn, %{"type" => type, "data" => data}) do
    case type do
      "subscription.activated" ->
        handle_subscription_activated(conn, data)

      "subscription.cancelled" ->
        handle_subscription_cancelled(conn, data)

      "subscription.expired" ->
        handle_subscription_expired(conn, data)

      _ ->
        Logger.debug("Received unhandled billing event: #{type}")
        json(conn, %{status: "received"})
    end
  end

  defp handle_billing_event(conn, _params) do
    json(conn, %{status: "received"})
  end

  defp handle_subscription_activated(conn, data) do
    with subscriber_id when not is_nil(subscriber_id) <- data["subscriber_id"],
         %{id: user_role_id} <-
           FunSheep.Accounts.get_user_role_by_interactor_id(subscriber_id) do
      FunSheep.Billing.activate_subscription(user_role_id, %{
        plan: data["plan_name"] || "monthly",
        billing_subscription_id: data["subscription_id"],
        stripe_customer_id: data["stripe_customer_id"],
        current_period_start: parse_datetime(data["current_period_start"]),
        current_period_end: parse_datetime(data["current_period_end"])
      })

      json(conn, %{status: "activated"})
    else
      _ ->
        Logger.warning("Could not find user for billing event: #{inspect(data["subscriber_id"])}")
        conn |> put_status(404) |> json(%{error: "User not found"})
    end
  end

  defp handle_subscription_cancelled(conn, data) do
    with subscriber_id when not is_nil(subscriber_id) <- data["subscriber_id"],
         %{id: user_role_id} <-
           FunSheep.Accounts.get_user_role_by_interactor_id(subscriber_id) do
      FunSheep.Billing.cancel_subscription(user_role_id)
      json(conn, %{status: "cancelled"})
    else
      _ ->
        conn |> put_status(404) |> json(%{error: "User not found"})
    end
  end

  defp handle_subscription_expired(conn, data) do
    with subscriber_id when not is_nil(subscriber_id) <- data["subscriber_id"],
         %{id: user_role_id} <-
           FunSheep.Accounts.get_user_role_by_interactor_id(subscriber_id),
         sub when not is_nil(sub) <- FunSheep.Billing.get_subscription(user_role_id) do
      FunSheep.Billing.update_subscription(sub, %{plan: "free", status: "expired"})
      json(conn, %{status: "expired"})
    else
      _ ->
        conn |> put_status(404) |> json(%{error: "User not found"})
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  # --- Tool Callback Handlers ---

  defp handle_get_ocr_text(conn, %{"arguments" => %{"material_id" => material_id}}) do
    case FunSheep.Repo.get(FunSheep.Content.UploadedMaterial, material_id) do
      nil ->
        json(conn, %{error: "Material not found"})

      _material ->
        pages = FunSheep.Content.list_ocr_pages_by_material(material_id)
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

    questions = FunSheep.Questions.list_questions_by_course(course_id, filters)

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
    case FunSheep.Questions.create_question(args) do
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
