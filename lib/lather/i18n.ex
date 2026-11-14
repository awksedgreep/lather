defmodule Lather.I18n do
  @moduledoc """
  Minimal translation table for the built-in web pages (`?dashboard`,
  `?docs`, `?history`).

  ## Examples

      iex> Lather.I18n.t("operations", "en")
      "Operations"

      iex> Lather.I18n.t("operations", "es")
      "Operaciones"

      iex> Lather.I18n.t("operations", "de")
      "Operationen"
  """

  @translations %{
    "en" => %{
      "dashboard" => "Service Dashboard",
      "operations" => "Operations",
      "requests" => "Requests",
      "errors" => "Errors",
      "avg_duration" => "Avg duration",
      "uptime" => "Uptime",
      "recent_requests" => "Recent requests",
      "docs" => "API Documentation",
      "parameters" => "Parameters",
      "required" => "required",
      "description" => "Description"
    },
    "es" => %{
      "dashboard" => "Panel de Servicio",
      "operations" => "Operaciones",
      "requests" => "Solicitudes",
      "errors" => "Errores",
      "avg_duration" => "Duración promedio",
      "uptime" => "Tiempo activo",
      "recent_requests" => "Solicitudes recientes",
      "docs" => "Documentación de la API",
      "parameters" => "Parámetros",
      "required" => "obligatorio",
      "description" => "Descripción"
    },
    "de" => %{
      "dashboard" => "Service-Dashboard",
      "operations" => "Operationen",
      "requests" => "Anfragen",
      "errors" => "Fehler",
      "avg_duration" => "Durchschnittliche Dauer",
      "uptime" => "Verfügbarkeitszeit",
      "recent_requests" => "Letzte Anfragen",
      "docs" => "API-Dokumentation",
      "parameters" => "Parameter",
      "required" => "erforderlich",
      "description" => "Beschreibung"
    }
  }

  def languages do
    Map.keys(@translations)
  end

  def t(key, lang \\ "en") do
    lang = String.downcase(lang)

    case Map.get(@translations, lang) do
      nil -> Map.get(@translations["en"], key, key)
      table -> Map.get(table, key, Map.get(@translations["en"], key, key))
    end
  end
end
