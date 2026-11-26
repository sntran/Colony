defmodule Colony.Mirror do
  @moduledoc """
  A client without a screen, for the tests.

  It reads the binary messages and keeps the same state that the page keeps. A test then
  compares this state with the world. If they are different, the protocol has a fault.
  """

  import Bitwise

  alias Colony.Grid

  defstruct grid: nil,
            tick: 0,
            you: nil,
            decay_ticks: 10,
            workers: %{},
            structure: %{},
            frontier: [],
            locks: %{},
            scent: %{},
            food: nil,
            players: %{},
            names: %{},
            fell: []

  @doc "Starts from a snapshot."
  def new(grid, <<tick::32-little, rest::binary>>) do
    sections(%__MODULE__{grid: grid, tick: tick}, rest)
  end

  @doc "Applies the changes of one tick."
  def apply_tick(%__MODULE__{} = mirror, <<tick::32-little, rest::binary>>) do
    mirror = %{mirror | tick: tick, players: %{}, fell: []}

    mirror =
      if rem(tick, mirror.decay_ticks) == 0 do
        scent = for {cell, value} <- mirror.scent, value > 1, into: %{}, do: {cell, value - 1}
        %{mirror | scent: scent}
      else
        mirror
      end

    sections(mirror, rest)
  end

  defp sections(mirror, <<>>), do: mirror

  defp sections(mirror, <<tag::8, count::16-little, rest::binary>>) do
    {mirror, rest} = records(start(mirror, tag), tag, count, rest)
    sections(mirror, rest)
  end

  # The structure and the frontier are full lists: the old values go away.
  defp start(mirror, 8), do: %{mirror | structure: %{}}
  defp start(mirror, 9), do: %{mirror | frontier: []}
  defp start(mirror, _tag), do: mirror

  defp records(mirror, _tag, 0, rest), do: {mirror, rest}

  defp records(mirror, tag, count, rest) do
    {mirror, rest} = record(mirror, tag, rest)
    records(mirror, tag, count - 1, rest)
  end

  defp record(mirror, 1, <<_width::16, _rows::24, _nest::16, _food::16, _seed::32, you::16-little, _rate::8, _speed::8, decay::16-little, _units::16, rest::binary>>) do
    {%{mirror | you: you, decay_ticks: decay}, rest}
  end

  defp record(mirror, 2, <<id::16-little, size::8, name::binary-size(size), rest::binary>>) do
    {%{mirror | names: Map.put(mirror.names, id, name)}, rest}
  end

  defp record(mirror, 3, <<id::16-little, cell::16-little, flags::8, rest::binary>>) do
    {%{mirror | workers: Map.put(mirror.workers, id, {cell, flags &&& 1})}, rest}
  end

  defp record(mirror, 4, <<value::16-little, rest::binary>>) do
    id = value >>> 3
    direction = value &&& 7
    {cell, carry} = Map.fetch!(mirror.workers, id)
    to = Enum.find(Grid.neighbors(mirror.grid, cell), &(Grid.direction(mirror.grid, cell, &1) == direction))
    {%{mirror | workers: Map.put(mirror.workers, id, {to, carry})}, rest}
  end

  defp record(mirror, 5, <<id::16-little, rest::binary>>) do
    {%{mirror | workers: Map.delete(mirror.workers, id)}, rest}
  end

  defp record(mirror, 6, <<cell::16-little, kind::8, id::16-little, time::32-little, size::8, name::binary-size(size), rest::binary>>) do
    {%{mirror | locks: Map.put(mirror.locks, cell, %{kind: kind, id: id, time: time, name: name})}, rest}
  end

  defp record(mirror, 7, <<cell::16-little, rest::binary>>) do
    {%{mirror | fell: [cell | mirror.fell]}, rest}
  end

  defp record(mirror, 8, <<cell::16-little, support::8, rest::binary>>) do
    {%{mirror | structure: Map.put(mirror.structure, cell, support / 2)}, rest}
  end

  defp record(mirror, 9, <<cell::16-little, rest::binary>>) do
    {%{mirror | frontier: [cell | mirror.frontier]}, rest}
  end

  defp record(mirror, 10, <<cell::16-little, value::8, rest::binary>>) do
    {%{mirror | scent: Map.put(mirror.scent, cell, value)}, rest}
  end

  defp record(mirror, 11, <<pile::16-little, nest::32-little, rest::binary>>) do
    {%{mirror | food: {pile, nest}}, rest}
  end

  defp record(mirror, 12, <<id::16-little, x::16-little, z::16-little, heading::8, flags::8, rest::binary>>) do
    player = %{x: x / 1000 - 1, z: z / 1000 - 1, heading: heading, scent: flags == 1}
    {%{mirror | players: Map.put(mirror.players, id, player)}, rest}
  end
end
