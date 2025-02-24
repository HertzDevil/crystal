require "../dwarf"
require "./abbrev"

module Crystal
  module DWARF
    struct Info
      property unit_length : UInt32 | UInt64
      property version : UInt16
      property unit_type : UInt8
      property debug_abbrev_offset : UInt32 | UInt64
      property address_size : UInt8
      property! abbreviations : Array(Abbrev)

      property dwarf64 : Bool
      @offset : Int64
      @ref_offset : Int64

      def initialize(@io : IO::FileDescriptor, @offset)
        @ref_offset = offset

        @unit_length = @io.read_bytes(UInt32)
        if @unit_length == 0xffffffff
          @dwarf64 = true
          @unit_length = @io.read_bytes(UInt64)
        else
          @dwarf64 = false
        end

        @offset = @io.tell
        @version = @io.read_bytes(UInt16)

        if @version < 2 || @version > 5
          raise "Unsupported DWARF version #{@version}"
        end

        if @version >= 5
          @unit_type = @io.read_bytes(UInt8)
          @address_size = @io.read_bytes(UInt8)
          @debug_abbrev_offset = read_ulong
        else
          @unit_type = 0
          @debug_abbrev_offset = read_ulong
          @address_size = @io.read_bytes(UInt8)
        end

        if @address_size.zero?
          raise "Invalid address size: 0"
        end
      end

      def each(&)
        end_offset = @offset + @unit_length
        attributes = [] of Attribute

        while @io.tell < end_offset
          code = DWARF.read_unsigned_leb128(@io)
          abbrev = @abbreviations.try &.[code &- 1]? # abbreviations.find { |a| a.code == abbrev }
          next unless abbrev

          attributes.clear
          abbrev.attributes.each do |attr|
            form_id = attr.form
            if form_id == FORM::Indirect
              form_id = FORM.new(DWARF.read_unsigned_leb128(@io))
            end

            if attribute = read_attribute?(attr.at, form_id, attr.value)
              attributes << attribute
            else
              # Not an attribute we care
              skip_attribute_value(form_id)
            end
          end
          yield abbrev, attributes
        end
      end

      private def read_attribute?(at_id : AT, form_id : FORM, implicit_const_value : Int) : Attribute?
        case at_id
        when AT::DW_AT_name
          value = read_string_attribute_value?(form_id)
          raise "Invalid form for attribute value #{at_id}: #{form_id}" unless value
          AttributeName.new(value)
        when AT::DW_AT_low_pc
          value = read_address_attribute_value?(form_id)
          raise "Invalid form for attribute value #{at_id}: #{form_id}" unless value
          AttributeLowPc.new(value)
        when AT::DW_AT_high_pc
          value = read_address_attribute_value?(form_id)
          value ||= read_constant_attribute_value?(form_id, implicit_const_value)
          raise "Invalid form for attribute value #{at_id}: #{form_id}" unless value
          AttributeHighPc.new(value)
        end
      end

      private def read_string_attribute_value?(form_id : FORM) : AttributeClass::String?
        case form_id
        when FORM::String
          FormString.new(@io.gets('\0', chomp: true).not_nil!)
        when FORM::Strp
          offset = @dwarf64 ? @io.read_bytes(UInt64) : @io.read_bytes(UInt32).to_u64!
          FormStrp.new(offset)
        when FORM::LineStrp
          offset = @dwarf64 ? @io.read_bytes(UInt64) : @io.read_bytes(UInt32).to_u64!
          FormLineStrp.new(offset)
        end
      end

      private def read_address_attribute_value?(form_id : FORM) : AttributeClass::Address?
        case form_id
        when FORM::Addr
          address =
            case address_size
            when 4 then @io.read_bytes(UInt32)
            when 8 then @io.read_bytes(UInt64)
            else        raise "Invalid address size: #{address_size}"
            end
          FormAddr.new(LibC::SizeT.new(address))
        end
      end

      private def read_constant_attribute_value?(form_id : FORM, implicit_const_value : Int) : AttributeClass::Constant?
        case form_id
        when FORM::Data1
          FormData.new(@io.read_byte.not_nil!)
        when FORM::Data2
          FormData.new(@io.read_bytes(UInt16))
        when FORM::Data4
          FormData.new(@io.read_bytes(UInt32))
        when FORM::Data8
          FormData.new(@io.read_bytes(UInt64))
        when FORM::Data16
          FormData.new(@io.read_bytes(UInt128))
        when FORM::Sdata
          FormData.new(DWARF.read_signed_leb128(@io))
        when FORM::Udata
          FormData.new(DWARF.read_unsigned_leb128(@io))
        when FORM::ImplicitConst
          FormData.new(implicit_const_value)
        end
      end

      private def skip_attribute_value(form) : Nil
        case form
        when FORM::Addr
          @io.skip(address_size)
        when FORM::Block1
          @io.skip(@io.read_byte.not_nil!)
        when FORM::Block2
          @io.skip(@io.read_bytes(UInt16))
        when FORM::Block4
          @io.skip(@io.read_bytes(UInt32))
        when FORM::Block
          @io.skip(DWARF.read_unsigned_leb128(@io))
        when FORM::Data1
          @io.skip(1)
        when FORM::Data2
          @io.skip(2)
        when FORM::Data4
          @io.skip(4)
        when FORM::Data8
          @io.skip(8)
        when FORM::Data16
          @io.skip(16)
        when FORM::Sdata
          DWARF.skip_leb128(@io)
        when FORM::Udata
          DWARF.skip_leb128(@io)
        when FORM::ImplicitConst
          # nothing is read
        when FORM::Exprloc
          @io.skip(DWARF.read_unsigned_leb128(@io))
        when FORM::Flag
          @io.skip(1)
        when FORM::FlagPresent
          # nothing is read
        when FORM::SecOffset
          skip_ulong
        when FORM::Ref1
          @io.skip(1)
        when FORM::Ref2
          @io.skip(2)
        when FORM::Ref4
          @io.skip(4)
        when FORM::Ref8
          @io.skip(8)
        when FORM::RefUdata
          DWARF.skip_leb128(@io)
        when FORM::RefAddr
          skip_ulong
        when FORM::RefSig8
          @io.skip(8)
        when FORM::String
          @io.gets('\0', chomp: true)
        when FORM::Strp, FORM::LineStrp
          skip_ulong
        else
          raise "Unknown DW_FORM_#{form.to_s.underscore}"
        end
      end

      private def read_ulong
        if @dwarf64
          @io.read_bytes(UInt64)
        else
          @io.read_bytes(UInt32)
        end
      end

      private def skip_ulong : Nil
        @io.skip(@dwarf64 ? 8 : 4)
      end
    end
  end
end
