defmodule FunSheep.Interactor.Agents do
  @moduledoc """
  Interface to the Interactor AI Agents API.

  Manages assistants, rooms, messages, and provides a high-level `chat/3`
  function that handles the full room lifecycle for synchronous AI requests
  from background workers.

  ## Architecture

  Interactor uses a room-based conversational model:
  1. Create a room with an assistant
  2. Send a message to the room
  3. Wait for the AI response via polling
  4. Close the room

  The `chat/3` function wraps this entire flow into a single synchronous call.

  ## Assistant Resolution

  Workers reference assistants by name (e.g., `"course_discovery"`), but the
  Interactor API requires UUIDs. This module resolves names to IDs by fetching
  the assistant list and caching the mapping in `persistent_term`.
  """

  alias FunSheep.AIUsage
  alias FunSheep.Interactor.Client

  require Logger

  @base_path "/api/v1/agents"
  @response_timeout 60_000
  @poll_interval 1_500
  @max_polls 40
  @cache_key :interactor_assistant_map

  # --- High-Level API ---

  @doc """
  Sends a prompt to an Interactor AI assistant and waits for the response.

  Creates a temporary room, sends the message, polls for the assistant's reply,
  then closes the room. This is the primary interface for background workers
  that need synchronous AI responses.

  The `assistant_name` is resolved to a UUID via the assistant list API.

  ## Parameters

    - `assistant_name` - The assistant name (e.g., `"question_gen"`, `"web_search"`)
    - `prompt` - The message content to send
    - `opts` - Optional map with:
      - `:metadata` - Metadata to attach to the room
      - `:timeout` - Max wait time in ms (default: 60_000)

  ## Returns

    - `{:ok, response_text}` - The assistant's response as a string
    - `{:error, reason}` - If the request failed
  """
  @spec chat(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def chat(assistant_name, prompt, opts \\ %{}) do
    timeout = opts[:timeout] || @response_timeout
    metadata = opts[:metadata] || %{}
    source = opts[:source] || assistant_name
    external_user_id = "funsheep_worker_#{:erlang.system_time(:millisecond)}"
    started_at = System.monotonic_time(:millisecond)

    result =
      with {:ok, assistant_id} <- resolve_assistant(assistant_name),
           {:ok, room} <- create_room(assistant_id, external_user_id, metadata),
           room_id <- extract_id(room),
           {:ok, _msg} <- send_message(room_id, prompt),
           {:ok, assistant_message} <- await_response(room_id, timeout) do
        # Close room in background — don't block on it
        Task.start(fn -> close_room(room_id) end)
        {:ok, assistant_message}
      end

    duration_ms = System.monotonic_time(:millisecond) - started_at
    record_usage(result, assistant_name, prompt, source, metadata, duration_ms)

    case result do
      {:ok, %{"content" => content}} ->
        {:ok, content}

      {:error, reason} = error ->
        Logger.error("[Agents] chat failed for assistant #{assistant_name}: #{inspect(reason)}")
        error
    end
  end

  # One AIUsage row per chat invocation, regardless of outcome. Telemetry
  # failures are swallowed inside AIUsage.log_call/1 so they can't cascade.
  defp record_usage({:ok, message}, assistant_name, prompt, source, metadata, duration_ms) do
    AIUsage.log_call(%{
      provider: "interactor",
      model: Map.get(message, "model"),
      assistant_name: assistant_name,
      source: source,
      prompt: prompt,
      response: Map.get(message, "content"),
      prompt_tokens: Map.get(message, "input_tokens"),
      completion_tokens: Map.get(message, "output_tokens"),
      duration_ms: duration_ms,
      status: "ok",
      metadata: metadata
    })
  end

  defp record_usage({:error, reason}, assistant_name, prompt, source, metadata, duration_ms) do
    status = if reason == :timeout, do: "timeout", else: "error"

    AIUsage.log_call(%{
      provider: "interactor",
      assistant_name: assistant_name,
      source: source,
      prompt: prompt,
      duration_ms: duration_ms,
      status: status,
      error: inspect(reason),
      metadata: metadata
    })
  end

  # --- Assistant Resolution ---

  @doc """
  Resolves an assistant name to its UUID.

  Fetches the assistant list from Interactor and caches the name→ID mapping.
  Cache is refreshed if the requested name isn't found (handles new assistants).
  """
  @spec resolve_assistant(String.t()) :: {:ok, String.t()} | {:error, term()}
  def resolve_assistant(name) do
    # If it looks like a UUID already, pass through
    if uuid?(name) do
      {:ok, name}
    else
      case get_cached_id(name) do
        {:ok, id} ->
          {:ok, id}

        :miss ->
          # Cache miss — refresh from API
          case refresh_assistant_cache() do
            :ok -> get_cached_id(name) |> normalize_cache_result(name)
            {:error, _} = error -> error
          end
      end
    end
  end

  # --- Room Lifecycle ---

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
  @spec list_messages(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_messages(room_id, opts \\ []) do
    query =
      opts
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    path =
      if query == "",
        do: "#{@base_path}/rooms/#{room_id}/messages",
        else: "#{@base_path}/rooms/#{room_id}/messages?#{query}"

    Client.get(path)
  end

  @doc "Closes a room, ending the conversation."
  @spec close_room(String.t()) :: {:ok, map()} | {:error, term()}
  def close_room(room_id) do
    Client.post("#{@base_path}/rooms/#{room_id}/close", %{})
  end

  # --- Assistant Management ---

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

  # --- Private Helpers ---

  defp uuid?(str) do
    Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, str)
  end

  defp get_cached_id(name) do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        :miss

      map ->
        Map.get(map, name)
        |> case do
          nil -> :miss
          id -> {:ok, id}
        end
    end
  end

  defp normalize_cache_result({:ok, id}, _name), do: {:ok, id}

  defp normalize_cache_result(:miss, name) do
    Logger.error("[Agents] Assistant '#{name}' not found on Interactor server")
    {:error, {:assistant_not_found, name}}
  end

  defp refresh_assistant_cache do
    case list_assistants() do
      {:ok, %{"data" => assistants}} when is_list(assistants) ->
        map =
          Map.new(assistants, fn a ->
            {a["name"], a["id"]}
          end)

        :persistent_term.put(@cache_key, map)
        Logger.debug("[Agents] Cached #{map_size(map)} assistant name→ID mappings")
        :ok

      {:ok, unexpected} ->
        Logger.error("[Agents] Unexpected assistant list response: #{inspect(unexpected)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.error("[Agents] Failed to fetch assistants: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Await the assistant's response by polling messages.
  defp await_response(room_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_for_response(room_id, deadline, 0)
  end

  defp poll_for_response(room_id, deadline, attempt) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      Logger.warning("[Agents] Timed out waiting for response in room #{room_id}")
      {:error, :timeout}
    else
      if attempt > 0 do
        Process.sleep(@poll_interval)
      end

      case list_messages(room_id) do
        {:ok, %{"data" => messages}} when is_list(messages) ->
          assistant_messages =
            Enum.filter(messages, fn m ->
              m["role"] == "assistant" && is_binary(m["content"]) && m["content"] != ""
            end)

          case List.last(assistant_messages) do
            %{"content" => _} = message ->
              {:ok, message}

            nil ->
              if attempt < @max_polls do
                poll_for_response(room_id, deadline, attempt + 1)
              else
                {:error, :no_response}
              end
          end

        {:ok, _unexpected} ->
          if attempt < @max_polls do
            poll_for_response(room_id, deadline, attempt + 1)
          else
            {:error, :unexpected_message_format}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_id(%{"data" => %{"id" => id}}), do: id
  defp extract_id(%{"id" => id}), do: id
  defp extract_id(other), do: other
end
