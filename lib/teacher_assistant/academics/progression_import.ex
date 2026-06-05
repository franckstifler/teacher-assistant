defmodule TeacherAssistant.Academics.ProgressionImport do
  @moduledoc """
  Imports text-based progression PDFs into teacher progression plans.

  PDF text extraction uses Poppler's `pdftotext` command with layout preservation.
  """

  require Ash.Query

  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Scope

  @type preview_row :: %{
          row: pos_integer(),
          week_number: integer() | nil,
          start_date: Date.t() | nil,
          end_date: Date.t() | nil,
          title: String.t(),
          planned_content: String.t() | nil,
          planned_hours: Decimal.t() | nil,
          duplicate?: boolean(),
          errors: [String.t()]
        }

  def extract_pdf(path) when is_binary(path) do
    with {:ok, command} <- pdftotext_command(),
         {text, 0} <- System.cmd(command, ["-layout", path, "-"], stderr_to_stdout: true),
         text when text != "" <- String.trim(text) do
      {:ok, text}
    else
      {:error, :pdftotext_missing} ->
        {:error, :pdftotext_missing}

      {"", 0} ->
        {:error, :empty_pdf}

      {_output, _status} ->
        {:error, :pdf_extraction_failed}

      "" ->
        {:error, :empty_pdf}
    end
  rescue
    ErlangError -> {:error, :pdftotext_missing}
  end

  def preview_rows(%Scope{} = scope, plan_id, pdf_path) when is_binary(plan_id) do
    with {:ok, plan} <- get_teacher_plan(scope, plan_id),
         {:ok, text} <- extract_pdf(pdf_path) do
      existing_weeks = existing_weeks(scope, plan.id)

      rows =
        text
        |> parse_text()
        |> Enum.map(&mark_duplicate(&1, existing_weeks))

      if rows == [] do
        {:error, :no_progression_rows}
      else
        {:ok, %{plan: plan, rows: rows}}
      end
    end
  end

  def save_rows(%Scope{} = scope, plan_id, rows) when is_binary(plan_id) and is_list(rows) do
    with {:ok, plan} <- get_teacher_plan(scope, plan_id),
         {:ok, attrs} <- validate_rows(rows) do
      entries =
        Enum.map(attrs, fn row ->
          ProgressionEntry
          |> Ash.Changeset.for_create(:create, Map.put(row, :progression_plan_id, plan.id),
            scope: scope
          )
          |> Ash.create!(authorize?: false)
        end)

      {:ok, %{plan: plan, entries: entries}}
    end
  end

  defp pdftotext_command do
    command = Application.get_env(:teacher_assistant, :pdftotext_path, "pdftotext")

    cond do
      Path.type(command) == :absolute and File.exists?(command) ->
        {:ok, command}

      Path.type(command) == :absolute ->
        {:error, :pdftotext_missing}

      executable = System.find_executable(command) ->
        {:ok, executable}

      true ->
        {:error, :pdftotext_missing}
    end
  end

  defp get_teacher_plan(scope, plan_id) do
    ProgressionPlan
    |> Ash.Query.filter(id == ^plan_id and teacher_id == ^scope.current_user.id)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %ProgressionPlan{} = plan} -> {:ok, plan}
      {:ok, nil} -> {:error, :plan_not_found}
      {:error, _error} -> {:error, :plan_not_found}
    end
  end

  defp existing_weeks(scope, plan_id) do
    ProgressionEntry
    |> Ash.Query.filter(progression_plan_id == ^plan_id)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.week_number)
    |> MapSet.new()
  end

  defp parse_text(text) do
    text
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, row_number} ->
      case parse_line(line, row_number) do
        {:ok, row} -> [row]
        :skip -> []
      end
    end)
  end

  defp parse_line(line, row_number) do
    parts =
      line
      |> String.trim()
      |> String.split(~r/\s{2,}|\t+/, trim: true)

    case parts do
      [header | _] when header in ["Week", "Weeks", "Semaine", "Semaines"] ->
        :skip

      [week, start_date, end_date, title, content, hours | rest] ->
        build_preview_row(row_number, %{
          "week_number" => week,
          "start_date" => start_date,
          "end_date" => end_date,
          "title" => title,
          "planned_content" => Enum.join([content | rest], " "),
          "planned_hours" => hours
        })

      [week, title, content, hours | rest] ->
        build_preview_row(row_number, %{
          "week_number" => week,
          "title" => title,
          "planned_content" => Enum.join([content | rest], " "),
          "planned_hours" => hours
        })

      _ ->
        :skip
    end
  end

  defp build_preview_row(row_number, params) do
    case validate_row(params, row_number) do
      {:ok, row} -> {:ok, Map.put(row, :duplicate?, false)}
      {:error, row} -> {:ok, Map.put(row, :duplicate?, false)}
    end
  end

  defp mark_duplicate(%{week_number: week_number} = row, existing_weeks) do
    %{row | duplicate?: !is_nil(week_number) and MapSet.member?(existing_weeks, week_number)}
  end

  defp validate_rows(rows) do
    validated =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} -> validate_row(row, index) end)

    invalid =
      validated
      |> Enum.filter(&match?({:error, _row}, &1))
      |> Enum.map(fn {:error, row} -> row end)

    if invalid == [] do
      attrs =
        Enum.map(validated, fn {:ok, row} ->
          row
          |> Map.take([
            :week_number,
            :start_date,
            :end_date,
            :title,
            :planned_content,
            :planned_hours
          ])
          |> Map.put(:entry_type, :lesson)
        end)

      {:ok, attrs}
    else
      {:error, {:invalid_rows, invalid}}
    end
  end

  defp validate_row(row, row_number) do
    week_result = parse_week(field(row, "week_number"))
    title = required_text(field(row, "title"))
    hours_result = parse_decimal(field(row, "planned_hours", "0"))
    start_date_result = parse_optional_date(field(row, "start_date"))
    end_date_result = parse_optional_date(field(row, "end_date"))

    errors =
      []
      |> add_error(week_result, "Week is required")
      |> add_error(title, "Title is required")
      |> add_error(hours_result, "Hours must be a number")
      |> add_error(start_date_result, "Start date must be YYYY-MM-DD")
      |> add_error(end_date_result, "End date must be YYYY-MM-DD")

    row = %{
      row: row_number,
      week_number: value_or_nil(week_result),
      start_date: value_or_nil(start_date_result),
      end_date: value_or_nil(end_date_result),
      title: title || "",
      planned_content: optional_text(field(row, "planned_content")),
      planned_hours: value_or_nil(hours_result),
      duplicate?: false,
      errors: Enum.reverse(errors)
    }

    if row.errors == [], do: {:ok, row}, else: {:error, row}
  end

  defp add_error(errors, {:error, _reason}, message), do: [message | errors]
  defp add_error(errors, nil, message), do: [message | errors]
  defp add_error(errors, _value, _message), do: errors

  defp value_or_nil({:ok, value}), do: value
  defp value_or_nil(_value), do: nil

  defp parse_week(value) do
    value = to_string(value || "") |> String.trim()

    case Integer.parse(value) do
      {week, ""} when week > 0 -> {:ok, week}
      _ -> {:error, :invalid_week}
    end
  end

  defp parse_decimal(value) do
    value = to_string(value || "") |> String.trim()

    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_decimal}
    end
  end

  defp parse_optional_date(nil), do: {:ok, nil}
  defp parse_optional_date(""), do: {:ok, nil}

  defp parse_optional_date(value) do
    value = String.trim(to_string(value))

    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp required_text(value) do
    value = to_string(value || "") |> String.trim()
    if value == "", do: nil, else: value
  end

  defp optional_text(value) do
    value = to_string(value || "") |> String.trim()
    if value == "", do: nil, else: value
  end

  defp field(row, key, default \\ nil)

  defp field(row, key, default) when is_map(row) do
    Map.get(row, key) || Map.get(row, known_atom_key(key), default)
  end

  defp known_atom_key("week_number"), do: :week_number
  defp known_atom_key("start_date"), do: :start_date
  defp known_atom_key("end_date"), do: :end_date
  defp known_atom_key("title"), do: :title
  defp known_atom_key("planned_content"), do: :planned_content
  defp known_atom_key("planned_hours"), do: :planned_hours
  defp known_atom_key(_key), do: nil
end
