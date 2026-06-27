defmodule TeacherAssistant.Academics.FicheParser do
  @moduledoc """
  Pure, deterministic parser: turns `pdftotext -layout` text from a fiche de
  progression into draft progression rows. Never raises; returns low confidence
  with the raw text when it cannot find a table.
  """

  @type row :: %{
          module: String.t(),
          lesson_title: String.t(),
          planned_hours: Decimal.t(),
          entry_type: atom(),
          week_no: integer() | nil,
          sequence_no: integer() | nil
        }

  # Column keyword groups (bilingual). Order here is the field priority.
  @groups [
    {:module, ~r/module|chapitre|chapter|th[eè]me|theme/iu},
    {:lesson, ~r/le[cç]on|lesson|contenu|content|intitul|titre|title/iu},
    {:hours, ~r/dur[eé]e|duree|heures?|hours?|volume/iu},
    {:week, ~r/semaine|week/iu},
    {:sequence, ~r/s[eé]quence|sequence/iu}
  ]

  @spec parse(String.t()) :: {:ok, %{rows: [row], confidence: :high | :low, raw_text: String.t()}}
  def parse(text) when is_binary(text) do
    lines = clean_lines(text)

    case find_header(lines) do
      nil ->
        {:ok, %{rows: [], confidence: :low, raw_text: text}}

      {header_index, columns} ->
        rows =
          lines
          |> Enum.drop(header_index + 1)
          |> build_rows(columns)

        confidence = if rows == [], do: :low, else: :high
        {:ok, %{rows: rows, confidence: confidence, raw_text: text}}
    end
  end

  def parse(_), do: {:ok, %{rows: [], confidence: :low, raw_text: ""}}

  # --- header detection -----------------------------------------------------

  # Returns {line_index, [{field, start_col}]} sorted by start_col, or nil.
  defp find_header(lines) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, idx} ->
      cols = header_columns(line)
      if length(cols) >= 2, do: {idx, Enum.sort_by(cols, &elem(&1, 1))}, else: nil
    end)
  end

  defp header_columns(line) do
    @groups
    |> Enum.flat_map(fn {field, regex} ->
      case Regex.run(regex, line, return: :index) do
        [{start, _len} | _] ->
          # Convert byte offset (from regex) to character offset using the header line
          char_offset = byte_offset_to_char_offset(line, start)
          [{field, char_offset}]

        _ ->
          []
      end
    end)
  end

  # --- row building ---------------------------------------------------------

  defp build_rows(data_lines, columns) do
    {rows, _module} =
      Enum.reduce(data_lines, {[], ""}, fn line, {acc, current_module} ->
        cells = slice_cells(line, columns)
        module_cell = String.trim(cell(cells, :module))
        lesson = String.trim(cell(cells, :lesson))
        current_module = if module_cell == "", do: current_module, else: module_cell

        if lesson == "" do
          {acc, current_module}
        else
          row = %{
            module: current_module,
            lesson_title: lesson,
            planned_hours: parse_hours(cell(cells, :hours)),
            entry_type: :lesson,
            week_no: nil,
            sequence_no: nil
          }

          {[row | acc], current_module}
        end
      end)

    Enum.reverse(rows)
  end

  # Slice the line into %{field => substring} by column start positions (character offsets).
  defp slice_cells(line, columns) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {{field, char_start}, i} ->
      char_stop =
        case Enum.at(columns, i + 1) do
          {_f, next_char_start} -> next_char_start
          nil -> String.length(line)
        end

      {field, String.slice(line, char_start, max(char_stop - char_start, 0))}
    end)
    |> Map.new()
  end

  # Convert byte offset (from Regex.run) to character offset.
  # Clamps offset to binary size to avoid raising.
  defp byte_offset_to_char_offset(binary, byte_offset) do
    clamped = min(byte_offset, byte_size(binary))
    binary |> binary_part(0, clamped) |> String.length()
  end

  defp cell(cells, field), do: Map.get(cells, field, "")

  defp parse_hours(text) do
    normalized = text |> to_string() |> String.replace(",", ".")

    case Regex.run(~r/\d+(\.\d+)?/, normalized) do
      [match | _] -> Decimal.new(match)
      _ -> Decimal.new("1")
    end
  end

  # --- cleaning -------------------------------------------------------------

  defp clean_lines(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&boilerplate?/1)
  end

  defp boilerplate?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      Regex.match?(~r/r[eé]publique du cameroun|minesec|page\s+\d+|^\d+$/iu, trimmed)
  end
end
