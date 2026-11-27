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
            person: 0,
            decay_ticks: 10,
            rule: nil,
            rivers: [],
            start: 0,
            workers: %{},
            structure: %{},
            open: %{},
            locks: %{},
            scent: %{},
            food: nil,
            piles: %{},
            nest: nil,
            old_nests: [],
            players: %{},
            names: %{},
            people: %{}

  @doc "Starts from a snapshot."
  def new(grid, <<tick::32-little, rest::binary>>) do
    sections(%__MODULE__{grid: grid, tick: tick}, rest)
  end

  @doc "Applies the changes of one tick."
  def apply_tick(%__MODULE__{} = mirror, <<tick::32-little, rest::binary>>) do
    mirror = %{mirror | tick: tick, players: %{}}

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

  # The open cells are a full list: the old values go away.
  defp start(mirror, 9), do: %{mirror | open: %{}}
  defp start(mirror, _tag), do: mirror

  defp records(mirror, _tag, 0, rest), do: {mirror, rest}

  defp records(mirror, tag, count, rest) do
    {mirror, rest} = record(mirror, tag, rest)
    records(mirror, tag, count - 1, rest)
  end

  defp record(
         mirror,
         1,
         <<width::16-little, _rows::16-little, _seed::32, you::16-little, person::16-little,
           _rate::8, _speed::8, decay::16-little, start::32-little, bank::8, n::8,
           costs::binary-size(n), count::16-little, rest::binary>>
       ) do
    rule = %{bank: bank, costs: :binary.bin_to_list(costs)}

    {rivers, rest} =
      Enum.map_reduce(1..count//1, rest, fn _,
                                            <<first::16-little, widths::binary-size(^width),
                                              rest::binary>> ->
        {%{start: first, widths: :binary.bin_to_list(widths)}, rest}
      end)

    mirror = %{
      mirror
      | you: you,
        person: person,
        decay_ticks: decay,
        rule: rule,
        rivers: rivers,
        start: start
    }

    {mirror, rest}
  end

  defp record(
         mirror,
         2,
         <<id::16-little, flags::8, size::8, name::binary-size(size), rest::binary>>
       ) do
    {%{mirror | names: Map.put(mirror.names, id, {name, flags == 1})}, rest}
  end

  defp record(mirror, 3, <<id::16-little, cell::32-little, flags::8, rest::binary>>) do
    worker = %{
      cell: cell,
      carry: carry(flags),
      kind: if((flags &&& 8) != 0, do: :carrier, else: :spare)
    }

    {%{mirror | workers: Map.put(mirror.workers, id, worker)}, rest}
  end

  defp record(mirror, 4, <<value::16-little, rest::binary>>) do
    id = value >>> 3
    direction = value &&& 7
    worker = Map.fetch!(mirror.workers, id)

    to =
      Enum.find(
        Grid.neighbors(mirror.grid, worker.cell),
        &(Grid.direction(mirror.grid, worker.cell, &1) == direction)
      )

    {%{mirror | workers: Map.put(mirror.workers, id, %{worker | cell: to})}, rest}
  end

  defp record(mirror, 5, <<id::16-little, rest::binary>>) do
    {%{mirror | workers: Map.delete(mirror.workers, id)}, rest}
  end

  defp record(
         mirror,
         6,
         <<cell::32-little, kind::8, id::16-little, owner::16-little, time::32-little, n::32-little,
           size::8, name::binary-size(size), rest::binary>>
       ) do
    lock = %{kind: kind, id: id, owner: owner, time: time, n: n, name: name}
    {%{mirror | locks: Map.put(mirror.locks, cell, lock)}, rest}
  end

  defp record(mirror, 7, <<person::16-little, size::8, name::binary-size(size), rest::binary>>) do
    locks =
      Map.new(mirror.locks, fn
        {cell, %{owner: ^person, kind: 1} = lock} -> {cell, %{lock | name: name}}
        entry -> entry
      end)

    {%{mirror | people: Map.put(mirror.people, person, name), locks: locks}, rest}
  end

  defp record(mirror, 8, <<cell::32-little, support::8, rest::binary>>) do
    {%{mirror | structure: Map.put(mirror.structure, cell, support)}, rest}
  end

  defp record(mirror, 9, <<cell::32-little, gain::8, rest::binary>>) do
    {%{mirror | open: Map.put(mirror.open, cell, gain)}, rest}
  end

  defp record(mirror, 10, <<cell::32-little, value::8, rest::binary>>) do
    {%{mirror | scent: Map.put(mirror.scent, cell, value)}, rest}
  end

  defp record(mirror, 11, <<nest::32-little, stage::16-little, flags::8, rest::binary>>) do
    {%{mirror | food: %{nest: nest, stage: stage, complete: flags == 1}}, rest}
  end

  defp record(
         mirror,
         12,
         <<id::16-little, x::16-little, z::32-little, heading::8, flags::8, rest::binary>>
       ) do
    player = %{x: x / 500 - 1, z: z / 500 - 1, heading: heading, carry: flags == 1}
    {%{mirror | players: Map.put(mirror.players, id, player)}, rest}
  end

  defp record(
         mirror,
         13,
         <<id::16-little, cell::32-little, units::16-little, size::16-little, least::16-little,
           flags::8, rest::binary>>
       ) do
    pile = %{cell: cell, units: units, size: size, least: least, far: flags == 1}
    {%{mirror | piles: Map.put(mirror.piles, id, pile)}, rest}
  end

  defp record(mirror, 14, <<nest::32-little, count::16-little, rest::binary>>) do
    {old, rest} =
      Enum.map_reduce(1..count//1, rest, fn _, <<cell::32-little, land::16-little, rest::binary>> ->
        {%{cell: cell, land: land}, rest}
      end)

    {%{mirror | nest: nest, old_nests: old}, rest}
  end

  defp carry(flags) do
    cond do
      (flags &&& 1) != 0 -> :food
      (flags &&& 4) != 0 -> :egg
      true -> nil
    end
  end
end
