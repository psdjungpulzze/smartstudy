defmodule FunSheep.Integrations.Provider do
  @moduledoc """
  Behaviour implemented by each external LMS/school-app adapter
  (Google Classroom, Canvas, ParentSquare).

  All provider-specific HTTP work, API shape normalisation, and test-schedule
  heuristics live in the adapter — the context + worker stay provider-agnostic.
  """

  @type raw_course :: map()
  @type raw_assignment :: map()
  @type normalized_course :: map()
  @type normalized_assignment :: map() | :skip

  @callback service_id() :: String.t()
  @callback default_scopes() :: [String.t()]

  @callback list_courses(access_token :: String.t(), opts :: keyword()) ::
              {:ok, [raw_course()]} | {:error, term()}

  @callback list_assignments(
              access_token :: String.t(),
              external_course_id :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, [raw_assignment()]} | {:error, term()}

  @callback normalize_course(raw_course()) :: normalized_course()

  @callback normalize_assignment(
              raw_assignment(),
              local_course_id :: Ecto.UUID.t(),
              user_role_id :: Ecto.UUID.t()
            ) :: normalized_assignment()

  @doc """
  Supported? Some adapters (ParentSquare v1) are stubs that report
  `supported?/0 == false`. Registry uses this to render "Coming soon".
  """
  @callback supported?() :: boolean()

  @optional_callbacks supported?: 0
end
