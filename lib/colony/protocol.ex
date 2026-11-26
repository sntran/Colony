defmodule Colony.Protocol do
  @moduledoc """
  The binary messages between the server and the clients.

  All numbers are little-endian. A message from the server is:

      tick: u32
      then zero or more sections: tag: u8, count: u16, then `count` records

  The records of each section:

      1  hello       width u16, near rows u8, gap rows u8, far rows u8, nest cell u16,
                     food cell u16, seed u32, your id u16, tick rate u8, speed * 10 u8,
                     scent decay ticks u16, food units u16
      2  names       player id u16, length u8, name
      3  worker set  worker id u16, cell u16, flags u8 (1 = carries food, 2 = new position)
      4  moves       u16: worker id * 8 + direction
      5  worker gone worker id u16
      6  locks       cell u16, kind u8 (0 = worker, 1 = player), body id u16, time u32,
                     length u8, name
      7  fell        cell u16
      8  structure   cell u16, support * 2 u8. All the locked bodies.
      9  frontier    cell u16. All the cells where a lock is possible.
      10 scent       cell u16, value u8
      11 food        pile u16, nest u32
      12 players     player id u16, x u16, z u16, heading u8, flags u8 (1 = puts scent)

  A position is `(value + 1) * 1000`. A heading is a part of a full turn times 256.

  The snapshot (event "s") has all the state. A tick (event "t") has only the changes.
  A move from a client (event "m") is: x u16, z u16, heading u8, flags u8.
  """

  import Bitwise

  alias Colony.World

  @hello 1
  @names 2
  @worker_set 3
  @moves 4
  @worker_gone 5
  @locks 6
  @fell 7
  @structure 8
  @frontier 9
  @scent 10
  @food 11
  @players 12

  @doc "All the state, for a client that joins. `you` is the id of the player, or 0xFFFF."
  def snapshot(%World{} = world, you) do
    grid = world.grid
    p = world.p

    hello =
      <<grid.width::16-little, grid.near_rows::8, grid.gap_rows::8, grid.far_rows::8,
        grid.nest::16-little, grid.food::16-little, world.seed::32-little, you::16-little,
        p.rate::8, round(p.step * p.rate * 10)::8, p.decay_ticks::16-little,
        p.food_units::16-little>>

    workers =
      for {id, worker} <- world.workers do
        <<id::16-little, worker.cell::16-little, carry_flag(worker) ||| 2::8>>
      end

    IO.iodata_to_binary([
      <<world.tick::32-little>>,
      section(@hello, [hello]),
      section(@names, for({id, player} <- world.players, do: name_record(id, player.name))),
      section(@worker_set, workers),
      section(@locks, Enum.map(world.locked, &lock_record/1)),
      structure(world),
      section(@scent, for({cell, value} <- world.scent, do: <<cell::16-little, value::8>>)),
      food(world),
      players(world)
    ])
  end

  @doc "The changes of one tick."
  def tick(%World{} = world, events) do
    IO.iodata_to_binary([
      <<world.tick::32-little>>,
      section(@names, for({id, name} <- Enum.reverse(events.names), do: name_record(id, name))),
      section(
        @worker_set,
        for {id, cell, flags} <- Enum.reverse(events.worker_set) do
          <<id::16-little, cell::16-little, flags::8>>
        end
      ),
      section(
        @moves,
        for({id, direction} <- events.moves, do: <<id <<< 3 ||| direction::16-little>>)
      ),
      section(@worker_gone, for(id <- events.worker_gone, do: <<id::16-little>>)),
      section(@locks, events.locks |> Enum.reverse() |> Enum.map(&lock_record/1)),
      section(@fell, for(cell <- events.fell, do: <<cell::16-little>>)),
      if(events.structure, do: structure(world), else: []),
      section(@scent, for({cell, value} <- events.scent, do: <<cell::16-little, value::8>>)),
      if(events.food, do: food(world), else: []),
      players(world)
    ])
  end

  @doc "Reads a move from a client."
  def decode_move(<<x::16-little, z::16-little, heading::8, flags::8>>) do
    {:ok, x / 1000 - 1, z / 1000 - 1, heading / 256 * 2 * :math.pi(), (flags &&& 1) == 1}
  end

  def decode_move(_), do: :error

  @doc "Makes a move as a client does. The load test uses it."
  def encode_move(x, z, heading, scent?) do
    <<position(x)::16-little, position(z)::16-little, heading_byte(heading)::8,
      if(scent?, do: 1, else: 0)::8>>
  end

  defp section(_tag, []), do: []
  defp section(tag, records), do: [<<tag::8, length(records)::16-little>> | records]

  defp structure(world) do
    bodies =
      for {cell, _} <- world.locked do
        support = Map.get(world.supports, cell, 0.0)
        <<cell::16-little, min(255, max(0, round(support * 2)))::8>>
      end

    # A count of 0 is necessary here: it tells the client that no body is locked.
    [
      <<@structure::8, length(bodies)::16-little>>,
      bodies,
      <<@frontier::8, length(world.frontier)::16-little>>,
      for(cell <- world.frontier, do: <<cell::16-little>>)
    ]
  end

  defp food(world) do
    <<@food::8, 1::16-little, world.food_pile::16-little, world.food_nest::32-little>>
  end

  defp players(world) do
    records =
      for {id, %{state: :alive} = player} <- world.players do
        <<id::16-little, position(player.x)::16-little, position(player.z)::16-little,
          heading_byte(player.heading)::8, if(player.scent, do: 1, else: 0)::8>>
      end

    section(@players, records)
  end

  defp name_record(id, name), do: <<id::16-little, byte_size(name)::8, name::binary>>

  defp lock_record({cell, body}) do
    kind = if body.kind == :player, do: 1, else: 0

    <<cell::16-little, kind::8, body.id::16-little, body.time::32-little, byte_size(body.name)::8,
      body.name::binary>>
  end

  defp carry_flag(%{carry: true}), do: 1
  defp carry_flag(_), do: 0

  defp position(value), do: min(65_535, max(0, round((value + 1) * 1000)))

  defp heading_byte(heading) do
    Integer.mod(round(heading / (2 * :math.pi()) * 256), 256)
  end
end
