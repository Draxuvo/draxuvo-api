module Whatsapp
  # Catálogo de los tipos de mensaje que manda Draxuvo por WhatsApp (spec 047): cuántas variables espera la plantilla de
  # cada uno, el nombre y el idioma que se sugieren al crearla en Meta y su guía (texto y significado de cada variable).
  # Es solo lectura: lo que el super admin cambia vive en `WhatsappMessageType`.
  class MessageTypes
    Definition = Struct.new(:kind, :uses_template, :expected_variables, :suggested_name, :suggested_language, :category, keyword_init: true) do
      def uses_template? = uses_template

      # Guía para crear la plantilla en Meta; null si el tipo no usa plantilla (tickets).
      def guide(locale: I18n.locale)
        return nil unless uses_template?

        {
          kind: kind, name: suggested_name, language: suggested_language, category: category,
          body: I18n.t("whatsapp_admin.guide.#{kind}.body", locale: locale),
          variables: Array(I18n.t("whatsapp_admin.guide.#{kind}.variables", locale: locale)).each_with_index.map do |meaning, index|
            { position: index + 1, meaning: meaning }
          end
        }
      end

      # Nombre del tipo en una frase («los avisos de stock bajo»).
      def label(locale: I18n.locale) = I18n.t("whatsapp_admin.targets.#{kind}", locale: locale)
    end

    DEFINITIONS = {
      "verification_code" => Definition.new(kind: "verification_code", uses_template: true, expected_variables: 1,
                                            suggested_name: "verification_code", suggested_language: "es_MX", category: "UTILITY"),
      "stock_alert" => Definition.new(kind: "stock_alert", uses_template: true, expected_variables: 3,
                                      suggested_name: "stock_bajo", suggested_language: "es_MX", category: "UTILITY"),
      "ticket" => Definition.new(kind: "ticket", uses_template: false, expected_variables: nil,
                                 suggested_name: nil, suggested_language: nil, category: nil)
    }.freeze

    def self.fetch(kind) = DEFINITIONS.fetch(kind.to_s)

    def self.all = DEFINITIONS.values

    def self.with_template = all.select(&:uses_template?)
  end
end
