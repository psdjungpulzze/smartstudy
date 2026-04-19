defmodule FunSheep.Interactor.Agents do
  @moduledoc """
  Interface to the Interactor AI Agents API.

  Manages assistants, rooms, messages, and tool callbacks.
  In mock mode, returns stub data without making HTTP requests.
  """

  alias FunSheep.Interactor.Client

  @base_path "/api/v1/agents"

  @doc "Creates a new assistant with the given attributes."
  @spec create_assistant(map()) :: {:ok, map()} | {:error, term()}
  def create_assistant(attrs) do
    Client.post("#{@base_path}/assistants", attrs)
  end

  @doc "Lists all assistants."
  @spec list_assistants() :: {:ok, map()} | {:error, term()}
  def list_assistants do
    Client.get("#{@base_path}/assistants")
  end

  @doc "Creates a room for the given assistant and external user."
  @spec create_room(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_room(assistant_id, external_user_id, metadata \\ %{}) do
    Client.post("#{@base_path}/#{assistant_id}/rooms", %{
      external_user_id: external_user_id,
      metadata: metadata
    })
  end

  @doc "Sends a message to the given room."
  @spec send_message(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_message(room_id, content, opts \\ %{}) do
    Client.post("#{@base_path}/rooms/#{room_id}/messages", Map.merge(%{content: content}, opts))
  end

  @doc "Lists messages in the given room."
  @spec list_messages(String.t()) :: {:ok, map()} | {:error, term()}
  def list_messages(room_id) do
    Client.get("#{@base_path}/rooms/#{room_id}/messages")
  end

  @doc "Closes a room, ending the conversation."
  @spec close_room(String.t()) :: {:ok, map()} | {:error, term()}
  def close_room(room_id) do
    Client.post("#{@base_path}/rooms/#{room_id}/close", %{})
  end
end
