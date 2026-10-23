require "prawn"

module Labels
  # Dibuja un código de barras en el PDF como rectángulos (spec 035). El tipo sale del código tal cual llega:
  # EAN-13 (13 dígitos con verificador válido), EAN-13 con un 0 a la izquierda (12 dígitos, se lee como UPC-A),
  # EAN-8 (8 dígitos con verificador válido) y Code 128 para todo lo demás (letras, otras longitudes, verificador malo),
  # que cualquier lector soporta y devuelve exacto.
  class BarcodeDrawing
    # Ancho ideal de un módulo (la barra más angosta) y el mínimo que una pistola estándar lee (80 % del ideal).
    IDEAL_MODULE_MM = 0.33
    MIN_MODULE_MM = 0.264
    # Zonas en blanco (módulos) a cada lado: EAN-13 11 y 7, EAN-8 7 y 7, Code 128 10 y 10.
    QUIET_ZONES = { ean13: [ 11, 7 ], ean8: [ 7, 7 ], code128: [ 10, 10 ] }.freeze
    GRID_MM = 0.01

    # Un código con caracteres que Code 128 no puede codificar (acentos, emojis…).
    class Unsupported < StandardError; end

    attr_reader :code, :kind, :modules

    def self.for(code) = new(code)

    def initialize(code)
      @code = code.to_s
      raise Unsupported, @code if @code.empty? || !@code.match?(/\A[ -~]+\z/)

      @barcode, @kind = build
      @modules = @barcode.encoding.chars.map { |bit| bit == "1" }
    end

    # Texto que va debajo de las barras.
    def human_text = @code

    def module_count = @modules.size

    def quiet_zone_modules = QUIET_ZONES.fetch(@kind).sum

    # Módulos totales con las zonas en blanco, para saber cuánto ancho pide el código.
    def total_modules = module_count + quiet_zone_modules

    # Ancho de módulo (mm) que cabe en `available_mm`: el ideal si sobra espacio, o el que alcance (puede quedar por
    # debajo del mínimo legible: `readable_in?` lo dice).
    def module_width_mm(available_mm)
      [ IDEAL_MODULE_MM, available_mm.to_f / total_modules ].min
    end

    def readable_in?(available_mm) = module_width_mm(available_mm) >= MIN_MODULE_MM - 1e-9

    # Dibuja las barras centradas en `x`..`x + width` con su base en `y` (puntos). El ancho de módulo se redondea hacia
    # abajo a una cuadrícula de 0.01 mm para que dos barras vecinas no se mezclen al imprimir.
    def draw(pdf, x:, y:, width:, height:)
      module_mm = (module_width_mm(width / Layout::MM_TO_PT) / GRID_MM).floor * GRID_MM
      module_pt = module_mm * Layout::MM_TO_PT
      total_pt = module_count * module_pt
      start = x + ((width - total_pt) / 2.0)
      pdf.fill_color "000000"
      run_start = nil
      (@modules + [ false ]).each_with_index do |bar, index|
        if bar && run_start.nil?
          run_start = index
        elsif !bar && run_start
          pdf.fill_rectangle [ start + (run_start * module_pt), y + height ], (index - run_start) * module_pt, height
          run_start = nil
        end
      end
    end

    private

    def build
      if Barcodes::CheckDigit.valid_ean13?(@code)
        [ Barby::EAN13.new(@code[0, 12]), :ean13 ]
      elsif @code.match?(/\A\d{12}\z/) && Barcodes::CheckDigit.valid_ean13?("0#{@code}")
        # UPC-A es un EAN-13 con un 0 a la izquierda: las barras son las mismas y el lector devuelve los 12 dígitos.
        [ Barby::EAN13.new("0#{@code[0, 11]}"), :ean13 ]
      elsif Barcodes::CheckDigit.valid_ean8?(@code)
        [ Barby::EAN8.new(@code[0, 7]), :ean8 ]
      else
        [ Barby::Code128B.new(@code), :code128 ]
      end
    end
  end
end
