class Crystal::CodeGenVisitor
  private def codegen_primitive_vector_literal(node, target_def, call_args)
    llvm_type = llvm_type(node.type)

    if call_args.any?(&.constant?)
      index = 0
      elements = Array(LLVM::Value).new(llvm_type.vector_size)
      undef_element = nil

      call_args.each do |arg|
        if arg.constant?
          elements << arg
        else
          undef_element ||= llvm_type.element_type.undef
          elements << undef_element
        end
        index += 1
      end

      vector = llvm_context.const_vector(elements)
    else
      vector = llvm_type.undef
    end

    call_args.each_with_index do |arg, i|
      unless arg.constant?
        vector = builder.insert_element vector, arg, int32(i)
      end
    end

    vector
  end

  private def codegen_primitive_vector_extract_element(node, target_def, call_args)
    vector = call_args[0]
    index = call_args[1]

    builder.extract_element vector, index
  end

  private def codegen_primitive_vector_insert_element(node, target_def, call_args)
    vector = call_args[0]
    index = call_args[1]
    element = call_args[2]

    builder.insert_element vector, element, index
  end

  private def codegen_primitive_vector_unaligned_load(node, target_def, call_args)
    target_type = node.type
    pointer = call_args[1]

    load = builder.load(llvm_type(target_type), pointer)
    load.alignment = 1
    load
  end

  private def codegen_primitive_vector_unaligned_store(node, target_def, call_args)
    vector = call_args[0]
    pointer = call_args[1]

    store = builder.store(vector, pointer)
    store.alignment = 1
    store
  end
end
