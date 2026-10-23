require "test_helper"

class Barcodes::CheckDigitTest < ActiveSupport::TestCase
  test "computes the EAN-13 check digit of known codes" do
    assert_equal 1, Barcodes::CheckDigit.ean13("400638133393")
    assert_equal 5, Barcodes::CheckDigit.ean13("200000000001")
    assert_equal 0, Barcodes::CheckDigit.ean13("000000000000")
  end

  test "validates complete EAN-13 and EAN-8 codes" do
    assert Barcodes::CheckDigit.valid_ean13?("4006381333931")
    assert_not Barcodes::CheckDigit.valid_ean13?("4006381333932")
    assert_not Barcodes::CheckDigit.valid_ean13?("400638133393")
    assert_not Barcodes::CheckDigit.valid_ean13?("40063813339A1")
    assert Barcodes::CheckDigit.valid_ean8?("96385074")
    assert_not Barcodes::CheckDigit.valid_ean8?("96385075")
  end

  test "an EAN-8 body gets its digit too" do
    assert_equal 4, Barcodes::CheckDigit.for_digits("9638507")
  end

  test "rejects non-digit input" do
    assert_raises(ArgumentError) { Barcodes::CheckDigit.for_digits("12AB") }
  end

  test "agrees with Barby for every candidate in a range" do
    1_000.times do |n|
      body = "29#{n.to_s.rjust(10, '0')}"
      assert_equal Barby::EAN13.new(body).checksum, Barcodes::CheckDigit.ean13(body)
    end
  end
end
