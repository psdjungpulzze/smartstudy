defmodule FunSheepWeb.ParentSettingsLive do
  @moduledoc """
  `/parent/settings` — guardian-only settings page (spec §8.2 / §8.4).

  Manages:

    * weekly digest frequency (`:weekly | :off`)
    * opt-in alerts (`:alerts_skipped_days`, `:alerts_readiness_drop`;
      `:alerts_goal_achieved` stays on by default)

  Parents can also unsubscribe from every email at once. All writes go
  through `Accounts.update_user_role/2`, which already guards email and
  interactor_user_id via the schema.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
      nil ->
        {:ok, assign(socket, page_title: "Settings", user_role: nil)}

      user_role ->
        {:ok,
         socket
         |> assign(page_title: "Settings", user_role: user_role)
         |> assign(:saved?, false)}
    end
  end

  @impl true
  def handle_event("save_settings", params, socket) do
    case socket.assigns.user_role do
      nil ->
        {:noreply, socket}

      user_role ->
        attrs = %{
          digest_frequency: digest_pref(params["digest_frequency"]),
          alerts_skipped_days: checked?(params["alerts_skipped_days"]),
          alerts_readiness_drop: checked?(params["alerts_readiness_drop"]),
          alerts_goal_achieved: checked?(params["alerts_goal_achieved"])
        }

        case Accounts.update_user_role(user_role, attrs) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(user_role: updated, saved?: true)}

          {:error, _cs} ->
            {:noreply, socket}
        end
    end
  end

  defp digest_pref("off"), do: :off
  defp digest_pref(_), do: :weekly

  defp checked?("on"), do: true
  defp checked?(true), do: true
  defp checked?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto space-y-4 sm:space-y-6">
      <div>
        <h1 class="text-xl sm:text-2xl font-extrabold text-gray-900">
          {gettext("Notification settings")}
        </h1>
        <p class="text-gray-500 text-sm mt-0.5">
          {gettext("Pick what we email you about your student.")}
        </p>
      </div>

      <div
        :if={@user_role == nil}
        class="bg-white rounded-2xl border border-gray-100 p-5 text-sm text-gray-600"
      >
        {gettext("Sign in as a guardian to manage settings.")}
      </div>

      <form
        :if={@user_role}
        phx-submit="save_settings"
        class="bg-white rounded-2xl border border-gray-100 p-5 space-y-5"
      >
        <div>
          <p class="text-sm font-extrabold text-gray-900">
            {gettext("Weekly digest")}
          </p>
          <p class="text-xs text-gray-500 mt-0.5">
            {gettext(
              "A short Sunday recap of this week's activity, readiness change, and one conversation opener."
            )}
          </p>
          <label class="flex items-center gap-2 mt-2 text-sm">
            <input
              type="radio"
              name="digest_frequency"
              value="weekly"
              checked={@user_role.digest_frequency == :weekly}
            />
            {gettext("Send weekly")}
          </label>
          <label class="flex items-center gap-2 mt-1 text-sm">
            <input
              type="radio"
              name="digest_frequency"
              value="off"
              checked={@user_role.digest_frequency == :off}
            />
            {gettext("Off")}
          </label>
        </div>

        <div>
          <p class="text-sm font-extrabold text-gray-900">
            {gettext("Alerts")}
          </p>
          <p class="text-xs text-gray-500 mt-0.5">
            {gettext("Opt-in. We never turn surveillance alerts on for you by default.")}
          </p>
          <label class="flex items-start gap-2 mt-3 text-sm">
            <input
              type="checkbox"
              name="alerts_skipped_days"
              checked={@user_role.alerts_skipped_days}
            />
            <span>
              {gettext("3+ skipped study days (with an active daily-minutes goal)")}
            </span>
          </label>
          <label class="flex items-start gap-2 mt-2 text-sm">
            <input
              type="checkbox"
              name="alerts_readiness_drop"
              checked={@user_role.alerts_readiness_drop}
            />
            <span>
              {gettext("Readiness drop > 10% week-over-week within 21 days of a test")}
            </span>
          </label>
          <label class="flex items-start gap-2 mt-2 text-sm">
            <input
              type="checkbox"
              name="alerts_goal_achieved"
              checked={@user_role.alerts_goal_achieved}
            />
            <span>
              {gettext("Goal achieved (celebratory — on by default)")}
            </span>
          </label>
        </div>

        <div class="flex items-center justify-end gap-3">
          <span :if={@saved?} class="text-xs text-[#256029]">
            {gettext("Saved.")}
          </span>
          <button
            type="submit"
            class="text-sm font-bold bg-[#4CD964] hover:bg-[#3DBF55] text-white px-5 py-2 rounded-full shadow-md"
          >
            {gettext("Save")}
          </button>
        </div>
      </form>
    </div>
    """
  end
end
