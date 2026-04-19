defmodule FunSheepWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for authentication and common assigns.
  Supports both real Interactor auth and dev auth bypass.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias FunSheep.{Accounts, Learning}

  def on_mount(:require_auth, _params, session, socket) do
    case get_user_from_session(session) do
      {:ok, user} ->
        {streak_count, total_xp, due_reviews} = load_gamification_stats(user["id"])

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
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _} ->
          try do
            Accounts.get_user_role!(user_role_id)
          rescue
            Ecto.NoResultsError -> nil
          end

        :error ->
          nil
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
