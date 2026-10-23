require "test_helper"

class Barcodes::GeneratorTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  test "codes are 13 digits with the internal prefix and a valid check digit" do
    codes = Barcodes::Generator.reserve(@company, 5)

    assert_equal 5, codes.uniq.size
    codes.each do |code|
      assert_match(/\A29\d{11}\z/, code)
      assert Barcodes::CheckDigit.valid_ean13?(code), "#{code} tiene mal el verificador"
    end
    assert_equal 5, @company.reload.barcode_sequence
  end

  test "each company has its own sequence" do
    first = Barcodes::Generator.reserve(companies(:one), 2)
    other = Barcodes::Generator.reserve(companies(:two), 2)

    assert_equal first, other
  end

  test "never repeats a code across calls, even the ones that were not assigned" do
    first = Barcodes::Generator.reserve(@company, 3)
    second = Barcodes::Generator.reserve(@company, 3)

    assert_empty first & second
    assert_equal 6, @company.reload.barcode_sequence
  end

  test "skips candidates already registered in the company and keeps going until it has enough" do
    taken = Barcodes::Generator.build(2)
    products(:resto_tacos).barcodes.create!(company: @company, code: taken)

    codes = Barcodes::Generator.reserve(@company, 3)

    assert_equal 3, codes.size
    assert_not_includes codes, taken
    assert_equal [ Barcodes::Generator.build(1), Barcodes::Generator.build(3), Barcodes::Generator.build(4) ], codes
  end

  test "a released code is never handed out again" do
    product = products(:resto_sopa)
    code = Barcodes::Generator.assign(@company, [ product ])[:generated].first && product.reload.barcode_codes.first
    product.barcodes.destroy_all

    assert_not_equal code, Barcodes::Generator.reserve(@company, 1).first
  end

  test "assign gives a code only to the products that have none" do
    with_code = products(:resto_tacos)
    without = [ products(:resto_sopa), products(:resto_cola) ]
    list = Product.includes(:barcodes).where(id: [ with_code.id, *without.map(&:id) ]).to_a

    result = Barcodes::Generator.assign(@company, list)

    assert_equal [ without.map(&:id).sort, 1 ], [ result[:generated].map(&:id).sort, result[:already_had] ]
    assert_equal [ "7502000000002" ], with_code.reload.barcode_codes
    without.each { |product| assert_equal 1, product.reload.barcodes.size }
  end

  test "the generated codes are found like any other barcode" do
    product = products(:resto_sopa)
    Barcodes::Generator.assign(@company, [ Product.includes(:barcodes).find(product.id) ])

    assert_equal product, Products::Lookup.call(@company, product.reload.barcode_codes.first)
  end

  test "retries when someone registers a candidate between the check and the insert" do
    product = Product.includes(:barcodes).find(products(:resto_sopa).id)
    original = Barcodes::Generator.method(:reserve)
    calls = 0
    Barcodes::Generator.stub :reserve, ->(company, count) {
      calls += 1
      calls == 1 ? [ ProductBarcode.first&.code || "2900000000011" ].tap { |c| ProductBarcode.find_or_create_by!(company: company, product: products(:resto_tacos), code: c.first) } : original.call(company, count)
    } do
      Barcodes::Generator.assign(@company, [ product ])
    end

    assert_equal 1, product.reload.barcodes.size
    assert_operator calls, :>=, 2
  end
end

# Con conexiones reales (sin la transacción compartida de las pruebas) para que haya concurrencia de verdad.
class Barcodes::GeneratorConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent generation never hands out the same code twice" do
    company = Company.create!(name: "Concurrencia #{SecureRandom.hex(3)}", order_mode: :service)
    # La reserva de conexiones es de 5: cuatro hilos más el de la prueba.
    results = 4.times.map do
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { Barcodes::Generator.reserve(company, 25) } }
    end.map(&:value)

    all = results.flatten
    assert_equal 100, all.size
    assert_equal 100, all.uniq.size
    assert_equal 100, company.reload.barcode_sequence
  ensure
    company&.destroy
  end
end
