defmodule Cemso.CemantixEndpoint do
  require Logger

  def get_score(word, logmsg \\ nil) do
    # Count in days since well-known arbitrary date
    daycount =
      DateTime.now!("Europe/Paris")
      |> DateTime.to_date()
      |> Date.diff(~D[2022-03-02])

    Logger.info(logmsg || "Requesting score for #{inspect(word)}")
    :ok = Kota.await(Cemantix.RateLimiter)

    Req.post("https://cemantix.certitudes.org/score",
      retry: :safe_transient,
      params: [n: daycount],
      retry_delay: fn _ -> 1000 end,
      body: "word=#{word}",
      headers: %{
        "Content-Type" => "application/x-www-form-urlencoded",
        "Origin" => "https://cemantix.certitudes.org",
        "User-Agent" =>
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      }
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"e" => "Je ne connais pas" <> _}}} ->
        {:error, :cemantix_unknown}

      {:ok, %Req.Response{status: 200, body: "Je ne connais pas" <> _}} ->
        {:error, :cemantix_unknown}

      {:ok, %Req.Response{status: 200, body: %{"s" => score}}} when is_number(score) ->
        {:ok, score}

      {:error, reason} when is_exception(reason) ->
        {:error, Exception.message(reason)}

      {:error, reason} ->
        {:error, "unknown error: #{inspect(reason)}"}

      {:ok, resp} ->
        Logger.error("Cemantix returned response: #{inspect(resp.body)}")
        {:error, "bad server response"}
    end
  end
end
