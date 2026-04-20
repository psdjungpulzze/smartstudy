defmodule FunSheep.Tutorials do
  @moduledoc """
  The Tutorials context.

  Tracks whether a user has seen a given in-app tutorial so first-time
  overlays auto-show but aren't nagged after dismissal. Tutorials are
  keyed by string (e.g. "quick_practice") and are replayable via the
  help (?) button on any page.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Tutorials.UserTutorial

  @doc """
  Returns true if the user has completed/dismissed the given tutorial.

  nil or unset user_role_id returns false (treat as "not seen") so the
  tutorial shows on their next visit after identification completes.
  """
  def seen?(nil, _key), do: false

  def seen?(user_role_id, tutorial_key) when is_binary(tutorial_key) do
    case Ecto.UUID.cast(user_role_id) do
      {:ok, _} ->
        from(t in UserTutorial,
          where: t.user_role_id == ^user_role_id and t.tutorial_key == ^tutorial_key,
          limit: 1
        )
        |> Repo.exists?()

      :error ->
        false
    end
  end

  @doc """
  Marks a tutorial as seen. Idempotent: if an entry already exists it's
  left alone (we preserve the original completed_at).
  """
  def mark_seen(nil, _key), do: {:error, :no_user}

  def mark_seen(user_role_id, tutorial_key) when is_binary(tutorial_key) do
    attrs = %{
      user_role_id: user_role_id,
      tutorial_key: tutorial_key,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %UserTutorial{}
    |> UserTutorial.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_role_id, :tutorial_key]
    )
  end

  @doc """
  Clears the seen-state for a tutorial so it auto-shows again on next
  visit. Used by admin/debug flows; the help button replays without
  calling this (it just re-opens the overlay in the current session).
  """
  def reset(nil, _key), do: {0, nil}

  def reset(user_role_id, tutorial_key) when is_binary(tutorial_key) do
    from(t in UserTutorial,
      where: t.user_role_id == ^user_role_id and t.tutorial_key == ^tutorial_key
    )
    |> Repo.delete_all()
  end
end
