defmodule FunSheepWeb.ParentOnboardingLive do
  @moduledoc """
  Parent-initiated onboarding wizard — Flow B (§5.2).

  Four steps:

    1. Who are you studying for? (child details, multi-child loop)
    2. Link the child (fire invites + generate claim codes as needed)
    3. Optional upfront purchase (soft CTA — most parents wait)
    4. Done

  Route: `/onboarding/parent`
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Accounts
  alias FunSheep.InviteCodes

  @grades ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College Adult)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    parent = Accounts.get_user_role_by_interactor_id(user["interactor_user_id"])

    socket =
      socket
      |> assign(
        page_title: "Set up FunSheep for your child",
        parent: parent,
        step: 1,
        children: [],
        draft: empty_child(),
        form_error: nil,
        invite_results: []
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("update_draft", params, socket) do
    {:noreply, assign(socket, :draft, Map.merge(socket.assigns.draft, atomize(params)))}
  end

  def handle_event("add_child", params, socket) do
    # Prefer the submitted form params (tests fire submit without a change
    # event) and fall back to the live-updated draft when the user has
    # been typing.
    child =
      case params do
        %{} when map_size(params) > 0 ->
          %{
            display_name: Map.get(params, "display_name", "") |> to_string() |> String.trim(),
            email: Map.get(params, "email", "") |> to_string() |> String.trim(),
            grade: Map.get(params, "grade", "") |> to_string()
          }

        _ ->
          socket.assigns.draft
      end

    case validate_child(child) do
      :ok ->
        children = socket.assigns.children ++ [child]

        {:noreply,
         socket
         |> assign(children: children, draft: empty_child(), form_error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, :form_error, msg)}
    end
  end

  def handle_event("remove_child", %{"index" => idx}, socket) do
    idx = String.to_integer(idx)
    children = List.delete_at(socket.assigns.children, idx)
    {:noreply, assign(socket, :children, children)}
  end

  def handle_event("goto_step", %{"step" => step}, socket) do
    step = String.to_integer(step)
    {:noreply, maybe_advance(socket, step)}
  end

  def handle_event("send_invites", _params, socket) do
    case socket.assigns.children do
      [] ->
        {:noreply, assign(socket, :form_error, "Add at least one child first.")}

      children ->
        results = Enum.map(children, &send_invite(&1, socket.assigns.parent))
        {:noreply, socket |> assign(invite_results: results, step: 3, form_error: nil)}
    end
  end

  def handle_event("skip_upfront", _params, socket) do
    {:noreply, assign(socket, :step, 4)}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <.progress_header step={@step} />

      <%= case @step do %>
        <% 1 -> %>
          <.step_one draft={@draft} children={@children} form_error={@form_error} />
        <% 2 -> %>
          <.step_two children={@children} form_error={@form_error} />
        <% 3 -> %>
          <.step_three invite_results={@invite_results} />
        <% 4 -> %>
          <.step_four invite_results={@invite_results} />
      <% end %>
    </div>
    """
  end

  # ── Step components ──────────────────────────────────────────────────────

  attr :step, :integer, required: true

  def progress_header(assigns) do
    steps = [
      {1, "Child details"},
      {2, "Send invites"},
      {3, "Unlock now?"},
      {4, "Done"}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <div class="flex items-center justify-between text-xs font-medium">
      <div
        :for={{n, label} <- @steps}
        class={[
          "flex items-center gap-2",
          if(n <= @step, do: "text-[#4CD964]", else: "text-[#8E8E93]")
        ]}
      >
        <span class={[
          "w-6 h-6 rounded-full flex items-center justify-center text-xs font-semibold",
          if(n <= @step,
            do: "bg-[#4CD964] text-white",
            else: "bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#8E8E93]"
          )
        ]}>
          {n}
        </span>
        <span class="hidden sm:inline">{label}</span>
      </div>
    </div>
    """
  end

  attr :draft, :map, required: true
  attr :children, :list, required: true
  attr :form_error, :any, required: true

  def step_one(assigns) do
    grades = ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College Adult)
    assigns = assign(assigns, :grades, grades)

    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Who are you studying for?
      </h2>
      <p class="text-sm text-[#8E8E93]">
        Add each child once — you can add more than one.
      </p>

      <form phx-change="update_draft" phx-submit="add_child" class="space-y-3">
        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Child's name</span>
          <input
            type="text"
            name="display_name"
            value={@draft.display_name}
            required
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </label>

        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">
            Child's email
            <span class="text-[#8E8E93] font-normal">
              (optional — we'll make a claim code if you skip this)
            </span>
          </span>
          <input
            type="email"
            name="email"
            value={@draft.email}
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </label>

        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Grade</span>
          <select
            name="grade"
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          >
            <option value="">Select a grade…</option>
            <option :for={g <- @grades} value={g} selected={@draft.grade == g}>{g}</option>
          </select>
        </label>

        <p :if={@form_error} class="text-sm text-[#FF3B30]">{@form_error}</p>

        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
        >
          + Add this child
        </button>
      </form>

      <div
        :if={@children != []}
        class="border-t border-[#E5E5EA] dark:border-[#3A3A3C] pt-4 space-y-2"
      >
        <p class="text-sm font-semibold text-[#1C1C1E] dark:text-white">
          Added:
        </p>
        <ul class="space-y-2">
          <li
            :for={{child, idx} <- Enum.with_index(@children)}
            class="flex items-center justify-between px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl"
          >
            <div>
              <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
                {child.display_name}
                <span class="text-[#8E8E93] font-normal">· Grade {child.grade || "—"}</span>
              </p>
              <p class="text-xs text-[#8E8E93]">
                {if child.email && child.email != "", do: child.email, else: "will get a claim code"}
              </p>
            </div>
            <button
              type="button"
              phx-click="remove_child"
              phx-value-index={idx}
              class="text-xs text-[#FF3B30] hover:underline"
            >
              Remove
            </button>
          </li>
        </ul>
      </div>

      <div class="flex justify-end pt-2">
        <button
          type="button"
          phx-click="goto_step"
          phx-value-step="2"
          disabled={@children == []}
          class="bg-[#4CD964] hover:bg-[#3DBF55] disabled:bg-[#E5E5EA] disabled:text-[#8E8E93] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
        >
          Next — send invites
        </button>
      </div>
    </div>
    """
  end

  attr :children, :list, required: true
  attr :form_error, :any, required: true

  def step_two(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Link {length(@children) |> child_noun()}
      </h2>
      <p class="text-sm text-[#8E8E93]">
        We'll email {if length(@children) > 1, do: "them each", else: "them"} a sign-in link
        and give you a claim code to share in person.
      </p>

      <ul class="space-y-2">
        <li
          :for={child <- @children}
          class="px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl"
        >
          <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
            {child.display_name}
          </p>
          <p class="text-xs text-[#8E8E93]">
            {if child.email && child.email != "",
              do: "Invite email → #{child.email}",
              else: "Claim code only (no email)"}
          </p>
        </li>
      </ul>

      <p :if={@form_error} class="text-sm text-[#FF3B30]">{@form_error}</p>

      <div class="flex items-center justify-between pt-2">
        <button
          type="button"
          phx-click="goto_step"
          phx-value-step="1"
          class="px-4 py-2 text-sm text-[#8E8E93] hover:text-[#1C1C1E] dark:hover:text-white"
        >
          ← Back
        </button>
        <button
          type="button"
          phx-click="send_invites"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
        >
          Send invites
        </button>
      </div>
    </div>
    """
  end

  attr :invite_results, :list, required: true

  def step_three(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Unlock now, or wait for the ask?
      </h2>
      <p class="text-sm text-[#1C1C1E] dark:text-white">
        Most parents wait until their kid asks — but if you'd rather set this up now,
        here's what unlimited looks like.
      </p>

      <%!-- Per-child invite status --%>
      <div class="space-y-3">
        <div
          :for={res <- @invite_results}
          class="flex items-start gap-3 p-4 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl"
        >
          <div class="flex-1">
            <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
              {res.display_name}
            </p>
            <p class="text-xs text-[#8E8E93]">
              {status_text(res)}
            </p>
            <p :if={res[:code]} class="text-sm font-mono font-bold text-[#4CD964] mt-1">
              Claim code: {res.code}
            </p>
          </div>
          <.link
            navigate={"/subscription?beneficiary=#{res.display_name}"}
            class="text-sm text-[#007AFF] hover:underline"
          >
            Set up now →
          </.link>
        </div>
      </div>

      <%!-- Primary action: Skip for now (parent's intended path per §5.3) --%>
      <div class="flex items-center justify-end pt-2">
        <button
          type="button"
          phx-click="skip_upfront"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
        >
          Skip for now
        </button>
      </div>
    </div>
    """
  end

  attr :invite_results, :list, required: true

  def step_four(assigns) do
    assigns = assign(assigns, :count, length(assigns.invite_results))

    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
      <div class="text-5xl" aria-hidden="true">💚</div>
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        You're set up
      </h2>
      <p class="text-sm text-[#1C1C1E] dark:text-white max-w-md mx-auto">
        {@count |> Kernel.to_string()} {child_noun(@count)} {if @count == 1, do: "has", else: "have"} been invited. Here's what happens next:
      </p>
      <ul class="text-left max-w-md mx-auto space-y-2 text-sm text-[#1C1C1E] dark:text-white">
        <li>• They'll receive an email or sign in with a claim code you share.</li>
        <li>• You'll see their study progress on your parent dashboard.</li>
        <li>
          • If they hit the weekly free-practice cap, you'll get an email — no action required today.
        </li>
      </ul>

      <.link
        navigate="/parent"
        class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
      >
        Go to parent dashboard
      </.link>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp empty_child do
    %{display_name: "", email: "", grade: ""}
  end

  defp atomize(params) when is_map(params) do
    for {k, v} <- Map.take(params, ~w(display_name email grade)),
        into: %{},
        do: {String.to_atom(k), v}
  end

  defp validate_child(%{display_name: n}) when not is_binary(n) or n == "",
    do: {:error, "Please enter the child's name."}

  defp validate_child(%{email: e}) when is_binary(e) and e != "" do
    if Regex.match?(~r/^[^\s]+@[^\s]+$/, e), do: :ok, else: {:error, "That email looks off."}
  end

  defp validate_child(_), do: :ok

  defp maybe_advance(socket, 2) do
    if socket.assigns.children == [],
      do: assign(socket, :form_error, "Add at least one child first."),
      else: assign(socket, step: 2, form_error: nil)
  end

  defp maybe_advance(socket, step), do: assign(socket, step: step, form_error: nil)

  defp send_invite(child, parent) do
    attrs = %{
      relationship_type: :parent,
      child_display_name: child.display_name,
      child_email: nilify(child.email),
      child_grade: nilify(child.grade),
      metadata: %{}
    }

    case InviteCodes.create(parent.id, attrs) do
      {:ok, invite} ->
        %{
          display_name: child.display_name,
          email: invite.child_email,
          code: invite.code,
          status: if(invite.child_email, do: :email_and_code, else: :code_only)
        }

      {:error, _cs} ->
        %{
          display_name: child.display_name,
          email: child.email,
          code: nil,
          status: :failed
        }
    end
  end

  defp nilify(""), do: nil
  defp nilify(v), do: v

  defp status_text(%{status: :email_and_code}),
    do: "Invite email sent + claim code ready"

  defp status_text(%{status: :code_only}), do: "Share the claim code below"
  defp status_text(%{status: :failed}), do: "Couldn't create the invite — try again"
  defp status_text(_), do: ""

  defp child_noun(1), do: "child"
  defp child_noun(_), do: "children"

  def grades, do: @grades
end
