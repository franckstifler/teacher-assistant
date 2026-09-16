defmodule Faker do
  def unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end

defmodule Faker.Team do
  def creature, do: Faker.unique("year")
end

defmodule Faker.Lorem do
  def word, do: Faker.unique("word")
  def sentence, do: Faker.unique("Sentence")
end

defmodule Faker.Cat do
  def name, do: Faker.unique("name")
end

defmodule Faker.Airports do
  def name, do: Faker.unique("sequence")
end

defmodule Faker.Address do
  def city, do: Faker.unique("city")
end

defmodule Faker.Internet do
  def email, do: "#{Faker.unique("user")}@example.test"
end

defmodule Faker.Person do
  def first_name, do: Faker.unique("First")
  def last_name, do: Faker.unique("Last")
end

defmodule Faker.String do
  def base64(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end
end

defmodule Faker.Date do
  def backward(days) when is_integer(days) and days >= 0 do
    Date.utc_today() |> Date.add(-days)
  end
end
