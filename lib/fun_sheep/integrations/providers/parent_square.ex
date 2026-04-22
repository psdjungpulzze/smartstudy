defmodule FunSheep.Integrations.Providers.ParentSquare do
  @moduledoc """
  ParentSquare adapter (stub).

  ParentSquare does not publish an open OAuth API for student-level
  course data. Until SKB has a verified service record and/or we have
  a district-admin integration path or email-forwarding pipeline, this
  provider renders as "Coming soon" in the UI and refuses to initiate
  OAuth.

  See `docs/i/guides/integrations.md` for the full rationale.
  """

  @behaviour FunSheep.Integrations.Provider

  require Logger

  @impl true
  def service_id, do: "parentsquare"

  @impl true
  def default_scopes, do: []

  @impl true
  def supported?, do: false

  @impl true
  def list_courses(_access_token, _opts \\ []) do
    {:error, :not_supported}
  end

  @impl true
  def list_assignments(_access_token, _course_id, _opts \\ []) do
    {:error, :not_supported}
  end

  @impl true
  def normalize_course(_raw), do: %{}

  @impl true
  def normalize_assignment(_raw, _course_id, _user_role_id), do: :skip
end
