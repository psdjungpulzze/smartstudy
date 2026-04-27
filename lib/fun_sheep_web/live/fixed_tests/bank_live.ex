defmodule FunSheepWeb.FixedTests.BankLive do
  @moduledoc """
  Authoring LiveView for custom fixed-question test banks.
  Handles create, edit, and question management.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, FixedTests}
  alias FunSheep.FixedTests.{FixedTestBank, FixedTestQuestion}

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    user_role = Accounts.get_user_role_by_interactor_id(user["interactor_user_id"])

    socket =
      socket
      |> assign(user_role: user_role)
      |> assign(page_title: "My Custom Tests")
      |> assign(banks: list_banks(user_role))
      |> assign(view: :list)
      |> assign(active_bank: nil)
      |> assign(editing_question: nil)
      |> assign(question_form: nil)
      |> assign(bank_form: nil)

    socket =
      case params do
        %{"id" => id} -> load_bank(socket, id)
        _ -> socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, load_bank(socket, id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, view: :list, active_bank: nil)}
  end

  # ── Bank events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_bank", _params, socket) do
    cs = FixedTestBank.changeset(%FixedTestBank{}, %{})
    {:noreply, assign(socket, view: :new_bank, bank_form: to_form(cs))}
  end

  def handle_event("save_bank", %{"fixed_test_bank" => params}, socket) do
    user_role = socket.assigns.user_role
    attrs = Map.put(params, "created_by_id", user_role.id)

    case FixedTests.create_bank(attrs) do
      {:ok, bank} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test created")
         |> push_navigate(to: ~p"/custom-tests/#{bank.id}")}

      {:error, cs} ->
        {:noreply, assign(socket, bank_form: to_form(cs))}
    end
  end

  def handle_event("edit_bank_meta", _params, socket) do
    bank = socket.assigns.active_bank
    cs = FixedTestBank.changeset(bank, %{})
    {:noreply, assign(socket, view: :edit_bank, bank_form: to_form(cs))}
  end

  def handle_event("update_bank", %{"fixed_test_bank" => params}, socket) do
    bank = socket.assigns.active_bank

    case FixedTests.update_bank(bank, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> assign(active_bank: updated, view: :questions)}

      {:error, cs} ->
        {:noreply, assign(socket, bank_form: to_form(cs))}
    end
  end

  def handle_event("archive_bank", %{"id" => id}, socket) do
    bank = FixedTests.get_bank!(id)

    case FixedTests.archive_bank(bank) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test archived")
         |> assign(banks: list_banks(socket.assigns.user_role))
         |> push_navigate(to: ~p"/custom-tests")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not archive test")}
    end
  end

  # ── Question events ──────────────────────────────────────────────────────

  def handle_event("new_question", _params, socket) do
    bank = socket.assigns.active_bank
    pos = FixedTests.question_count(bank) + 1

    cs =
      FixedTestQuestion.changeset(%FixedTestQuestion{}, %{
        bank_id: bank.id,
        position: pos,
        question_type: "multiple_choice"
      })

    {:noreply, assign(socket, editing_question: :new, question_form: to_form(cs))}
  end

  def handle_event("edit_question", %{"id" => id}, socket) do
    question = FixedTests.get_question!(id)
    cs = FixedTestQuestion.changeset(question, %{})
    {:noreply, assign(socket, editing_question: question, question_form: to_form(cs))}
  end

  def handle_event("save_question", %{"fixed_test_question" => params}, socket) do
    bank = socket.assigns.active_bank

    result =
      case socket.assigns.editing_question do
        :new -> FixedTests.add_question(bank, params)
        %FixedTestQuestion{} = q -> FixedTests.update_question(q, params)
      end

    case result do
      {:ok, _} ->
        updated_bank = FixedTests.get_bank_with_questions!(bank.id)

        {:noreply,
         socket
         |> assign(active_bank: updated_bank, editing_question: nil, question_form: nil)
         |> put_flash(:info, "Question saved")}

      {:error, cs} ->
        {:noreply, assign(socket, question_form: to_form(cs))}
    end
  end

  def handle_event("cancel_question_edit", _params, socket) do
    {:noreply, assign(socket, editing_question: nil, question_form: nil)}
  end

  def handle_event("delete_question", %{"id" => id}, socket) do
    question = FixedTests.get_question!(id)

    case FixedTests.delete_question(question) do
      {:ok, _} ->
        updated_bank = FixedTests.get_bank_with_questions!(socket.assigns.active_bank.id)
        {:noreply, assign(socket, active_bank: updated_bank)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete question")}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <%= case @view do %>
        <% :list -> %>
          <.bank_list banks={@banks} />
        <% :new_bank -> %>
          <.bank_form_view form={@bank_form} title="New Custom Test" />
        <% :edit_bank -> %>
          <.bank_form_view form={@bank_form} title={"Edit: #{@active_bank.title}"} />
        <% :questions -> %>
          <.questions_view
            bank={@active_bank}
            editing_question={@editing_question}
            question_form={@question_form}
          />
      <% end %>
    </div>
    """
  end

  # ── Sub-renders ──────────────────────────────────────────────────────────

  defp bank_list(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">My Custom Tests</h1>
        <button
          phx-click="new_bank"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-sm"
        >
          + New Test
        </button>
      </div>

      <%= if @banks == [] do %>
        <div class="text-center py-20 text-[#8E8E93]">
          <div class="text-5xl mb-4">📋</div>
          <p class="font-medium">No custom tests yet</p>
          <p class="text-sm mt-1">Create one to assign to students or take yourself</p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for bank <- @banks do %>
            <div class="bg-white rounded-2xl shadow-sm p-5 flex items-center justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <span class="text-xs font-medium bg-indigo-100 text-indigo-700 px-2 py-0.5 rounded-full">
                    Custom Test
                  </span>
                  <h3 class="font-semibold text-[#1C1C1E]">{bank.title}</h3>
                </div>
                <p class="text-sm text-[#8E8E93] mt-0.5">
                  <%= if bank.course do %>
                    {bank.course.name} ·
                  <% end %>
                  {bank.visibility}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <.link
                  navigate={~p"/custom-tests/#{bank.id}"}
                  class="text-sm font-medium text-[#4CD964] hover:underline"
                >
                  Edit
                </.link>
                <.link
                  navigate={~p"/custom-tests/#{bank.id}/assign"}
                  class="text-sm font-medium text-indigo-600 hover:underline"
                >
                  Assign
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp bank_form_view(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E] mb-6">{@title}</h1>

      <div class="bg-white rounded-2xl shadow-sm p-6">
        <.form for={@form} phx-submit="save_bank" class="space-y-4">
          <.input field={@form[:title]} label="Title" placeholder="e.g. Chapter 5 Quiz" />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description (optional)"
            rows="2"
          />
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:time_limit_minutes]}
              type="number"
              label="Time limit (minutes)"
              placeholder="Leave blank for untimed"
            />
            <.input
              field={@form[:max_attempts]}
              type="number"
              label="Max attempts"
              placeholder="Leave blank for unlimited"
            />
          </div>
          <.input
            field={@form[:shuffle_questions]}
            type="checkbox"
            label="Shuffle question order"
          />
          <.input
            field={@form[:visibility]}
            type="select"
            label="Visibility"
            options={[
              {"Private (only you and assigned students)", "private"},
              {"Class (visible to your class)", "class"},
              {"School", "school"}
            ]}
          />

          <div class="flex gap-3 pt-2">
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full"
            >
              Save
            </button>
            <.link navigate={~p"/custom-tests"} class="text-[#8E8E93] px-4 py-2">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp questions_view(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <div>
          <.link
            navigate={
              if @bank.course_id, do: ~p"/courses/#{@bank.course_id}/tests", else: ~p"/custom-tests"
            }
            class="text-sm text-[#8E8E93] hover:underline"
          >
            ← Back
          </.link>
          <h1 class="text-2xl font-bold text-[#1C1C1E] mt-1">{@bank.title}</h1>
          <p class="text-sm text-[#8E8E93]">
            {length(@bank.questions)} question{if length(@bank.questions) != 1, do: "s", else: ""}
          </p>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="edit_bank_meta"
            class="text-sm border border-gray-200 px-4 py-2 rounded-full hover:bg-gray-50"
          >
            Settings
          </button>
          <.link
            navigate={~p"/custom-tests/#{@bank.id}/assign"}
            class="text-sm bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-full"
          >
            Assign
          </.link>
          <button
            phx-click="new_question"
            class="text-sm bg-[#4CD964] hover:bg-[#3DBF55] text-white px-4 py-2 rounded-full"
          >
            + Question
          </button>
        </div>
      </div>

      <%= if @bank.questions == [] do %>
        <div class="text-center py-16 text-[#8E8E93] bg-white rounded-2xl shadow-sm">
          <div class="text-4xl mb-3">📝</div>
          <p class="font-medium">No questions yet</p>
          <p class="text-sm mt-1">Click "+ Question" to add your first question</p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for {q, idx} <- Enum.with_index(@bank.questions, 1) do %>
            <div class="bg-white rounded-2xl shadow-sm p-5">
              <div class="flex items-start justify-between gap-4">
                <div class="flex-1">
                  <div class="flex items-center gap-2 mb-1">
                    <span class="text-xs font-medium text-[#8E8E93]">Q{idx}</span>
                    <span class="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">
                      {q.question_type |> String.replace("_", " ")}
                    </span>
                  </div>
                  <p class="text-[#1C1C1E]">{q.question_text}</p>
                  <%= if q.options do %>
                    <div class="mt-2 space-y-1">
                      <%= for {opt, _i} <- Enum.with_index(q.options["choices"] || []) do %>
                        <div class={[
                          "text-sm px-3 py-1 rounded-lg",
                          if(opt["value"] == q.answer_text,
                            do: "bg-green-50 text-green-700 font-medium",
                            else: "text-[#8E8E93]"
                          )
                        ]}>
                          {if opt["value"] == q.answer_text, do: "✓ ", else: "  "}{opt["label"]}
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="text-sm text-[#4CD964] mt-1">Answer: {q.answer_text}</p>
                  <% end %>
                </div>
                <div class="flex gap-2 shrink-0">
                  <button
                    phx-click="edit_question"
                    phx-value-id={q.id}
                    class="text-xs text-indigo-600 hover:underline"
                  >
                    Edit
                  </button>
                  <button
                    phx-click="delete_question"
                    phx-value-id={q.id}
                    data-confirm="Delete this question?"
                    class="text-xs text-red-500 hover:underline"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @editing_question do %>
        <.question_edit_modal form={@question_form} />
      <% end %>
    </div>
    """
  end

  defp question_edit_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div class="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-6">
        <h2 class="text-lg font-bold text-[#1C1C1E] mb-4">Question</h2>

        <.form for={@form} phx-submit="save_question" class="space-y-4">
          <.input
            field={@form[:question_type]}
            type="select"
            label="Question type"
            options={[
              {"Multiple Choice", "multiple_choice"},
              {"True / False", "true_false"},
              {"Short Answer", "short_answer"}
            ]}
          />
          <.input
            field={@form[:question_text]}
            type="textarea"
            label="Question"
            rows="3"
            placeholder="Enter your question here"
          />
          <.input
            field={@form[:answer_text]}
            label="Correct answer"
            placeholder="For MC: enter the option value (e.g. b). For T/F: true or false."
          />
          <.input
            field={@form[:explanation]}
            type="textarea"
            label="Explanation (optional — shown after answer)"
            rows="2"
          />
          <.input field={@form[:points]} type="number" label="Points" />

          <div class="flex gap-3 pt-2">
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full"
            >
              Save question
            </button>
            <button
              type="button"
              phx-click="cancel_question_edit"
              class="text-[#8E8E93] px-4 py-2"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp list_banks(nil), do: []

  defp list_banks(user_role) do
    FixedTests.list_banks_by_creator(user_role.id)
  end

  defp load_bank(socket, id) do
    bank = FixedTests.get_bank_with_questions!(id)
    assign(socket, active_bank: bank, view: :questions, page_title: bank.title)
  end
end
