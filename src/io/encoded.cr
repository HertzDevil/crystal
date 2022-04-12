# An `IO` that wraps another `IO` with a custom encoding. Bytes written to an
# `IO::Encoded` are converted from UTF-8 to the target encoding, and bytes read
# from an `IO::Encoded` are converted from the target encoding to UTF-8.
#
# ```
# bytes = "ñＡ😂".encode("UTF-16LE") # => Bytes[0xF1, 0x00, 0x21, 0xFF, 0x3D, 0xD8, 0x02, 0xDE]
# inner = IO::Memory.new(bytes)
# io = IO::Encoded.new(inner, "UTF-16LE")
# io.gets_to_end # => "ñＡ😂"
#
# inner = IO::Memory.new
# io = IO::Encoded.new(inner, "UTF-16LE")
# io << "ñＡ😂"
# io.flush
# inner.to_slice # => Bytes[0xF1, 0x00, 0x21, 0xFF, 0x3D, 0xD8, 0x02, 0xDE]
# ```
#
# ### Buffering
#
# `IO::Encoded` includes the `IO::Buffered` module, with mandatory read
# buffering. It may read more bytes than necessary from the wrapped `IO`. This
# can sometimes be mitigated using `IO::Sized`:
#
# ```
# inner = IO::Memory.new("ＡＢＣＤ".encode("UTF-32LE"))
# io = IO::Encoded.new(inner, "UTF-32LE")
# io.read_char # => 'Ａ'
# inner.pos    # => 16
#
# inner = IO::Memory.new("ＡＢＣＤ".encode("UTF-32LE"))
# io = IO::Encoded.new(IO::Sized.new(inner, 4), "UTF-32LE")
# io.read_char # => 'Ａ'
# inner.pos    # => 4
# ```
#
# Writes to an `IO::Encoded` are buffered by default, preserving the encoder's
# internal state between successive writes. This state is not reset until a call
# to `#flush`, `#close`, or `#rewind`:
#
# ```
# inner = IO::Memory.new
# io = IO::Encoded.new(inner, "BIG5-HKSCS")
# io << "\u{00CA}" # LATIN CAPITAL LETTER E WITH CIRCUMFLEX
# io << "\u{0304}" # COMBINING MACRON
# io.flush         # okay, writes "\u{00CA}\u{0304}" to `inner`
# inner.to_slice   # => Bytes[0x88, 0x62]
# io << "\u{00CA}"
# io.close
# inner.to_slice # => Bytes[0x88, 0x62, 0x88, 0x66]
# ```
#
# Unbuffered writes take immediate effect on the wrapped `IO`, but the encoder's
# internal state is reset after every write operation:
#
# ```
# inner = IO::Memory.new
# io = IO::Encoded.new(inner, "BIG5-HKSCS")
# io.sync = true
# io << "\u{00CA}"
# inner.to_slice   # => Bytes[0x88, 0x66]
# io << "\u{0304}" # raises IO::Error
# ```
class IO::Encoded < IO
  include Buffered

  enum InvalidOption
    Fail
    Skip
  end

  # Whether to close the enclosed `IO` when closing this reader.
  property? sync_close : Bool = false

  # Returns `true` if this `IO::Encoded` is closed.
  getter? closed : Bool = false

  @read_buffering = true

  @orig_buffer_raw : Bytes?
  @orig_buffer = Pointer(UInt8).null
  @orig_buffer_left = LibC::SizeT.zero
  @orig_pos : Int64?

  private IN_BUFFER_SIZE = 4 * 1024

  def initialize(@io : IO, encoding : String, *, invalid : InvalidOption = :fail, @sync_close = false)
    # TODO: use `InvalidOption` in `Crystal::Iconv` as well
    @encoder_iconv = Crystal::Iconv.new("UTF-8", encoding, invalid.skip? ? :skip : nil)
    @decoder_iconv = Crystal::Iconv.new(encoding, "UTF-8", invalid.skip? ? :skip : nil)

    @orig_pos = begin
      io.pos.to_i64
    rescue IO::Error
      nil
    end
    @out_pos = 0_i64
  end

  def unbuffered_read(slice : Bytes) : Int32
    check_open

    bytes_written = 0
    out_buffer = slice.to_unsafe
    out_buffer_left = LibC::SizeT.new(slice.size)

    if orig_pos = @orig_pos
      current_pos = begin
        @io.pos.to_i64
      rescue IO::Error
        nil
      end
      if current_pos && current_pos != orig_pos
        raise IO::Error.new "Changing the position of an IO::Encoded's wrapped IO is not allowed"
      end
    end

    while true
      orig_buffer_raw = @orig_buffer_raw || reset_in_buffer
      if @orig_buffer_left == 0
        @orig_buffer = orig_buffer_raw.to_unsafe
        @orig_buffer_left = LibC::SizeT.new(@io.read(orig_buffer_raw))
      end

      # If, after refilling the orig_buffer_raw, we couldn't read new bytes
      # it means we reached the end
      break if @orig_buffer_left == 0

      # Convert bytes using iconv
      old_left = out_buffer_left
      result = @decoder_iconv.convert(pointerof(@orig_buffer), pointerof(@orig_buffer_left), pointerof(out_buffer), pointerof(out_buffer_left))
      byte_count = old_left - out_buffer_left
      bytes_written += byte_count
      @out_pos += byte_count

      # Check for errors
      break unless result == Crystal::Iconv::ERROR

      case Errno.value
      when Errno::EILSEQ
        # For an illegal sequence we just skip one byte and we'll continue next
        @decoder_iconv.handle_invalid(pointerof(@orig_buffer), pointerof(@orig_buffer_left))
      when Errno::EINVAL
        # EINVAL means "An incomplete multibyte sequence has been encountered in the input."
        old_in_buffer_left = @orig_buffer_left

        # On invalid multibyte sequence we try to read more bytes
        # to see if they complete the sequence
        refill_in_buffer

        # If we couldn't read anything new, we raise or skip
        if old_in_buffer_left == @orig_buffer_left
          @decoder_iconv.handle_invalid(pointerof(@orig_buffer), pointerof(@orig_buffer_left))
        end
      when Errno::E2BIG
        # Output buffer (this IO's read buffer) is not large enough, stop reading
        break
      else
        # Not an error we can handle
      end

      # Continue decoding after an error
    end

    @orig_pos = @io.pos.to_i64 if @orig_pos
    bytes_written
  end

  private def reset_in_buffer
    @orig_buffer_raw = orig_buffer_raw = Bytes.new(GC.malloc_atomic(IN_BUFFER_SIZE).as(UInt8*), IN_BUFFER_SIZE)
    @orig_buffer = orig_buffer_raw.to_unsafe
    @orig_buffer_left = LibC::SizeT.new(0)
    orig_buffer_raw
  end

  private def refill_in_buffer
    orig_buffer_raw = @orig_buffer_raw || reset_in_buffer
    buffer_remaining = IN_BUFFER_SIZE - @orig_buffer_left - (@orig_buffer - orig_buffer_raw.to_unsafe)
    if buffer_remaining < 64
      orig_buffer_raw.copy_from(@orig_buffer, @orig_buffer_left)
      @orig_buffer = orig_buffer_raw.to_unsafe
      buffer_remaining = IN_BUFFER_SIZE - @orig_buffer_left
    end
    @orig_buffer_left += LibC::SizeT.new(@io.read(Slice.new(@orig_buffer + @orig_buffer_left, buffer_remaining)))
  end

  def unbuffered_write(slice : Bytes) : Nil
    check_open

    inbuf_ptr = slice.to_unsafe
    inbytesleft = LibC::SizeT.new(slice.size)
    outbuf = uninitialized UInt8[1024]
    while inbytesleft > 0
      outbuf_ptr = outbuf.to_unsafe
      outbytesleft = LibC::SizeT.new(outbuf.size)
      err = @encoder_iconv.convert(pointerof(inbuf_ptr), pointerof(inbytesleft), pointerof(outbuf_ptr), pointerof(outbytesleft))
      if err == Crystal::Iconv::ERROR
        @encoder_iconv.handle_invalid(pointerof(inbuf_ptr), pointerof(inbytesleft))
      end
      byte_count = outbuf.size - outbytesleft
      @io.write(outbuf.to_slice[0, byte_count])
      @out_pos += byte_count
    end

    flush_encoder if sync?
  end

  private def flush_encoder
    outbuf = uninitialized UInt8[1024]
    outbuf_ptr = outbuf.to_unsafe
    outbytesleft = LibC::SizeT.new(outbuf.size)
    err = @encoder_iconv.convert(Pointer(UInt8*).null, Pointer(LibC::SizeT).null, pointerof(outbuf_ptr), pointerof(outbytesleft))
    if err == Crystal::Iconv::ERROR
      @encoder_iconv.handle_invalid(Pointer(UInt8*).null, Pointer(LibC::SizeT).null)
    end
    byte_count = outbuf.size - outbytesleft
    @io.write(outbuf.to_slice[0, byte_count])
    @out_pos += byte_count
  end

  # Returns the current position (in bytes) in this `IO`.
  #
  # If the wrapped `IO`'s position can be obtained, `IO::Encoded` ensures that
  # it is kept in sync with the encoder's own position; if the two positions
  # don't match, subsequent read operations will raise when the read buffer
  # needs to be refilled.
  #
  # ```
  # inner = IO::Memory.new Bytes[0x66, 0x00, 0x6F, 0x00, 0x6F, 0x00]
  # io = IO::Encoded.new(inner, "UTF-16LE")
  # io.read_byte # => 102
  # inner.pos = 0
  # io.gets_to_end # raises IO::Error
  # ```
  def unbuffered_pos
    @out_pos
  end

  # Outputs any remaining bytes needed to reset the encoder to its initial
  # state, then flushes the wrapped `IO`.
  def unbuffered_flush
    flush_encoder
    @io.flush
  end

  def unbuffered_close
    return if @closed
    @closed = true

    @encoder_iconv.close
    @decoder_iconv.close

    @io.close if @sync_close
  end

  # Rewinds the wrapped `IO` and also resets any internal state associated
  # with the encoder.
  def unbuffered_rewind
    flush_encoder
    @io.rewind
    @encoder_iconv.reset
    @decoder_iconv.reset
    reset_in_buffer if @orig_buffer_raw
    @orig_pos = 0_i64 if @orig_pos
    @out_pos = 0_i64
  end

  # Raises if *read_buffering* is falsey, otherwise has no effect. Read
  # buffering is mandatory for instances of `IO::Encoded`.
  def read_buffering=(read_buffering)
    raise "cannot disable read buffering for IO::Encoded"
  end
end
