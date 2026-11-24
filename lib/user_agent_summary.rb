# Resumen legible del User-Agent para la bitácora de inicios de sesión (spec 073, research R7): «Chrome · macOS»,
# «App · Android». Solo cubre los casos comunes; lo demás es «Desconocido». Sin gemas: es una etiqueta informativa.
module UserAgentSummary
  UNKNOWN = "Desconocido".freeze
  # React Native manda el User-Agent de su cliente HTTP: okhttp en Android y CFNetwork/Darwin en iOS.
  ANDROID_APP = %r{\Aokhttp/}i
  IOS_APP = %r{CFNetwork/.*Darwin/}i

  BROWSERS = [
    [ "Edge", %r{Edg(?:e|A|iOS)?/} ],
    [ "Opera", %r{OPR/|Opera} ],
    [ "Samsung Internet", %r{SamsungBrowser/} ],
    [ "Firefox", %r{Firefox/|FxiOS/} ],
    [ "Chrome", %r{Chrome/|CriOS/} ],
    [ "Safari", %r{Version/[\d.]+.*Safari/} ]
  ].freeze

  SYSTEMS = [
    [ "iPadOS", /iPad/ ],
    [ "iOS", /iPhone|iPod/ ],
    [ "Android", /Android/ ],
    [ "ChromeOS", /CrOS/ ],
    [ "Windows", /Windows/ ],
    [ "macOS", /Macintosh|Mac OS X/ ],
    [ "Linux", /Linux/ ]
  ].freeze

  module_function

  def call(user_agent)
    ua = user_agent.to_s[0, 500]
    return "App · Android" if ua.match?(ANDROID_APP)
    return "App · iOS" if ua.match?(IOS_APP)
    return UNKNOWN unless browser?(ua)

    browser = BROWSERS.find { |_, pattern| ua.match?(pattern) }&.first
    system = SYSTEMS.find { |_, pattern| ua.match?(pattern) }&.first
    parts = [ browser, system ].compact
    parts.empty? ? UNKNOWN : parts.join(" · ")
  end

  def native_app?(user_agent)
    ua = user_agent.to_s
    ua.match?(ANDROID_APP) || ua.match?(IOS_APP)
  end

  def browser?(user_agent)
    user_agent.to_s.start_with?("Mozilla/")
  end
end
