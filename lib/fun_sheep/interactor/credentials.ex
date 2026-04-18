defmodule FunSheep.Interactor.Credentials do
  @moduledoc """
  Interface to the Interactor Credential Management API.

  Manages OAuth credentials for external services (e.g., Google OAuth
  for Docs export, YouTube API). Credentials are stored per
  `external_user_id` with automatic token refresh.
  """

  alias FunSheep.Interactor.Client

  @base_path "/api/v1/credentials"

  @doc "Initiates an OAuth flow for the given service configuration."
  @spec initiate_oauth(map()) :: {:ok, map()} | {:error, term()}
  def initiate_oauth(attrs) do
    Client.post("#{@base_path}/oauth/initiate", attrs)
  end

  @doc "Lists credentials for the given external user ID."
  @spec list_credentials(String.t()) :: {:ok, map()} | {:error, term()}
  def list_credentials(external_user_id) do
    Client.get("#{@base_path}/#{external_user_id}")
  end

  @doc "Gets a valid access token for the given credential ID."
  @spec get_token(String.t()) :: {:ok, map()} | {:error, term()}
  def get_token(credential_id) do
    Client.get("#{@base_path}/#{credential_id}/token")
  end
end
