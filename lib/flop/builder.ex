defmodule Flop.Builder do
  @moduledoc false

  import Ecto.Query
  import Flop.Operators

  alias Flop.Filter

  require Logger

  @operators [
    :==,
    :!=,
    :empty,
    :not_empty,
    :>=,
    :<=,
    :>,
    :<,
    :in,
    :contains,
    :not_contains,
    :like,
    :=~,
    :ilike,
    :not_in,
    :like_and,
    :like_or,
    :ilike_and,
    :ilike_or
  ]

  def filter(_, %Filter{field: nil}, c), do: c
  def filter(_, %Filter{value: nil}, c), do: c

  def filter(
        schema_struct,
        %Filter{field: field} = filter,
        conditions
      ) do
    build_op(
      conditions,
      schema_struct,
      get_field_type(schema_struct, field),
      filter
    )
  end

  defp build_op(c, schema_struct, {:compound, fields}, %Filter{op: op} = filter)
       when op in [
              :=~,
              :like,
              :like_and,
              :like_or,
              :ilike,
              :ilike_and,
              :ilike_or,
              :not_empty
            ] do
    compound_dynamic =
      fields
      |> Enum.map(&get_field_type(schema_struct, &1))
      |> Enum.reduce(false, fn field, dynamic ->
        dynamic_for_field =
          build_op(true, schema_struct, field, %{filter | field: field})

        dynamic([r], ^dynamic or ^dynamic_for_field)
      end)

    dynamic([r], ^c and ^compound_dynamic)
  end

  defp build_op(
         c,
         schema_struct,
         {:compound, fields},
         %Filter{op: :empty} = filter
       ) do
    compound_dynamic =
      fields
      |> Enum.map(&get_field_type(schema_struct, &1))
      |> Enum.reduce(true, fn field, dynamic ->
        dynamic_for_field =
          build_op(true, schema_struct, field, %{filter | field: field})

        dynamic([r], ^dynamic and ^dynamic_for_field)
      end)

    dynamic([r], ^c and ^compound_dynamic)
  end

  defp build_op(
         c,
         _schema_struct,
         {:compound, _fields},
         %Filter{op: op, value: _value} = _filter
       )
       when op in [
              :==,
              :!=,
              :<=,
              :<,
              :>=,
              :>,
              :in,
              :not_in,
              :contains,
              :not_contains
            ] do
    # value = value |> String.split() |> Enum.join(" ")
    # filter = %{filter | value: value}
    # compare value with concatenated fields
    Logger.warn(
      "Flop: Operator '#{op}' not supported for compound fields. Ignored."
    )

    c
  end

  for op <- @operators do
    {fragment, prelude, combinator} = op_config(op)

    defp build_op(c, _schema_struct, {:normal, field}, %Filter{
           op: unquote(op),
           value: value
         }) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end

    defp build_op(
           c,
           _schema_struct,
           {:join, %{binding: binding, field: field}},
           %Filter{
             op: unquote(op),
             value: value
           }
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), true, unquote(combinator))
    end
  end

  defp get_field_type(nil, field), do: {:normal, field}

  defp get_field_type(struct, field) when is_atom(field) do
    Flop.Schema.field_type(struct, field)
  end
end
