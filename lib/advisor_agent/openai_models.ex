defmodule AdvisorAgent.OpenAIModels do
  @moduledoc """
  Centralized module for managing OpenAI model specifications.

  This module provides type-safe model identifiers using atoms and
  conversion functions for API calls.
  """

  # Available chat completion models
  @chat_models %{
    gpt_3_5_turbo: "gpt-3.5-turbo",
    gpt_4: "gpt-4",
    gpt_4_turbo: "gpt-4-turbo",
    gpt_4o: "gpt-4o",
    gpt_4o_mini: "gpt-4o-mini",
    gpt_4_1: "gpt-4.1",
    gpt_4_1_mini: "gpt-4.1-mini",
    gpt_4_1_nano: "gpt-4.1-nano",
    gpt_5: "gpt-5",
    gpt_5_mini: "gpt-5-mini"
  }

  # Available embedding models
  @embedding_models %{
    text_embedding_ada_002: "text-embedding-ada-002",
    text_embedding_3_small: "text-embedding-3-small",
    text_embedding_3_large: "text-embedding-3-large"
  }

  @doc """
  Returns the default chat model.
  """
  def default_chat_model, do: :gpt_4_1_mini

  @doc """
  Returns the default embedding model.
  """
  def default_embedding_model, do: :text_embedding_ada_002

  @doc """
  Converts a model atom to its API string representation.

  ## Examples

      iex> AdvisorAgent.OpenAIModels.to_string(:gpt_3_5_turbo)
      "gpt-3.5-turbo"

      iex> AdvisorAgent.OpenAIModels.to_string(:text_embedding_ada_002)
      "text-embedding-ada-002"
  """
  def to_string(model) when is_atom(model) do
    @chat_models[model] || @embedding_models[model] ||
      raise ArgumentError, "Unknown model: #{inspect(model)}"
  end

  @doc """
  Checks if the given atom is a valid chat model.

  ## Examples

      iex> AdvisorAgent.OpenAIModels.valid_chat_model?(:gpt_3_5_turbo)
      true

      iex> AdvisorAgent.OpenAIModels.valid_chat_model?(:invalid_model)
      false
  """
  def valid_chat_model?(model) when is_atom(model) do
    Map.has_key?(@chat_models, model)
  end

  @doc """
  Checks if the given atom is a valid embedding model.

  ## Examples

      iex> AdvisorAgent.OpenAIModels.valid_embedding_model?(:text_embedding_ada_002)
      true

      iex> AdvisorAgent.OpenAIModels.valid_embedding_model?(:invalid_model)
      false
  """
  def valid_embedding_model?(model) when is_atom(model) do
    Map.has_key?(@embedding_models, model)
  end

  @doc """
  Returns a list of all available chat models as atoms.
  """
  def list_chat_models do
    Map.keys(@chat_models)
  end

  @doc """
  Returns a list of all available embedding models as atoms.
  """
  def list_embedding_models do
    Map.keys(@embedding_models)
  end
end
