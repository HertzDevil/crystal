require "crystal/dwarf"
{% if flag?(:darwin) %}
  require "./mach_o"
{% else %}
  require "./elf"
{% end %}

struct Exception::CallStack
  @@dwarf_loaded = false
  @@dwarf_line_numbers : Crystal::DWARF::LineNumbers?
  @@dwarf_function_names : Array(Tuple(LibC::SizeT, LibC::SizeT, String))?

  {% if flag?(:win32) %}
    @@coff_symbols : Hash(Int32, Array(Crystal::PE::COFFSymbol))?
  {% end %}

  # :nodoc:
  def self.load_debug_info : Nil
    return if ENV["CRYSTAL_LOAD_DEBUG_INFO"]? == "0"

    unless @@dwarf_loaded
      @@dwarf_loaded = true
      begin
        load_debug_info_impl
      rescue ex
        @@dwarf_line_numbers = nil
        @@dwarf_function_names = nil
        Crystal::System.print_exception "Unable to load dwarf information", ex
      end
    end
  end

  protected def self.decode_line_number(pc)
    load_debug_info
    if ln = @@dwarf_line_numbers
      if row = ln.find(pc)
        return {row.path, row.line, row.column}
      end
    end
    {"??", 0, 0}
  end

  protected def self.decode_function_name(pc)
    load_debug_info
    if fn = @@dwarf_function_names
      fn.each do |(low_pc, high_pc, function_name)|
        return function_name if low_pc <= pc <= high_pc
      end
    end
  end

  protected def self.parse_function_names_from_dwarf(info, strings, line_strings, &)
    info.each do |abbrev, attributes|
      if abbrev.tag.subprogram?
        if record = decode_function_attributes(attributes, strings, line_strings)
          yield *record
        end
      end
    end
  end

  private def self.decode_function_attributes(attributes, strings, line_strings) : {LibC::SizeT, LibC::SizeT, String}?
    name = low_pc = high_pc = pc_size = nil

    attributes.each do |attribute|
      case attribute
      in Crystal::DWARF::AttributeName
        case form = attribute.form
        in Crystal::DWARF::FormString
          name = form.value
        in Crystal::DWARF::FormStrp
          name = strings.try(&.decode(form.value))
        in Crystal::DWARF::FormLineStrp
          name = line_strings.try(&.decode(form.value))
        end
      in Crystal::DWARF::AttributeLowPc
        case form = attribute.form
        in Crystal::DWARF::FormAddr
          low_pc = form.value
        end
      in Crystal::DWARF::AttributeHighPc
        case form = attribute.form
        in Crystal::DWARF::FormAddr
          high_pc = form.value
        in Crystal::DWARF::FormData
          pc_size = form.value
        end
      end
    end

    if low_pc && pc_size
      high_pc = low_pc + pc_size
    end

    if low_pc && high_pc && name
      {low_pc, high_pc, name}
    end
  end
end
