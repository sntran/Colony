defmodule Colony.Guide do
  @moduledoc """
  The guide: the one target that a player gets at each moment. The page has the same rules
  in `priv/static/js/guide.js`. The helpers obey the guide.

  The first rule that applies gives the target:

  1. The player carries food: the nest, if the player can walk to it.
  2. The colony has a spare body, and an open cell is there: the nearest open cell, by
     steps on foot.
  3. A pile with food that the player can walk to is there: the nearest such pile.
  4. Nothing: no target.

  **Share the work.** If the colony has fewer spare bodies than players and helpers, and
  the last act of the player was a lock, rule 3 comes before rule 2. After the player
  brings food, rule 2 comes first again.
  """

  alias Colony.{Grid, World}

  @doc """
  The target of a player: `{:nest, cell}`, `{:open, cell, stand, path}`, `{:pile, id, cell}`
  or nil. For an open cell, `stand` is the cell where the body stands to lock, and `path`
  is the way on foot to it, without the cell of the body.
  """
  def target(%World{} = world, player) do
    if player.carry != nil do
      if is_map_key(world.walk, player.cell), do: {:nest, world.nest}
    else
      Enum.find_value(order(world, player), fn
        :open -> open_target(world, player)
        :pile -> pile_target(world, player.cell)
      end)
    end
  end

  @doc "The order of rules 2 and 3 for a player: share the work."
  def order(world, player) do
    if share?(world, player), do: [:pile, :open], else: [:open, :pile]
  end

  @doc "True if rule 3 comes before rule 2 for the player."
  def share?(world, player) do
    player.last == :lock and World.spare(world) < map_size(world.players)
  end

  # The nearest open cell by steps on foot. Of the open cells with the same number of
  # steps, the cell nearest to the body in a straight line, then the lowest cell number.
  defp open_target(world, player) do
    if World.spare(world) > 0 and world.open != %{} do
      search(world, {player.x, player.z}, [player.cell], %{player.cell => nil})
    end
  end

  defp search(_world, _at, [], _before), do: nil

  defp search(world, {x, z} = at, front, before) do
    grid = world.grid

    pairs =
      for cell <- front,
          open <- Grid.neighbors(grid, cell),
          World.open?(world, open) do
        {ox, oz} = Grid.center(grid, open)
        {:math.sqrt((ox - x) ** 2 + (oz - z) ** 2), open, cell}
      end

    if pairs != [] do
      {_distance, open, stand} = Enum.min(pairs)
      {:open, open, stand, trace(before, stand, [])}
    else
      {next, before} =
        Enum.reduce(front, {[], before}, fn cell, acc ->
          Enum.reduce(Grid.neighbors(world.grid, cell), acc, fn to, {next, before} = acc ->
            if is_map_key(before, to) or not World.walkable?(world, to),
              do: acc,
              else: {[to | next], Map.put(before, to, cell)}
          end)
        end)

      search(world, at, next, before)
    end
  end

  defp trace(before, cell, path) do
    case Map.fetch!(before, cell) do
      nil -> path
      previous -> trace(before, previous, [cell | path])
    end
  end

  # The nearest pile with food that the player can walk to.
  defp pile_target(world, from) do
    world.to_pile
    |> Enum.flat_map(fn {id, way} ->
      case Map.get(way, from) do
        nil ->
          []

        steps ->
          pile = Map.fetch!(world.piles, id)
          if pile.units > 0 and pile.crossed != nil, do: [{steps, id}], else: []
      end
    end)
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      {_steps, id} -> {:pile, id, Map.fetch!(world.piles, id).cell}
    end
  end
end
