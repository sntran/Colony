defmodule Colony.Grid do
  @moduledoc """
  The grid of hexagonal cells.

  A cell is an integer: `row * width + column`. Rows are parallel to the banks.
  Row 0 is on the near bank. The rows with an odd number are moved half a cell to the right.
  Thus each cell touches two cells in its row, two cells in the row before
  and two cells in the row after.

  The distance between the centers of two cells that touch is 1.

  The near bank has a straight edge. The river has a different width in each column,
  thus the edge of the far bank is not straight. `river` has the width for each column.
  """

  @row_step :math.sqrt(3) / 2

  defstruct [
    :width,
    :rows,
    :near_rows,
    :count,
    :nest,
    # The width of the river in each column, as a tuple.
    :river,
    # Tuples with one element for each cell.
    :kinds,
    :neighbors,
    :forward,
    :beside,
    :nest_distance
  ]

  @type cell :: non_neg_integer()
  @type t :: %__MODULE__{}

  @doc "The distance between two rows."
  def row_step, do: @row_step

  @doc "Makes the grid from the game config and the seed of the world."
  def new(cfg, seed) do
    width = Keyword.fetch!(cfg, :width)
    near = Keyword.fetch!(cfg, :near_rows)
    river = river(cfg, seed)
    rows = near + Keyword.fetch!(cfg, :river_max) + Keyword.fetch!(cfg, :far_rows)
    {nest_row, nest_col} = Keyword.fetch!(cfg, :nest)

    grid = %__MODULE__{
      width: width,
      rows: rows,
      near_rows: near,
      count: width * rows,
      nest: nest_row * width + nest_col,
      river: List.to_tuple(river)
    }

    cells = 0..(grid.count - 1)

    kinds =
      for cell <- cells do
        row = div(cell, width)

        cond do
          row < near -> :near
          row < near + elem(grid.river, rem(cell, width)) -> :gap
          true -> :far
        end
      end

    neighbors = for cell <- cells, do: calculate_neighbors(grid, cell)

    # The cell with the same column number is first. A way that always takes the first cell
    # is thus a straight line across the river.
    forward =
      for {cell, list} <- Enum.zip(cells, neighbors) do
        list
        |> Enum.filter(&(div(&1, width) == div(cell, width) + 1))
        |> Enum.sort_by(&abs(rem(&1, width) - rem(cell, width)))
      end

    beside =
      for {cell, list} <- Enum.zip(cells, neighbors) do
        Enum.filter(list, &(div(&1, width) == div(cell, width)))
      end

    grid = %{
      grid
      | kinds: List.to_tuple(kinds),
        neighbors: List.to_tuple(neighbors),
        forward: List.to_tuple(forward),
        beside: List.to_tuple(beside)
    }

    %{grid | nest_distance: List.to_tuple(for cell <- cells, do: distance(grid, cell, grid.nest))}
  end

  @doc """
  The width of the river in each column, from the seed.

  The narrowest place is `river_min` rows wide or one row more, near the nest. From there
  the river gets wider by one row for each column, up to a width that changes slowly along
  the river. Thus each width from the narrowest to the widest is somewhere.
  """
  def river(cfg, seed) do
    width = Keyword.fetch!(cfg, :width)
    low = Keyword.fetch!(cfg, :river_min)
    high = Keyword.fetch!(cfg, :river_max)

    if low == high do
      List.duplicate(high, width)
    else
      Enum.find_value(0..199, fn attempt ->
        try_river(cfg, :erlang.phash2({seed, attempt}), width, low, high)
      end) ||
        raise "cannot make a river for the seed #{seed}"
    end
  end

  defp try_river(cfg, seed, width, low, high) do
    {_nest_row, nest_col} = Keyword.fetch!(cfg, :nest)
    span = Keyword.fetch!(cfg, :river_narrow_columns)
    rng = :rand.seed_s(:exsss, seed)

    {[p1, p2, p3, pick, extra], _rng} =
      Enum.map_reduce(1..5, rng, fn _, r -> :rand.uniform_s(r) end)

    narrow = low + trunc(extra * 2)
    center = nest_col - span + trunc(pick * (2 * span + 1))

    # A slow wave along the river.
    wave =
      for col <- 0..(width - 1) do
        :math.sin(col * 0.19 + p1 * 6.283) + 0.6 * :math.sin(col * 0.43 + p2 * 6.283) +
          0.3 * :math.sin(col * 0.83 + p3 * 6.283)
      end

    {least, most} = Enum.min_max(wave)
    # Outside of the narrow place, the river is 3 rows wider than its minimum, or more.
    floor = low + 3

    widths =
      for {value, col} <- Enum.with_index(wave) do
        open = floor + (high - floor) * (value - least) / (most - least)
        valley = narrow + abs(col - center)
        round(min(open, valley)) |> max(low) |> min(high)
      end

    # The edge of the far bank has no step of more than 2 rows.
    smooth? =
      widths |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> abs(a - b) <= 2 end)

    needed = [narrow, high | Keyword.get(cfg, :pile_widths, [])]

    if smooth? and Enum.min(widths) == narrow and Enum.all?(needed, &(&1 in widths)) do
      widths
    end
  end

  def cell(%__MODULE__{width: width}, row, col), do: row * width + col
  def row(%__MODULE__{width: width}, cell), do: div(cell, width)
  def col(%__MODULE__{width: width}, cell), do: rem(cell, width)

  @doc "The kind of a cell: `:near`, `:gap` or `:far`."
  def kind(%__MODULE__{kinds: kinds}, cell), do: elem(kinds, cell)

  @doc "The width of the river in a column."
  def river_width(%__MODULE__{river: river}, col), do: elem(river, col)

  @doc "The row of a river cell, from 1 at the near bank."
  def river_row(%__MODULE__{width: width, near_rows: near}, cell), do: div(cell, width) - near + 1

  @doc "The cells that touch a cell."
  def neighbors(%__MODULE__{neighbors: neighbors}, cell), do: elem(neighbors, cell)

  @doc """
  The cells that touch a cell and are in the next row, in the direction of the far bank.
  The cell with the same column number is first.
  """
  def forward(%__MODULE__{forward: forward}, cell), do: elem(forward, cell)

  @doc "The cells that touch a cell and are in the same row."
  def beside(%__MODULE__{beside: beside}, cell), do: elem(beside, cell)

  @doc "The number of cells from a cell to the nest. The river is not an obstacle for this number."
  def nest_distance(%__MODULE__{nest_distance: distances}, cell), do: elem(distances, cell)

  @doc "True if a river cell touches a bank cell."
  def touches_bank?(grid, cell) do
    Enum.any?(neighbors(grid, cell), &(kind(grid, &1) != :gap))
  end

  @doc "The last row of the near bank."
  def near_edge_row(%__MODULE__{near_rows: near}), do: near - 1

  @doc "The center of a cell as `{x, z}`."
  def center(%__MODULE__{width: width}, cell) do
    row = div(cell, width)
    {rem(cell, width) + 0.5 * rem(row, 2), row * @row_step}
  end

  @doc "The cell that contains the point `{x, z}`, or nil if the point is not on the grid."
  def cell_at(%__MODULE__{width: width, rows: rows}, x, z) do
    r = z / @row_step
    q = x - r / 2
    s = -q - r
    rq = round(q)
    rr = round(r)
    rs = round(s)
    dq = abs(rq - q)
    dr = abs(rr - r)
    ds = abs(rs - s)

    {q, r} =
      cond do
        dq > dr and dq > ds -> {-rr - rs, rr}
        dr > ds -> {rq, -rq - rs}
        true -> {rq, rr}
      end

    col = q + div(r - Integer.mod(r, 2), 2)

    if r >= 0 and r < rows and col >= 0 and col < width do
      r * width + col
    else
      nil
    end
  end

  @doc "The number of cells from cell `a` to cell `b`."
  def distance(grid, a, b) do
    {aq, ar} = axial(grid, a)
    {bq, br} = axial(grid, b)
    dq = aq - bq
    dr = ar - br
    max(abs(dq), max(abs(dr), abs(dq + dr)))
  end

  @doc """
  The direction from a cell to a cell that touches it, as a number from 0 to 5.

  0 and 1 are the cells in the same row (right, left). 2 and 3 are the cells in the next row
  (right, left). 4 and 5 are the cells in the row before (right, left).
  """
  def direction(%__MODULE__{width: width}, from, to) do
    row = div(from, width)
    d_row = div(to, width) - row
    d_col = rem(to, width) - rem(from, width)
    right? = if rem(row, 2) == 0, do: d_col == 0, else: d_col == 1

    case d_row do
      0 -> if d_col == 1, do: 0, else: 1
      1 -> if right?, do: 2, else: 3
      -1 -> if right?, do: 4, else: 5
    end
  end

  defp axial(%__MODULE__{width: width}, cell) do
    row = div(cell, width)
    {rem(cell, width) - div(row - rem(row, 2), 2), row}
  end

  defp calculate_neighbors(%__MODULE__{width: width, rows: rows}, cell) do
    row = div(cell, width)
    col = rem(cell, width)
    shift = rem(row, 2)

    [
      {row, col + 1},
      {row, col - 1},
      {row + 1, col + shift},
      {row + 1, col + shift - 1},
      {row - 1, col + shift},
      {row - 1, col + shift - 1}
    ]
    |> Enum.filter(fn {r, c} -> r >= 0 and r < rows and c >= 0 and c < width end)
    |> Enum.map(fn {r, c} -> r * width + c end)
  end
end
