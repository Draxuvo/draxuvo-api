module Barcodes
  # Dígito verificador de EAN-13 y EAN-8 (suma ponderada 1-3). Un código con el verificador mal lo rechaza todo lector.
  module CheckDigit
    module_function

    # Dígito que le toca a los primeros 12 dígitos (EAN-13) o a los primeros 7 (EAN-8).
    def for_digits(digits)
      text = digits.to_s
      raise ArgumentError, "solo dígitos" unless text.match?(/\A\d+\z/)

      weights = text.reverse.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 3 : 1) }
      (10 - weights % 10) % 10
    end

    def ean13(digits12) = for_digits(digits12)

    def valid_ean13?(code) = valid?(code, 13)

    def valid_ean8?(code) = valid?(code, 8)

    def valid?(code, length)
      text = code.to_s
      text.match?(/\A\d{#{length}}\z/) && for_digits(text[0...-1]) == text[-1].to_i
    end
    private_class_method :valid?
  end
end
