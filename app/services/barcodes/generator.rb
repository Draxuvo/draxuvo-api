module Barcodes
  # Códigos de barras propios (spec 035): 13 dígitos = "29" (rango de uso interno de tienda) + secuencia de 10 dígitos
  # + dígito verificador EAN-13. La secuencia es por empresa y solo avanza: un código generado nunca se reasigna.
  class Generator
    PREFIX = "29".freeze
    SEQUENCE_DIGITS = 10
    MAX_SEQUENCE = (10**SEQUENCE_DIGITS) - 1
    RETRIES = 3

    class SequenceExhausted < StandardError; end

    class << self
      # Reserva `count` códigos nuevos de la empresa, sin asignarlos. Salta los que ya existan en la empresa (propios
      # registrados a mano o importados); esos números quedan consumidos.
      def reserve(company, count)
        codes = []
        while codes.size < count
          need = count - codes.size
          last = advance_sequence(company, need)
          raise SequenceExhausted if last > MAX_SEQUENCE

          candidates = ((last - need + 1)..last).map { |number| build(number) }
          taken = ProductBarcode.where(company_id: company.id, code: candidates).pluck(:code)
          codes.concat(candidates - taken)
        end
        codes
      end

      # A cada producto que no tenga ningún código le agrega uno nuevo. `products` debe traer `barcodes` precargados.
      # Devuelve { generated: [productos que recibieron], already_had: n }.
      def assign(company, products)
        without = products.select { |product| product.barcodes.empty? }
        insert_codes(company, without) if without.any?
        { generated: without, already_had: products.size - without.size }
      end

      def build(number)
        body = "#{PREFIX}#{number.to_s.rjust(SEQUENCE_DIGITS, '0')}"
        "#{body}#{CheckDigit.ean13(body)}"
      end

      private

      # Una sola sentencia atómica: dos personas generando a la vez reciben bloques distintos.
      def advance_sequence(company, count)
        sql = Company.sanitize_sql_array([
          "UPDATE companies SET barcode_sequence = barcode_sequence + ? WHERE id = ? RETURNING barcode_sequence", count, company.id
        ])
        # `uncached`: el caché de consultas guardaría el resultado de un UPDATE idéntico y repetiría el mismo bloque.
        Company.uncached { Company.connection.select_value(sql) }.to_i
      end

      def insert_codes(company, products)
        attempts = 0
        begin
          now = Time.current
          rows = products.zip(reserve(company, products.size)).map do |product, code|
            { company_id: company.id, product_id: product.id, code: code, created_at: now, updated_at: now }
          end
          ProductBarcode.transaction(requires_new: true) { ProductBarcode.insert_all!(rows) }
        rescue ActiveRecord::RecordNotUnique
          # Alguien registró a mano justo uno de esos códigos: se reservan otros.
          attempts += 1
          retry if attempts < RETRIES
          raise
        end
      end
    end
  end
end
