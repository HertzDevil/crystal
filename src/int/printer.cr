# :nodoc:
#
# Implements algorithms for fast integer printing.
module Int::Printer
  {% begin %}
    private DIGITS_FD = "{% for i in 0..9 %}{{ i }}\u{0}{% end %}{% for i in 10..99 %}{{ i }}{% end %}".to_unsafe
    private DIGITS_DD = "{% for i in 0..9 %}0{{ i }}{% end %}{% for i in 10..99 %}{{ i }}{% end %}".to_unsafe
  {% end %}

  private macro head(part)
    part = {{ part }}
    if part < 10
      b.value = 0x30_u8 &+ part
      b += 1
    else
      b.copy_from(DIGITS_FD + (part << 1), 2)
      b += 2
    end
  end

  private macro rest(part)
    b.copy_from(DIGITS_DD + (({{ part }}) << 1), 2)
    b += 2
  end

  private macro print_u32(mode)
    if n < 100
      head(n)
    elsif n < 1_000_000
      if n < 10_000
        f = 167773 &* n # (10 * 2**24 / 1e3).ceil
        head(f >> 24)
        f = (f & ~(UInt32::MAX << 24)) &* 100
        rest(f >> 24)
      else
        f = 429497_u64 &* n # (10 * 2**32 / 1e5).ceil
        head(f >> 32)
        f = (f & ~(UInt64::MAX << 32)) &* 100
        rest(f >> 32)
        f = (f & ~(UInt64::MAX << 32)) &* 100
        rest(f >> 32)
      end
    elsif n < 100_000_000
      f = (281474977_u64 &* n) >> 16 # (10 * 2**48 / 1e7).ceil
      head(f >> 32)
      f = (f & ~(UInt64::MAX << 32)) &* 100
      rest(f >> 32)
      f = (f & ~(UInt64::MAX << 32)) &* 100
      rest(f >> 32)
      f = (f & ~(UInt64::MAX << 32)) &* 100
      rest(f >> 32)
    else
      f = 1441151881_u64 &* n # (10 * 2**57 / 1e9).ceil
      head(f >> 57)
      f = (f & ~(UInt64::MAX << 57)) &* 100
      rest(f >> 57)
      f = (f & ~(UInt64::MAX << 57)) &* 100
      rest(f >> 57)
      f = (f & ~(UInt64::MAX << 57)) &* 100
      rest(f >> 57)
      f = (f & ~(UInt64::MAX << 57)) &* 100
      rest(f >> 57)
    end
  end

  def self.print_base10(buffer : UInt8*, n : UInt32) : Int32
    b = buffer
    print_u32
    (b - buffer).to_i32!
  end

  def self.print_base10(n : UInt8 | UInt16 | UInt32, &)
    buffer = uninitialized UInt8[10]
    ptr = b = buffer.to_unsafe
    print_u32
    yield ptr, (b - ptr).to_i32!, false
  end

  def self.print_base10(n : Int8 | Int16 | Int32, &)
    if n >= 0
      print_base10(n.to_u32!) { |ptr, count, _| yield ptr, count, false }
    else
      print_base10(0_u32 &- n) { |ptr, count, _| yield ptr, count, true }
    end
  end
end

