defmodule FunSheepWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for authentication and common assigns.
  Supports both real Interactor auth and dev auth bypass.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias FunSheep.{Accounts, Learning, Tutorials}

  def on_mount(:require_auth, _params, session, socket) do
    case get_user_from_session(session) do
      {:ok, user} ->
        user = normalize_user(user)
        {streak_count, total_xp, due_reviews} = load_gamification_stats(user["user_role_id"])

        profile_gaps = compute_profile_gaps(user)

        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, user["role"])
          |> assign(:current_path, nil)
          |> assign(:streak_count, streak_count)
          |> assign(:total_xp, total_xp)
          |> assign(:due_reviews, due_reviews)
          |> assign(:profile_gaps, profile_gaps)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)
          |> attach_hook(:gate_onboarding, :handle_params, &gate_onboarding/3)
          |> attach_hook(:tutorial_events, :handle_event, &handle_tutorial_event/3)
          |> assign(:show_tutorial, false)
          |> assign(:tutorial_config, nil)

        {:cont, socket}

      :not_authenticated ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: login_path())

        {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case get_user_from_session(session) do
      {:ok, %{"role" => "admin"} = user} ->
        user = normalize_user(user)

        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, "admin")
          |> assign(:current_path, nil)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

        {:cont, socket}

      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:error, "You do not have admin access.")
          |> redirect(to: "/dashboard")

        {:halt, socket}

      :not_authenticated ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: login_path())

        {:halt, socket}
    end
  end

  # Patches legacy session shapes: older sessions stored `user["id"]` as the
  # Interactor sub and had no `user_role_id`. Re-resolve the local user_role
  # so `user["id"]` and `user["user_role_id"]` point at the local PK.
  defp normalize_user(%{"user_role_id" => id} = user)
       when is_binary(id) and id != "" do
    user
  end

  defp normalize_user(%{"interactor_user_id" => interactor_id} = user)
       when is_binary(interactor_id) and interactor_id != "" and interactor_id != "unknown" do
    case Accounts.get_user_role_by_interactor_id(interactor_id) do
      %Accounts.UserRole{id: id} ->
        user
        |> Map.put("user_role_id", id)
        |> Map.put("id", id)

      nil ->
        Map.put(user, "user_role_id", nil)
    end
  end

  defp normalize_user(user), do: Map.put_new(user, "user_role_id", nil)

  # Check real auth first, then fall back to dev auth
  defp get_user_from_session(%{"current_user" => user}) when is_map(user) do
    {:ok, user}
  end

  defp get_user_from_session(%{"dev_user" => user, "dev_user_id" => _id}) do
    {:ok, user}
  end

  defp get_user_from_session(_), do: :not_authenticated

  defp login_path do
    if Application.get_env(:fun_sheep, :dev_routes) do
      "/dev/login"
    else
      "/"
    end
  end

  defp save_request_path(_params, url, socket) do
    uri = URI.parse(url)
    {:cont, assign(socket, :current_path, uri.path)}
  end

  @doc """
  Assigns tutorial config on a LiveView socket. Reads the persisted
  seen-state so the overlay auto-shows once per user per key, and is
  dismissed/replayed via global `dismiss_tutorial` / `replay_tutorial`
  events handled in this module.

  ## Example

      socket
      |> LiveHelpers.assign_tutorial(
        key: "dashboard",
        title: "Welcome to FunSheep!",
        subtitle: "A quick tour of your home base.",
        steps: [
          %{emoji: "📚", title: "Courses", body: "Browse or create courses"},
          %{emoji: "⚡", title: "Practice", body: "Quick-fire flashcards"}
        ]
      )
  """
  def assign_tutorial(socket, opts) do
    key = Keyword.fetch!(opts, :key)
    title = Keyword.fetch!(opts, :title)
    steps = Keyword.fetch!(opts, :steps)
    subtitle = Keyword.get(opts, :subtitle)
    cta_label = Keyword.get(opts, :cta_label, "Got it!")

    user_role_id = get_in(socket.assigns, [:current_user, "user_role_id"])
    seen = Tutorials.seen?(user_role_id, key)

    socket
    |> assign(:show_tutorial, not seen)
    |> assign(:tutorial_config, %{
      key: key,
      title: title,
      subtitle: subtitle,
      cta_label: cta_label,
      steps: steps
    })
  end

  defp handle_tutorial_event("dismiss_tutorial", _params, socket) do
    case socket.assigns[:tutorial_config] do
      %{key: key} ->
        user_role_id = get_in(socket.assigns, [:current_user, "user_role_id"])
        Tutorials.mark_seen(user_role_id, key)
        {:halt, assign(socket, show_tutorial: false)}

      _ ->
        {:cont, socket}
    end
  end

  defp handle_tutorial_event("replay_tutorial", _params, socket) do
    if socket.assigns[:tutorial_config] do
      {:halt, assign(socket, show_tutorial: true)}
    else
      {:cont, socket}
    end
  end

  defp handle_tutorial_event(_event, _params, socket), do: {:cont, socket}

  # Redirects first-time students (missing grade or hobbies) to /profile/setup.
  # Teachers and parents are exempt — the gap fields (grade, hobbies) are
  # student-specific. The profile setup page and the subscription/guardian
  # flows pass through freely so users aren't trapped. Disabled in test
  # (via :fun_sheep, :onboarding_gate) so live tests can hit feature
  # pages without first filling out a profile fixture.
  @onboarding_exempt_paths ~w(/profile/setup /guardians /subscription)
  defp gate_onboarding(_params, url, socket) do
    uri = URI.parse(url)
    path = uri.path || ""
    gaps = socket.assigns[:profile_gaps] || []
    role = socket.assigns[:current_role]
    user_role_id = get_in(socket.assigns, [:current_user, "user_role_id"])

    cond do
      not onboarding_gate_enabled?() -> {:cont, socket}
      role != "student" -> {:cont, socket}
      not valid_uuid?(user_role_id) -> {:cont, socket}
      gaps == [] -> {:cont, socket}
      path in @onboarding_exempt_paths -> {:cont, socket}
      String.starts_with?(path, "/auth/") -> {:cont, socket}
      true -> {:halt, redirect(socket, to: "/profile/setup")}
    end
  end

  defp onboarding_gate_enabled?,
    do: Application.get_env(:fun_sheep, :onboarding_gate, true)

  defp valid_uuid?(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp valid_uuid?(_), do: false

  defp load_gamification_stats(user_role_id) do
    case Ecto.UUID.cast(user_role_id) do
      {:ok, _uuid} ->
        case FunSheep.Gamification.get_or_create_streak(user_role_id) do
          {:ok, streak} ->
            total_xp = FunSheep.Gamification.total_xp(user_role_id)
            due_reviews = FunSheep.Engagement.SpacedRepetition.due_card_count(user_role_id)
            {streak.current_streak, total_xp, due_reviews}

          {:error, _} ->
            {0, 0, 0}
        end

      :error ->
        {0, 0, 0}
    end
  end

  @doc """
  Computes what's missing from the user's profile.
  Returns a list of gap atoms: [:grade, :hobbies]
  Empty list = profile is complete.
  """
  def compute_profile_gaps(user) do
    user_role_id = user["user_role_id"] || user["id"]

    user_role =
      with id when is_binary(id) and id != "" <- user_role_id,
           {:ok, _} <- Ecto.UUID.cast(id) do
        Accounts.get_user_role(id)
      else
        _ -> nil
      end

    gaps = []

    gaps =
      if is_nil(user_role) or is_nil(user_role.grade) or user_role.grade == "" do
        [:grade | gaps]
      else
        gaps
      end

    gaps =
      if user_role do
        hobbies = Learning.list_hobbies_for_user(user_role.id)
        if hobbies == [], do: [:hobbies | gaps], else: gaps
      else
        [:hobbies | gaps]
      end

    Enum.reverse(gaps)
  end
end
