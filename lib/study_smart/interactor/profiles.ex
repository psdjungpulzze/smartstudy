defmodule StudySmart.Interactor.Profiles do
  @moduledoc """
  Interface to the Interactor User Profiles API.

  Stores and retrieves student preferences (grade, school, nationality,
  hobbies, learning preferences) keyed by `external_user_id`.
  """

  alias StudySmart.Interactor.Client

  @base_path "/api/v1/profiles"

  @doc "Gets the profile for the given external user ID."
  @spec get_profile(String.t()) :: {:ok, map()} | {:error, term()}
  def get_profile(external_user_id) do
    Client.get("#{@base_path}/#{external_user_id}")
  end

  @doc "Updates the profile for the given external user ID."
  @spec update_profile(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_profile(external_user_id, attrs) do
    Client.put("#{@base_path}/#{external_user_id}", attrs)
  end

  @doc "Gets the effective (merged) profile for the given external user ID."
  @spec get_effective_profile(String.t()) :: {:ok, map()} | {:error, term()}
  def get_effective_profile(external_user_id) do
    Client.get("#{@base_path}/#{external_user_id}/effective")
  end
end