struct Int
  def to_s_ctrl
    String.new(Bytes.new(0))
  end

  def to_s_new(*, precision : Int = 1) : String
    Int::Printer.print_base10(self) do |ptr, count, negative|
      actual_digits = {count, precision}.max

      if negative
        String.new(actual_digits + 1) do |buffer|
          buffer[0] = '-'.ord.to_u8!
          Slice.new(buffer + 1, actual_digits - count).fill('0'.ord.to_u8!)
          (buffer + 1 + actual_digits - count).copy_from(ptr, count)
          {actual_digits + 1, actual_digits + 1}
        end
      else
        String.new(actual_digits) do |buffer|
          Slice.new(buffer, actual_digits - count).fill('0'.ord.to_u8!)
          (buffer + actual_digits - count).copy_from(ptr, count)
          {actual_digits, actual_digits}
        end
      end
    end
  end

  def to_s_newf(*, precision : Int = 1) : String
    if self < 0
      Int::Printer.print_base10(self) do |ptr, count|
        actual_digits = {count, precision}.max
        String.new(actual_digits + 1) do |buffer|
          buffer[0] = '-'.ord.to_u8!
          Slice.new(buffer + 1, actual_digits - count).fill('0'.ord.to_u8!)
          (buffer + 1 + actual_digits - count).copy_from(ptr, count)
          {actual_digits + 1, actual_digits + 1}
        end
      end
    else
      Int::Printer.print_base10(self) do |ptr, count|
        actual_digits = {count, precision}.max
        String.new(actual_digits) do |buffer|
          Slice.new(buffer, actual_digits - count).fill('0'.ord.to_u8!)
          (buffer + actual_digits - count).copy_from(ptr, count)
          {actual_digits, actual_digits}
        end
      end
    end
  end

  def to_s_new : String
    Int::Printer.print_base10(self) do |ptr, count, negative|
      if negative
        String.new(count + 1) do |buffer|
          buffer[0] = '-'.ord.to_u8!
          (buffer + 1).copy_from(ptr, count)
          {count + 1, count + 1}
        end
      else
        String.new(count) do |buffer|
          buffer.copy_from(ptr, count)
          {count, count}
        end
      end
    end
  end

  def to_s_newf : String
    if self < 0
      Int::Printer.print_base10(self) do |ptr, count|
        String.new(count + 1) do |buffer|
          buffer[0] = '-'.ord.to_u8!
          (buffer + 1).copy_from(ptr, count)
          {count + 1, count + 1}
        end
      end
    else
      Int::Printer.print_base10(self) do |ptr, count|
        String.new(count) do |buffer|
          buffer.copy_from(ptr, count)
          {count, count}
        end
      end
    end
  end

  def to_s_ctrl(io : IO)
  end

  def to_s_new(io : IO, *, precision : Int = 1)
    Int::Printer.print_base10(self) do |ptr, count, negative|
      io << '-' if negative
      if precision > count
        (precision - count).times { io << '0' }
      end
      io.write_string(Slice.new(ptr, count))
    end
  end
end

(0..30).each do |pr|
  p (-1234567).to_s_new(precision: pr)
end

RANGES = [
  {1, (0_u32..9_u32)},
  {2, (10_u32..99_u32)},
  {3, (100_u32..999_u32)},
  {4, (1000_u32..9999_u32)},
  {5, (10000_u32..99999_u32)},
  {6, (100000_u32..999999_u32)},
  {7, (1000000_u32..9999999_u32)},
  {8, (10000000_u32..99999999_u32)},
  {9, (100000000_u32..999999999_u32)},
  {10, (1000000000_u32..UInt32::MAX)},
]

RANGES.each do |_, range|
  1000.times do
    x = range.sample
    raise "%08X" % x unless x.to_s == x.to_s_new
  end
end
# exit

require "benchmark"

N = 10000
x = ""
# RANGES.each do |digits, range|
#  Benchmark.ips do |b|
#    b.report("ctrl #{digits}") do
#      N.times { x = range.sample.to_s_ctrl }
#    end
#
#    b.report("old #{digits}") do
#      N.times { x = range.sample.to_s }
#    end
#
#    b.report("new #{digits}") do
#      N.times { x = range.sample.to_s_new }
#    end
#  end
# end

RANGES.each do |digits, range|
  Benchmark.ips do |b|
    b.report("ctrl #{digits}") do
      N.times { x = range.sample.to_s_ctrl }
    end

    b.report("old #{digits}") do
      N.times { x = range.sample.to_s }
    end

    b.report("new1 #{digits}") do
      N.times { x = range.sample.to_s_new }
    end

    b.report("new1f #{digits}") do
      N.times { x = range.sample.to_s_newf }
    end

    b.report("new2 #{digits}") do
      N.times { x = range.sample.to_s_new(precision: 1) }
    end

    b.report("new2f #{digits}") do
      N.times { x = range.sample.to_s_newf(precision: 1) }
    end
  end
end

# RANGES.each do |digits, range|
#  Benchmark.ips do |b|
#    b.report("io ctrl #{digits}") do
#      N.times { x = String.build { |io| range.sample.to_s_ctrl(io) } }
#    end
#
#    b.report("io old #{digits}") do
#      N.times { x = String.build { |io| range.sample.to_s(io) } }
#    end
#
#    b.report("io new #{digits}") do
#      N.times { x = String.build { |io| range.sample.to_s_new(io) } }
#    end
#  end
# end
