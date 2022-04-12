{% skip_file if flag?(:without_iconv) %}

require "../spec_helper"
{% unless flag?(:win32) %}
  require "socket"
{% end %}
require "big"
require "base64"

private def encoded_io(str : String, encoding : String, *, invalid : IO::Encoded::InvalidOption = :fail)
  IO::Encoded.new(IO::Memory.new(str.encode(encoding)), encoding, invalid: invalid)
end

private def encoded_io(bytes : Bytes, encoding : String, *, invalid : IO::Encoded::InvalidOption = :fail)
  IO::Encoded.new(IO::Memory.new(bytes), encoding, invalid: invalid)
end

private def assert_encodes(bytes : Bytes, encoding : String, *, invalid : IO::Encoded::InvalidOption = :fail, file = __FILE__, line = __LINE__, &)
  inner = IO::Memory.new
  io = IO::Encoded.new(inner, encoding, invalid: invalid)
  io.sync = false
  yield io
  io.close
  inner.to_slice.should eq(bytes), file: file, line: line

  inner = IO::Memory.new
  io = IO::Encoded.new(inner, encoding, invalid: invalid)
  io.sync = true
  yield io
  inner.to_slice.should eq(bytes), file: file, line: line
end

describe IO::Encoded do
  describe "decode" do
    it "gets_to_end" do
      str = "Hello world" * 200
      io = encoded_io(str, "UCS-2LE")
      io.gets_to_end.should eq(str)
    end

    it "gets" do
      str = "Hello world\r\nFoo\nBar"
      io = encoded_io(str, "UCS-2LE")
      io.gets.should eq("Hello world")
      io.gets.should eq("Foo")
      io.gets.should eq("Bar")
      io.gets.should be_nil
    end

    it "gets with chomp = false" do
      str = "Hello world\r\nFoo\nBar"
      io = encoded_io(str, "UCS-2LE")
      io.gets(chomp: false).should eq("Hello world\r\n")
      io.gets(chomp: false).should eq("Foo\n")
      io.gets(chomp: false).should eq("Bar")
      io.gets(chomp: false).should be_nil
    end

    it "gets big string" do
      str = "Hello\nWorld\n" * 10_000
      io = encoded_io(str, "UCS-2LE")
      10_000.times do |i|
        io.gets.should eq("Hello")
        io.gets.should eq("World")
      end
    end

    it "gets big EUC-JP string" do
      2.times do
        str = "好我是人\n" * 1000
        io = encoded_io(str, "EUC-JP")
        1000.times do |i|
          io.gets.should eq("好我是人")
        end
      end
    end

    it "does gets on unicode with char and limit without off-by-one" do
      io = encoded_io("test\nabc", "UCS-2LE")
      io.gets('a', 5).should eq("test\n")
      io = encoded_io("test\nabc", "UCS-2LE")
      io.gets('a', 6).should eq("test\na")
    end

    it "gets with limit" do
      str = "Hello\nWorld\n"
      io = encoded_io(str, "UCS-2LE")
      io.gets(3).should eq("Hel")
    end

    it "gets with limit (small, no newline)" do
      str = "Hello world" * 10_000
      io = encoded_io(str, "UCS-2LE")
      io.gets(3).should eq("Hel")
    end

    it "gets with non-ascii" do
      str = "你好我是人"
      io = encoded_io(str, "UCS-2LE")
      io.gets('人').should eq("你好我是人")
    end

    it "gets with non-ascii and chomp: false" do
      str = "你好我是人"
      io = encoded_io(str, "UCS-2LE")
      io.gets('人', chomp: true).should eq("你好我是")
    end

    it "gets with limit (big)" do
      str = "Hello world" * 10_000
      io = encoded_io(str, "UCS-2LE")
      io.gets(20_000).should eq(str[0, 20_000])
    end

    it "gets with string delimiter" do
      str = "Hello world\nFoo\nBar"
      io = encoded_io(str, "UCS-2LE")
      io.gets("wo").should eq("Hello wo")
      io.gets("oo").should eq("rld\nFoo")
      io.gets("xx").should eq("\nBar")
      io.gets("zz").should be_nil
    end

    it "reads char" do
      str = "Hello world"
      io = encoded_io(str, "UCS-2LE")
      str.each_char do |char|
        io.read_char.should eq(char)
      end
      io.read_char.should be_nil
    end

    it "reads utf8 byte" do
      str = "Hello world"
      io = encoded_io(str, "UCS-2LE")
      str.each_byte do |byte|
        io.read_utf8_byte.should eq(byte)
      end
      io.read_utf8_byte.should be_nil
    end

    it "reads utf8" do
      io = encoded_io("好", "EUC-JP")

      buffer = uninitialized UInt8[1024]
      bytes_read = io.read_utf8(buffer.to_slice) # => 3
      bytes_read.should eq(3)
      buffer.to_slice[0, bytes_read].to_a.should eq("好".bytes)
    end

    it "raises on incomplete byte sequence" do
      io = IO::Encoded.new(IO::Memory.new("好".byte_slice(0, 1)), "EUC-JP")
      expect_raises ArgumentError, "Incomplete multibyte sequence" do
        io.read_char
      end
    end

    it "says invalid byte sequence" do
      io = encoded_io(Bytes[0xFF], "EUC-JP")
      expect_raises ArgumentError, {% if flag?(:musl) %}"Incomplete multibyte sequence"{% else %}"Invalid multibyte sequence"{% end %} do
        io.read_char
      end
    end

    it "skips invalid byte sequences" do
      string = String.build do |str|
        str.write "好".encode("EUC-JP")
        str.write_byte 255_u8
        str.write "是".encode("EUC-JP")
      end
      io = IO::Encoded.new(IO::Memory.new(string), "EUC-JP", invalid: :skip)
      io.read_char.should eq('好')
      io.read_char.should eq('是')
      io.read_char.should be_nil
    end

    # it "sets encoding to utf-8 and stays as UTF-8" do
    #   io = SimpleIOMemory.new(Base64.decode_string("ey8qx+Tl8fwg7+Dw4Ozl8vD7IOLo5+jy4CovfQ=="))
    #   io.set_encoding("utf-8")
    #   io.encoding.should eq("UTF-8")
    # end

    # it "sets encoding to utf8 and stays as UTF-8" do
    #   io = SimpleIOMemory.new(Base64.decode_string("ey8qx+Tl8fwg7+Dw4Ozl8vD7IOLo5+jy4CovfQ=="))
    #   io.set_encoding("utf8")
    #   io.encoding.should eq("UTF-8")
    # end

    it "does skips when converting to UTF-8" do
      io = encoded_io(Base64.decode("ey8qx+Tl8fwg7+Dw4Ozl8vD7IOLo5+jy4CovfQ=="), "UTF-8", invalid: :skip)
      io.gets_to_end.should eq "{/*  */}"
    end

    it "decodes incomplete multibyte sequence with skip (#3285)" do
      bytes = Bytes[195, 229, 237, 229, 240, 224, 246, 232, 255, 32, 241, 234, 240, 232, 239, 242, 224, 32, 48, 46, 48, 49, 50, 54, 32, 241, 229, 234, 243, 237, 228, 10]
      m = encoded_io(bytes, "UTF-8", invalid: :skip)
      m.gets_to_end.should eq("  0.0126 \n")
    end

    it "decodes incomplete multibyte sequence with skip (2) (#3285)" do
      str = File.read(datapath("io_data_incomplete_multibyte_sequence.txt"))
      m = encoded_io(Base64.decode(str), "UTF-8", invalid: :skip)
      m.gets_to_end.bytesize.should eq(4277)
    end

    it "decodes incomplete multibyte sequence with skip (3) (#3285)" do
      str = File.read(datapath("io_data_incomplete_multibyte_sequence_2.txt"))
      m = encoded_io(Base64.decode(str), "UTF-8", invalid: :skip)
      m.gets_to_end.bytesize.should eq(8977)
    end

    it "reads string" do
      str = "Hello world\r\nFoo\nBar"
      io = encoded_io(str, "UCS-2LE")
      io.read_string(11).should eq("Hello world")
      io.gets_to_end.should eq("\r\nFoo\nBar")
    end

    pending_win32 "gets ascii from socket (#9056)" do
      server = TCPServer.new "localhost", 0
      sock = TCPSocket.new "localhost", server.local_address.port
      writer = IO::Encoded.new(sock, "ascii")
      writer.sync = true
      begin
        spawn do
          client = server.accept
          message = client.gets
          client << "#{message}\n"
        end
        writer << "K\n"
        sock.gets.should eq("K")
      ensure
        server.close
        sock.close
      end
    end
  end

  describe "encode" do
    it "prints a string" do
      str = "Hello world"
      assert_encodes(str.encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print str
      end
    end

    it "prints numbers" do
      assert_encodes("0123456789.110.11".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print 0
        io.print 1_u8
        io.print 2_u16
        io.print 3_u32
        io.print 4_u64
        io.print 5_i8
        io.print 6_i16
        io.print 7_i32
        io.print 8_i64
        io.print 9.1_f32
        io.print 10.11_f64
      end
    end

    it "prints bool" do
      assert_encodes("truefalse".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print true
        io.print false
      end
    end

    it "prints char" do
      assert_encodes("a".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print 'a'
      end
    end

    it "prints symbol" do
      assert_encodes("foo".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print :foo
      end
    end

    it "prints big int" do
      assert_encodes("123456".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.print 123_456.to_big_i
      end
    end

    it "puts" do
      assert_encodes("1\n\n".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.puts 1
        io.puts
      end
    end

    it "printf" do
      assert_encodes("hi-123-45.67".encode("UCS-2LE"), "UCS-2LE") do |io|
        io.printf "%s-%d-%.2f", "hi", 123, 45.67
      end
    end

    it "raises on invalid byte sequence" do
      io = IO::Encoded.new(IO::Memory.new, "EUC-JP")
      io.sync = true
      expect_raises ArgumentError, "Invalid multibyte sequence" do
        io.print "\xff"
      end
    end

    it "skips on invalid byte sequence" do
      io = IO::Encoded.new(IO::Memory.new, "EUC-JP", invalid: :skip)
      io.print "ñ"
      io.print "foo"
    end

    it "raises on incomplete byte sequence" do
      io = IO::Encoded.new(IO::Memory.new, "EUC-JP")
      io.sync = true
      expect_raises ArgumentError, "Incomplete multibyte sequence" do
        io.print "好".byte_slice(0, 1)
      end
    end
  end

  it "says invalid encoding" do
    expect_raises ArgumentError, "Invalid encoding: FOO" do
      IO::Encoded.new(IO::Memory.new, "FOO")
    end
  end

  # describe "#encoding" do
  #   it "returns \"UTF-8\" if the encoding is not manually set" do
  #     SimpleIOMemory.new.encoding.should eq("UTF-8")
  #   end

  #   it "returns the name of the encoding set via #set_encoding" do
  #     io = SimpleIOMemory.new
  #     io.set_encoding("UTF-16LE")
  #     io.encoding.should eq("UTF-16LE")
  #   end
  # end
end
