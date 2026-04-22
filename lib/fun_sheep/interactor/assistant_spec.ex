defmodule FunSheep.Interactor.AssistantSpec do
  @moduledoc """
  Behaviour for FunSheep modules that own an Interactor assistant.

  The admin `/admin/interactor/agents` page reads every module implementing
  this behaviour to display the "intended" config alongside the live
  Interactor config, so drift (e.g. model changed manually on Interactor
  console but not in code) is obvious.

  Declare an assistant like this:

      defmodule FunSheep.Questions.Validation do
        @behaviour FunSheep.Interactor.AssistantSpec

        @impl true
        def assistant_attrs, do: %{
          name: "question_quality_reviewer",
          description: "…",
          llm_provider: "openai",
          llm_model: "gpt-4o-mini",
          …
        }
      end
  """

  @doc """
  Returns the intended configuration for this module's assistant.

  Must include at minimum `:name`, `:llm_provider`, and `:llm_model`.
  """
  @callback assistant_attrs() :: map()
end
