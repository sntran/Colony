defmodule Colony.Grid do
  @moduledoc """
  The grid of hexagonal cells.

  A cell is an integer: `row * width + column`. Rows go from the south to the north.
  Row 0 is the south edge of land 0. The rows with an odd number are moved half a cell to
  the right. Thus each cell touches two cells in its row, two cells in the row before and
  two cells in the row after.

  The distance between the centers of two cells that touch is 1.

  The world goes north from the nest: land 0, river 1, land 1, river 2, and so on. Each
  river goes across the full width of the grid. The south edge of a river is a straight
  line of cells. The river has a different width in each column, thus its north edge is
  not straight.
  """

  @row_step :math.sqrt(3) / 2

  defstruct [
    :width,
    :rows,
    :count,
    :nest,
    # One map for each river, as a tuple: %{start: the first row, widths: a tuple with the
    # width in each column, max: the largest width}.
    :rivers,
    # Tuples with one element for each cell.
    # 0 for a land cell, `k` for a cell of river `k`.
    :kinds,
    # The number of the land of a land cell. For a river cell: the number of its river.
    :lands,
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
    land_rows = Keyword.fetch!(cfg, :land_rows)
    {nest_row, nest_col} = Keyword.fetch!(cfg, :nest)

    # Each land after a river is `land_rows` deep at the widest place of the river.
    {rivers, rows} =
      cfg
      |> rivers(seed)
      |> Enum.map_reduce(near, fn widths, start ->
        most = Enum.max(widths)
        {%{start: start, widths: List.to_tuple(widths), max: most}, start + most + land_rows}
      end)

    grid = %__MODULE__{
      width: width,
      rows: rows,
      count: width * rows,
      nest: nest_row * width + nest_col,
      rivers: List.to_tuple(rivers)
    }

    cells = 0..(grid.count - 1)

    zones =
      for cell <- cells do
        row = div(cell, width)
        col = rem(cell, width)

        rivers
        |> Enum.with_index(1)
        |> Enum.reduce({0, 0}, fn {river, k}, zone ->
          cond do
            row < river.start -> zone
            row < river.start + elem(river.widths, col) -> {k, k}
            true -> {0, k}
          end
        end)
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
      | kinds: zones |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
        lands: zones |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
        neighbors: List.to_tuple(neighbors),
        forward: List.to_tuple(forward),
        beside: List.to_tuple(beside)
    }

    %{grid | nest_distance: List.to_tuple(for cell <- cells, do: distance(grid, cell, grid.nest))}
  end

  @doc """
  The width of each river in each column, from the seed: a list with one list for each river.

  The config `rivers` has `{least, most}` for each river. The width changes slowly along a
  river, by 1 row or less from one column to the next. Each river has a place with its
  least width and a place with its largest width.
  """
  def rivers(cfg, seed) do
    width = Keyword.fetch!(cfg, :width)

    for {{low, high}, k} <- Enum.with_index(Keyword.fetch!(cfg, :rivers), 1) do
      if low == high do
        List.duplicate(high, width)
      else
        Enum.find_value(0..199, fn attempt ->
          try_river(:erlang.phash2({seed, k, attempt}), width, low, high)
        end) || raise "cannot make river #{k} for the seed #{seed}"
      end
    end
  end

  defp try_river(seed, width, low, high) do
    rng = :rand.seed_s(:exsss, seed)
    {[p1, p2, p3], _rng} = Enum.map_reduce(1..3, rng, fn _, r -> :rand.uniform_s(r) end)

    # A slow wave along the river.
    wave =
      for col <- 0..(width - 1) do
        :math.sin(col * 0.17 + p1 * 6.283) + 0.5 * :math.sin(col * 0.37 + p2 * 6.283) +
          0.2 * :math.sin(col * 0.71 + p3 * 6.283)
      end

    {least, most} = Enum.min_max(wave)

    widths =
      for value <- wave do
        round(low + (high - low) * (value - least) / (most - least))
      end

    smooth? =
      widths |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> abs(a - b) <= 1 end)

    if smooth? and low in widths and high in widths, do: widths
  end

  def cell(%__MODULE__{width: width}, row, col), do: row * width + col
  def row(%__MODULE__{width: width}, cell), do: div(cell, width)
  def col(%__MODULE__{width: width}, cell), do: rem(cell, width)

  @doc "The kind of a cell: `:land` or `:gap`. A gap is a river cell."
  def kind(%__MODULE__{kinds: kinds}, cell), do: if(elem(kinds, cell) == 0, do: :land, else: :gap)

  @doc "The number of the river of a river cell, from 1. For a land cell: 0."
  def river(%__MODULE__{kinds: kinds}, cell), do: elem(kinds, cell)

  @doc "The number of the land of a land cell, from 0. For a river cell: the number of its river."
  def land(%__MODULE__{lands: lands}, cell), do: elem(lands, cell)

  @doc "The number of rivers."
  def river_count(%__MODULE__{rivers: rivers}), do: tuple_size(rivers)

  @doc "The first row of river `k`."
  def river_start(%__MODULE__{rivers: rivers}, k), do: elem(rivers, k - 1).start

  @doc "The width of river `k` in a column."
  def river_width(%__MODULE__{rivers: rivers}, k, col), do: elem(elem(rivers, k - 1).widths, col)

  @doc "The row of a river cell in its river, from 1 at the south edge."
  def river_row(%__MODULE__{width: width} = grid, cell) do
    div(cell, width) - river_start(grid, river(grid, cell)) + 1
  end

  @doc "The last row of the land before river `k`."
  def edge_row(grid, k), do: river_start(grid, k) - 1

  @doc "The cells that touch a cell."
  def neighbors(%__MODULE__{neighbors: neighbors}, cell), do: elem(neighbors, cell)

  @doc """
  The cells that touch a cell and are in the next row, to the north.
  The cell with the same column number is first.
  """
  def forward(%__MODULE__{forward: forward}, cell), do: elem(forward, cell)

  @doc "The cells that touch a cell and are in the same row."
  def beside(%__MODULE__{beside: beside}, cell), do: elem(beside, cell)

  @doc "The number of cells from a cell to the nest. A river is not an obstacle for this number."
  def nest_distance(%__MODULE__{nest_distance: distances}, cell), do: elem(distances, cell)

  @doc "True if a river cell touches a land cell."
  def touches_bank?(%__MODULE__{kinds: kinds} = grid, cell) do
    Enum.any?(neighbors(grid, cell), &(elem(kinds, &1) == 0))
  end

  @doc "True if a cell touches a cell of land `k`."
  def touches_land?(%__MODULE__{kinds: kinds, lands: lands} = grid, cell, k) do
    Enum.any?(neighbors(grid, cell), &(elem(kinds, &1) == 0 and elem(lands, &1) == k))
  end

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
