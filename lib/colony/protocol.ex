defmodule Colony.Protocol do
  @moduledoc """
  The binary messages between the server and the clients.

  All numbers are little-endian. A message from the server is:

      tick: u32
      then zero or more sections: tag: u8, count: u16, then `count` records

  The records of each section:

      1  hello       width u16, rows u8, nest cell u16, seed u32, your id u16, tick rate u8,
                     speed * 10 u8, scent decay ticks u16, the time of the start u32,
                     bank support u8, the number of costs u8, then each cost u8,
                     the number of rivers u8, then for each river: its first row u8 and its
                     width in each column, u8
      2  names       player id u16, flags u8 (1 = helper), length u8, name
      3  worker set  worker id u16, cell u16, flags u8 (1 = carries food, 2 = new position)
      4  moves       u16: worker id * 8 + direction
      5  worker gone worker id u16
      6  locks       cell u16, kind u8 (1 = player, 2 = helper), player id u16, time u32,
                     the number of the lock in the story u16, length u8, name
      8  structure   cell u16, support u8. All the locked bodies.
      9  open        cell u16. All the open cells.
      10 scent       cell u16, value u8
      11 food        food at the nest u32, the river that the colony builds across u8,
                     flags u8 (1 = the world is complete)
      12 players     player id u16, x u16, z u16, heading u8, flags u8 (1 = carries food)
      13 piles       pile id u8, cell u16, units u16, units at the start u16,
                     flags u8 (1 = no body can walk to the pile). All the piles.

  A position is `(value + 1) * 500`. A heading is a part of a full turn times 256.
  The supports and the costs are integers: see `Colony.Support`.

  The snapshot (event "s") has all the state. A tick (event "t") has only the changes.
  A move from a client (event "m") is: x u16, z u16, heading u8.

  The records of the bridges are not binary: the event "record" has one record as JSON.
  """

  import Bitwise

  alias Colony.World

  @hello 1
  @names 2
  @worker_set 3
  @moves 4
  @worker_gone 5
  @locks 6
  @structure 8
  @open 9
  @scent 10
  @food 11
  @players 12
  @piles 13

  @doc "All the state, for a client that joins. `you` is the id of the player, or 0xFFFF."
  def snapshot(%World{} = world, you) do
    grid = world.grid
    p = world.p
    rule = world.rule
    costs = Tuple.to_list(rule.costs)

    hello = [
      <<grid.width::16-little, grid.rows::8, grid.nest::16-little, world.seed::32-little,
        you::16-little, p.rate::8, round(p.step * p.rate * 10)::8, p.decay_ticks::16-little,
        world.start || 0::32-little, rule.bank::8, length(costs)::8>>,
      for(cost <- costs, do: <<cost::8>>),
      <<tuple_size(grid.rivers)::8>>,
      for river <- Tuple.to_list(grid.rivers) do
        [<<river.start::8>>, for(width <- Tuple.to_list(river.widths), do: <<width::8>>)]
      end
    ]

    workers =
      for {id, worker} <- world.workers do
        <<id::16-little, worker.cell::16-little, carry_flag(worker) ||| 2::8>>
      end

    names =
      for {id, player} <- world.players, do: name_record(id, player.name, player.helper != nil)

    IO.iodata_to_binary([
      <<world.tick::32-little>>,
      section(@hello, [hello]),
      section(@names, names),
      section(@worker_set, workers),
      section(@locks, for({cell, body} <- world.locked, do: lock_record({cell, body, 0}))),
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
      section(
        @names,
        for({id, name, helper?} <- Enum.reverse(events.names), do: name_record(id, name, helper?))
      ),
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
      if(events.structure, do: structure(world), else: []),
      section(@scent, for({cell, value} <- events.scent, do: <<cell::16-little, value::8>>)),
      if(events.food, do: food(world), else: []),
      players(world)
    ])
  end

  @doc "A record of a bridge as a map for JSON."
  def record(record) do
    Map.take(record, [:id, :time, :seconds, :names, :bodies, :rows, :width, :left, :size, :first])
  end

  @doc "Reads a move from a client."
  def decode_move(<<x::16-little, z::16-little, heading::8>>) do
    {:ok, x / 500 - 1, z / 500 - 1, heading / 256 * 2 * :math.pi()}
  end

  def decode_move(_), do: :error

  @doc "Makes a move as a client does. The load test uses it."
  def encode_move(x, z, heading) do
    <<position(x)::16-little, position(z)::16-little, heading_byte(heading)::8>>
  end

  defp section(_tag, []), do: []
  defp section(tag, records), do: [<<tag::8, length(records)::16-little>> | records]

  defp structure(world) do
    bodies =
      for {cell, _} <- world.locked do
        <<cell::16-little, min(255, max(0, Map.get(world.supports, cell, 0)))::8>>
      end

    # A count of 0 is necessary here: it tells the client that no body is locked, or
    # that no cell is open.
    [
      <<@structure::8, length(bodies)::16-little>>,
      bodies,
      <<@open::8, MapSet.size(world.open)::16-little>>,
      for(cell <- world.open, do: <<cell::16-little>>)
    ]
  end

  defp food(world) do
    far = World.far_pile(world)

    piles =
      for {id, pile} <- world.piles do
        flags = if far != nil and far.id == id, do: 1, else: 0
        <<id::8, pile.cell::16-little, pile.units::16-little, pile.size::16-little, flags::8>>
      end

    [
      <<@food::8, 1::16-little, world.food_nest::32-little, world.stage::8,
        if(world.complete, do: 1, else: 0)::8>>,
      section(@piles, piles)
    ]
  end

  defp players(world) do
    records =
      for {id, player} <- world.players do
        <<id::16-little, position(player.x)::16-little, position(player.z)::16-little,
          heading_byte(player.heading)::8, if(player.carry, do: 1, else: 0)::8>>
      end

    section(@players, records)
  end

  defp name_record(id, name, helper?) do
    <<id::16-little, if(helper?, do: 1, else: 0)::8, byte_size(name)::8, name::binary>>
  end

  defp lock_record({cell, body, id}) do
    kind = if body.helper, do: 2, else: 1

    <<cell::16-little, kind::8, id::16-little, body.time::32-little, body.n::16-little,
      byte_size(body.name)::8, body.name::binary>>
  end

  defp carry_flag(%{carry: nil}), do: 0
  defp carry_flag(_), do: 1

  defp position(value), do: min(65_535, max(0, round((value + 1) * 500)))

  defp heading_byte(heading) do
    Integer.mod(round(heading / (2 * :math.pi()) * 256), 256)
  end
end
