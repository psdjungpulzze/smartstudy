defmodule StudySmart.Interactor.Workflows do
  @moduledoc """
  Interface to the Interactor Workflows API.

  Manages workflow definitions, instances, and state transitions.
  Supports halting states for human-in-the-loop interactions.
  """

  alias StudySmart.Interactor.Client

  @base_path "/api/v1/workflows"

  @doc "Creates a new workflow definition."
  @spec create_workflow(map()) :: {:ok, map()} | {:error, term()}
  def create_workflow(attrs) do
    Client.post(@base_path, attrs)
  end

  @doc "Creates a new workflow instance from a definition."
  @spec create_instance(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_instance(workflow_id, input) do
    Client.post("#{@base_path}/#{workflow_id}/instances", %{input: input})
  end

  @doc "Resumes a halted workflow instance with the given input."
  @spec resume_instance(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def resume_instance(instance_id, input) do
    Client.post("#{@base_path}/instances/#{instance_id}/resume", %{input: input})
  end

  @doc "Gets the current state of a workflow instance."
  @spec get_instance(String.t()) :: {:ok, map()} | {:error, term()}
  def get_instance(instance_id) do
    Client.get("#{@base_path}/instances/#{instance_id}")
  end
end
