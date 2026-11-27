defmodule Colony.Protocol do
  @moduledoc """
  The binary messages between the server and the clients.

  All numbers are little-endian. A message from the server is:

      tick: u32
      then zero or more sections: tag: u8, count: u16, then `count` records

  The records of each section:

      1  hello       width u16, rows u16, seed u32, your id u16, your person u16, tick rate u8,
                     speed * 10 u8, scent decay ticks u16, the time of the start u32,
                     bank support u8, the number of costs u8, then each cost u8,
                     the number of rivers u16, then for each river: its first row u16 and
                     its width in each column, u8
      2  names       player id u16, flags u8 (1 = helper), length u8, name
      3  worker set  worker id u16, cell u32, flags u8 (1 = carries food, 2 = new position,
                     4 = carries an egg, 8 = carrier)
      4  moves       u16: worker id * 8 + direction
      5  worker gone worker id u16
      6  locks       cell u32, kind u8 (1 = player, 2 = helper), player id u16, owner u16,
                     time u32, the number of the lock in the story u32, length u8, name
      7  people      person u16, length u8, name. A person has a new name.
      8  structure   cell u32, support u8. In the snapshot: all the locked bodies. In a tick:
                     the locked bodies whose support changed.
      9  open        cell u32, gain u8. All the open cells.
      10 scent       cell u32, value u8
      11 food        food at the nest u32, the river that the colony builds across u16,
                     flags u8 (1 = the world is complete)
      12 players     player id u16, x u16, z u32, heading u8, flags u8 (1 = carries food)
      13 piles       pile id u16, cell u32, units u16, units at the start u16,
                     least units u16, flags u8 (1 = no body can walk to the pile).
                     In the snapshot: all the piles. In a tick: the piles that changed.
      14 nest        the cell of the nest u32, the number of old nests u16, then for each
                     old nest: cell u32, land u16

  A position is `(value + 1) * 500`. A heading is a part of a full turn times 256.
  The supports and the costs are integers: see `Colony.Support`. An owner is the number of
  a person, or 0 for a helper.

  The snapshot (event "s") has all the state. A tick (event "t") has only the changes.
  A move from a client (event "m") is: x u16, z u32, heading u8.

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
  @people 7
  @structure 8
  @open 9
  @scent 10
  @food 11
  @players 12
  @piles 13
  @nest 14

  @doc "All the state, for a client that joins. `you` is the id of the player, or 0xFFFF."
  def snapshot(%World{} = world, you) do
    grid = world.grid
    p = world.p
    rule = world.rule
    costs = Tuple.to_list(rule.costs)

    person =
      case Map.get(world.players, you) do
        %{person: person} when person != nil -> person
        _ -> 0
      end

    hello = [
      <<grid.width::16-little, grid.rows::16-little, world.seed::32-little, you::16-little,
        person::16-little, p.rate::8, round(p.step * p.rate * 10)::8, p.decay_ticks::16-little,
        world.start || 0::32-little, rule.bank::8, length(costs)::8>>,
      for(cost <- costs, do: <<cost::8>>),
      <<tuple_size(grid.rivers)::16-little>>,
      for river <- Tuple.to_list(grid.rivers) do
        [<<river.start::16-little>>, for(width <- Tuple.to_list(river.widths), do: <<width::8>>)]
      end
    ]

    workers =
      for {id, worker} <- world.workers do
        <<id::16-little, worker.cell::32-little, World.flags(worker) ||| 2::8>>
      end

    names =
      for {id, player} <- world.players, do: name_record(id, player.name, player.helper != nil)

    IO.iodata_to_binary([
      <<world.tick::32-little>>,
      section(@hello, [hello]),
      section(@names, names),
      section(@worker_set, workers),
      section(@locks, for({cell, body} <- world.locked, do: lock_record({cell, body, 0}))),
      structure(world, Map.keys(world.locked), true),
      open(world),
      section(@scent, for({cell, value} <- world.scent, do: <<cell::32-little, value::8>>)),
      food(world),
      piles(world, Map.keys(world.piles)),
      nest(world),
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
        @people,
        for {person, name} <- Enum.reverse(events.people) do
          <<person::16-little, byte_size(name)::8, name::binary>>
        end
      ),
      section(
        @worker_set,
        for {id, cell, flags} <- Enum.reverse(events.worker_set) do
          <<id::16-little, cell::32-little, flags::8>>
        end
      ),
      section(
        @moves,
        for({id, direction} <- events.moves, do: <<id <<< 3 ||| direction::16-little>>)
      ),
      section(@worker_gone, for(id <- events.worker_gone, do: <<id::16-little>>)),
      section(@locks, events.locks |> Enum.reverse() |> Enum.map(&lock_record/1)),
      if(events.structure != [],
        do: structure(world, Enum.uniq(events.structure), false),
        else: []
      ),
      if(events.open, do: open(world), else: []),
      section(@scent, for({cell, value} <- events.scent, do: <<cell::32-little, value::8>>)),
      if(events.food, do: food(world), else: []),
      if(events.piles != [], do: piles(world, Enum.uniq(events.piles)), else: []),
      if(events.nest, do: nest(world), else: []),
      players(world)
    ])
  end

  @doc "A record of a bridge as a map for JSON."
  def record(record) do
    Map.take(record, [
      :id,
      :time,
      :seconds,
      :names,
      :bodies,
      :best,
      :rows,
      :width,
      :left,
      :size,
      :first
    ])
  end

  @doc "Reads a move from a client."
  def decode_move(<<x::16-little, z::32-little, heading::8>>) do
    {:ok, x / 500 - 1, z / 500 - 1, heading / 256 * 2 * :math.pi()}
  end

  def decode_move(_), do: :error

  @doc "Makes a move as a client does. The load test uses it."
  def encode_move(x, z, heading) do
    <<position(x, 0xFFFF)::16-little, position(z, 0xFFFFFFFF)::32-little, heading_byte(heading)::8>>
  end

  defp section(_tag, []), do: []
  defp section(tag, records), do: [<<tag::8, length(records)::16-little>> | records]

  # A count of 0 is necessary in the snapshot: it tells the client that no body is locked.
  defp structure(world, cells, always) do
    bodies =
      for cell <- cells do
        <<cell::32-little, min(255, max(0, Map.get(world.supports, cell, 0)))::8>>
      end

    if bodies == [] and not always,
      do: [],
      else: [<<@structure::8, length(bodies)::16-little>>, bodies]
  end

  # A count of 0 is necessary here: it tells the client that no cell is open.
  defp open(world) do
    cells = for {cell, gain} <- world.open, do: <<cell::32-little, min(255, gain)::8>>
    [<<@open::8, length(cells)::16-little>>, cells]
  end

  defp food(world) do
    <<@food::8, 1::16-little, world.food_nest::32-little, world.stage::16-little,
      if(world.complete, do: 1, else: 0)::8>>
  end

  defp piles(world, ids) do
    far = World.far_pile(world)

    records =
      for id <- ids, pile = Map.get(world.piles, id), pile != nil do
        flags = if far != nil and far.id == id, do: 1, else: 0

        <<id::16-little, pile.cell::32-little, pile.units::16-little, pile.size::16-little,
          pile.least::16-little, flags::8>>
      end

    section(@piles, records)
  end

  defp nest(world) do
    old = for nest <- world.old_nests, do: <<nest.cell::32-little, nest.land::16-little>>

    [
      <<@nest::8, 1::16-little, world.nest::32-little, length(old)::16-little>>,
      old
    ]
  end

  defp players(world) do
    records =
      for {id, player} <- world.players do
        <<id::16-little, position(player.x, 0xFFFF)::16-little,
          position(player.z, 0xFFFFFFFF)::32-little, heading_byte(player.heading)::8,
          if(player.carry, do: 1, else: 0)::8>>
      end

    section(@players, records)
  end

  defp name_record(id, name, helper?) do
    <<id::16-little, if(helper?, do: 1, else: 0)::8, byte_size(name)::8, name::binary>>
  end

  defp lock_record({cell, body, id}) do
    kind = if body.helper, do: 2, else: 1

    <<cell::32-little, kind::8, id::16-little, body.owner || 0::16-little, body.time::32-little,
      body.n::32-little, byte_size(body.name)::8, body.name::binary>>
  end

  defp position(value, most), do: min(most, max(0, round((value + 1) * 500)))

  defp heading_byte(heading) do
    Integer.mod(round(heading / (2 * :math.pi()) * 256), 256)
  end
end
