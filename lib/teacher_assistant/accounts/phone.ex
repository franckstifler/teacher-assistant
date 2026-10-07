defmodule TeacherAssistant.Accounts.Phone do
  @moduledoc """
  A Cameroonian phone number, always stored as `+237XXXXXXXXX` (9 national
  digits starting with 6 — mobile — or 2 — landline). Casting normalises
  whatever the person typed, so `6 77 12 34 56` and `+237677123456` are the
  same value everywhere (sign-in, the Members form, the unique identity).
  """
  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :string

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    case normalize(value) do
      {:ok, phone} -> {:ok, phone}
      {:error, :invalid} -> {:error, message: "is not a valid phone number"}
    end
  end

  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints) when is_binary(value), do: {:ok, value}
  def dump_to_native(_value, _constraints), do: :error

  @doc "`{:ok, \"+237XXXXXXXXX\"}` for a valid Cameroonian number, else `{:error, :invalid}`."
  def normalize(value) when is_binary(value) do
    national =
      case String.replace(value, ~r/[\s.\-()]/, "") do
        "+237" <> rest -> rest
        "00237" <> rest -> rest
        "237" <> rest when byte_size(rest) == 9 -> rest
        rest -> rest
      end

    if national =~ ~r/\A[62]\d{8}\z/,
      do: {:ok, "+237" <> national},
      else: {:error, :invalid}
  end

  def normalize(_value), do: {:error, :invalid}

  @doc "Human format: `6 77 12 34 56`."
  def format(
        "+237" <>
          <<a::binary-size(1), b::binary-size(2), c::binary-size(2), d::binary-size(2),
            e::binary-size(2)>>
      ),
      do: Enum.join([a, b, c, d, e], " ")

  def format(other), do: to_string(other)
end
